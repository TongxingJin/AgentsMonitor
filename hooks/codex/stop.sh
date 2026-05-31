#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

write_status "idle"

# Refresh quota in background. read_quota.py uses CODEX_QUOTA_CHECK=1
# so no hooks fire and no tokens are consumed.
# Set QUOTA_PUSH_URL (e.g. in ~/.zshrc) to push quota to ubuntu-tailscale-beacon:
#   export QUOTA_PUSH_URL="http://100.91.235.49:8765/quota"
PATH="$HOME/.local/bin:$PATH" QUOTA_PUSH_URL="${QUOTA_PUSH_URL:-}" python3 "$SCRIPT_DIR/read_quota.py" &>/dev/null &
