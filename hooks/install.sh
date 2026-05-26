#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
CODEX_INSTALLER="$SCRIPT_DIR/codex/install.sh"

echo "==> Installing Claude hook scripts to $HOOKS_DIR"
mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/pre_tool_use.sh"  "$HOOKS_DIR/"
cp "$SCRIPT_DIR/post_tool_use.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/stop.sh"          "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR"/*.sh

echo "==> Patching $SETTINGS"

# Create settings.json with empty object if it doesn't exist
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

# Use Python to merge hooks into existing settings (avoids clobbering other keys)
python3 - "$SETTINGS" "$HOOKS_DIR" <<'PYEOF'
import json, sys, os

settings_path = sys.argv[1]
hooks_dir = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

def add_hook(event, command):
    entries = hooks.setdefault(event, [])
    for entry in entries:
        if isinstance(entry, dict) and any(
            h.get("command") == command
            for h in entry.get("hooks", [])
        ):
            return  # already present
    entry = {"hooks": [{"type": "command", "command": command}]}
    if event in ("PreToolUse", "PostToolUse"):
        entry["matcher"] = ""  # match all tools
    entries.append(entry)

add_hook("PreToolUse",  f"{hooks_dir}/pre_tool_use.sh")
add_hook("PostToolUse", f"{hooks_dir}/post_tool_use.sh")
add_hook("Stop",        f"{hooks_dir}/stop.sh")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("  Hooks registered successfully.")
PYEOF

echo "==> Installing Codex hook scripts"
"$CODEX_INSTALLER"

cat <<EOF

Done! Default install now sets up both Claude and Codex.

Claude status file:
  $HOME/.claude-status

Codex status file:
  ${CODEX_STATUS_FILE:-$HOME/.codex/agent-status/status.txt}

To start the Mac beacon:
  cd mac-beacon && swift run
EOF
