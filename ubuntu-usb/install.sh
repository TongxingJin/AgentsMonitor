#!/bin/bash
# Install USB pusher: iproxy tunnel + status pusher as systemd user services.
# Run after: sudo apt install libimobiledevice-utils usbmuxd

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

# --- iproxy service ---
cat > "$SYSTEMD_DIR/ubuntu-iproxy.service" <<EOF
[Unit]
Description=USB iproxy tunnel to iPhone (port 9000)
After=default.target

[Service]
Type=simple
ExecStart=/usr/bin/iproxy 9000 9000
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

# --- pusher service ---
cat > "$SYSTEMD_DIR/ubuntu-usb-pusher.service" <<EOF
[Unit]
Description=Agent Status USB Pusher
After=ubuntu-iproxy.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${SCRIPT_DIR}/pusher.py
Environment=PYTHONUNBUFFERED=1
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload

echo ""
echo "USB services installed (not started)."
echo "iPhone must be connected via USB and trusted (idevicepair pair)."
echo "Start now:    systemctl --user start ubuntu-iproxy ubuntu-usb-pusher"
echo "Enable boot:  systemctl --user enable ubuntu-iproxy ubuntu-usb-pusher"
echo "Status:       systemctl --user status ubuntu-iproxy ubuntu-usb-pusher --no-pager"
echo "Logs:         journalctl --user -u ubuntu-usb-pusher -f"
