#!/bin/bash
set -e

TARGET_DIR="$HOME/.codex/agent-status-hooks"
CONFIG_TOML="$HOME/.codex/config.toml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing Codex status hooks to $TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp "$SCRIPT_DIR"/*.sh "$TARGET_DIR/"
cp "$SCRIPT_DIR"/read_quota.py "$TARGET_DIR/"
chmod +x "$TARGET_DIR"/*.sh
chmod +x "$TARGET_DIR"/read_quota.py
mkdir -p "$HOME/.codex/agent-status"
mkdir -p "$(dirname "$CONFIG_TOML")"

echo "==> Writing hook definitions to $CONFIG_TOML"
python3 - "$CONFIG_TOML" "$TARGET_DIR" <<'PYEOF'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1]).expanduser()
hooks_dir = pathlib.Path(sys.argv[2]).expanduser()

if path.exists():
    text = path.read_text(encoding="utf-8")
else:
    text = ""

for pattern in (
    r"\n?# BEGIN agent-status-hooks.*?# END agent-status-hooks\n?",
    r"\n?# BEGIN agent-status-hooks-state.*?# END agent-status-hooks-state\n?",
):
    text = re.sub(pattern, "\n", text, flags=re.S)

block = f"""
# BEGIN agent-status-hooks
[hooks]
SessionStart = [{{ hooks = [{{ type = "command", command = "{hooks_dir / 'session_start.sh'}" }}] }}]
UserPromptSubmit = [{{ hooks = [{{ type = "command", command = "{hooks_dir / 'user_prompt_submit.sh'}" }}] }}]
PreToolUse = [{{ matcher = "", hooks = [{{ type = "command", command = "{hooks_dir / 'pre_tool_use.sh'}" }}] }}]
PostToolUse = [{{ matcher = "", hooks = [{{ type = "command", command = "{hooks_dir / 'post_tool_use.sh'}" }}] }}]
PermissionRequest = [{{ hooks = [{{ type = "command", command = "{hooks_dir / 'permission_request.sh'}" }}] }}]
Stop = [{{ hooks = [{{ type = "command", command = "{hooks_dir / 'stop.sh'}" }}] }}]
# END agent-status-hooks
"""

path.write_text(text.rstrip() + "\n\n" + block.strip() + "\n", encoding="utf-8")
PYEOF

cat <<EOF

Installed hook scripts.

Runtime scripts have been copied to:
  $TARGET_DIR

Runtime hook definitions have been written to:
  $CONFIG_TOML

This installer treats ~/.codex/config.toml as the source of truth.
It does not rely on ~/.codex/hooks.json.

If these hooks are new or changed, Codex may require review/trust before executing them.
That trust state is stored separately by Codex and is intentionally not faked by this installer.

Status file:
  ${CODEX_STATUS_FILE:-$HOME/.codex/agent-status/status.txt}

EOF
