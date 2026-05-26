#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

write_status "idle"

# Refresh quota in background. read_quota.py uses CODEX_QUOTA_CHECK=1
# so no hooks fire and no tokens are consumed.
python3 "$SCRIPT_DIR/read_quota.py" &>/dev/null &
