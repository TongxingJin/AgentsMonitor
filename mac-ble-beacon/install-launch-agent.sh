#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.jin.agent-status-ble-beacon"
OLD_LABEL="com.jin.agent-status-beacon"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
OLD_PLIST_PATH="$PLIST_DIR/$OLD_LABEL.plist"
LOG_DIR="$HOME/Library/Logs/AgentStatusBLEBeacon"
INSTALL_DIR="$HOME/Library/Application Support/AgentStatusBLEBeacon"
RUN_SCRIPT="$INSTALL_DIR/run-ble-beacon.sh"
BEACON_BINARY="$INSTALL_DIR/AgentStatusBLEBeacon"

mkdir -p "$PLIST_DIR" "$LOG_DIR" "$INSTALL_DIR"

echo "==> Building AgentStatusBLEBeacon"
"$DIR/build.sh"

echo "==> Copying runtime files to $INSTALL_DIR"
cp "$DIR/AgentStatusBLEBeacon" "$BEACON_BINARY"
cp "$DIR/run-ble-beacon.sh" "$RUN_SCRIPT"
chmod +x "$BEACON_BINARY" "$RUN_SCRIPT"

echo "==> Writing LaunchAgent plist"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$RUN_SCRIPT</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>ProcessType</key>
    <string>Background</string>

    <key>StandardOutPath</key>
    <string>$LOG_DIR/stdout.log</string>

    <key>StandardErrorPath</key>
    <string>$LOG_DIR/stderr.log</string>
</dict>
</plist>
EOF

echo "==> Cleaning up legacy LaunchAgent label (if present)"
launchctl bootout "gui/$(id -u)" "$OLD_PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$OLD_PLIST_PATH"

echo "==> Reloading LaunchAgent"
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/$(id -u)/$LABEL"

cat <<EOF

AgentStatusBLEBeacon is now installed as a LaunchAgent.

Label:
  $LABEL

Plist:
  $PLIST_PATH

Logs:
  $LOG_DIR/stdout.log
  $LOG_DIR/stderr.log

Installed runtime:
  $BEACON_BINARY
  $RUN_SCRIPT

Useful commands:
  launchctl print gui/$(id -u)/$LABEL
  launchctl kickstart -k gui/$(id -u)/$LABEL

EOF
