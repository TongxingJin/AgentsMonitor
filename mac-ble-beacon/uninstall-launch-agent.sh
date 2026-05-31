#!/bin/bash
set -euo pipefail

LABEL="com.jin.agent-status-ble-beacon"
OLD_LABEL="com.jin.agent-status-beacon"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
OLD_PLIST_PATH="$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
INSTALL_DIR="$HOME/Library/Application Support/AgentStatusBLEBeacon"

echo "==> Unloading LaunchAgent"
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" "$OLD_PLIST_PATH" >/dev/null 2>&1 || true

echo "==> Removing plist"
rm -f "$PLIST_PATH"
rm -f "$OLD_PLIST_PATH"

echo "==> Removing installed runtime files"
rm -rf "$INSTALL_DIR"

cat <<EOF

AgentStatusBLEBeacon LaunchAgent removed.

If you also want to remove logs:
  rm -rf "$HOME/Library/Logs/AgentStatusBLEBeacon"

EOF
