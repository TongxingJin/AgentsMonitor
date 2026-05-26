#!/bin/bash
set -euo pipefail

LABEL="com.jin.agent-status-beacon"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALL_DIR="$HOME/Library/Application Support/AgentStatusBeacon"

echo "==> Unloading LaunchAgent"
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true

echo "==> Removing plist"
rm -f "$PLIST_PATH"

echo "==> Removing installed runtime files"
rm -rf "$INSTALL_DIR"

cat <<EOF

AgentStatusBeacon LaunchAgent removed.

If you also want to remove logs:
  rm -rf "$HOME/Library/Logs/AgentStatusBeacon"

EOF
