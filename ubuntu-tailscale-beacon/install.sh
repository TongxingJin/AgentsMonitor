#!/bin/bash
# Install ubuntu-tailscale-beacon as a systemd user service.
# Usage: ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_NAME="ubuntu-tailscale-beacon"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

# Check dependencies
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required." >&2
    exit 1
fi

if ! command -v avahi-publish-service &>/dev/null; then
    echo "avahi-utils not found. Install for mDNS auto-discovery:"
    echo "  sudo apt install avahi-utils"
fi

# Create systemd user service
mkdir -p "$(dirname "$SERVICE_FILE")"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Agent Status Beacon (HTTP)
After=default.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${SCRIPT_DIR}/tailscale_beacon.py
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable "${SERVICE_NAME}"
systemctl --user start  "${SERVICE_NAME}"
systemctl --user status "${SERVICE_NAME}" --no-pager

echo ""
echo "ubuntu-tailscale-beacon installed and running."
echo "Auto-start is enabled for reboot persistence."
echo "Status:       systemctl --user status ${SERVICE_NAME} --no-pager"
echo "Logs:         journalctl --user -u ${SERVICE_NAME} -f"
echo "Stop:         systemctl --user stop ${SERVICE_NAME}"
