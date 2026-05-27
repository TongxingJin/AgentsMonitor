#!/usr/bin/env python3
"""
ubuntu-beacon: HTTP server that broadcasts agent status for the iOS app.
Reads the same status files as mac-beacon and serves them as JSON.
Advertises via mDNS (avahi) so the iOS app can discover it automatically
over USB or Wi-Fi without any IP configuration.
"""
import json
import os
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

PORT = 8765

STATUS_FILES = {
    "claude": Path(os.environ.get("CLAUDE_STATUS_FILE", Path.home() / ".claude-status")),
    "codex":  Path(os.environ.get("CODEX_STATUS_FILE", Path.home() / ".codex/agent-status/status.txt")),
}
QUOTA_FILE = Path.home() / ".codex/agent-status/quota.json"

_STATUS_MAP = {
    "working":           "working",
    "busy":              "working",
    "running":           "working",
    "idle":              "idle",
    "sleep":             "idle",
    "awaiting_approval": "awaiting_approval",
    "awaiting-approval": "awaiting_approval",
    "approve":           "awaiting_approval",
    "approval":          "awaiting_approval",
    "waiting_approval":  "awaiting_approval",
}


def _read_status(path: Path) -> str:
    try:
        return _STATUS_MAP.get(path.read_text().strip().lower(), "idle")
    except OSError:
        return "idle"


def _read_quota() -> dict:
    try:
        data = json.loads(QUOTA_FILE.read_text())
        if "fiveHourRemainingHours" in data and "sevenDayRemainingDays" in data:
            return {
                "quotas": {
                    "fiveHourRemainingHours": float(data["fiveHourRemainingHours"]),
                    "fiveHourCapacityHours":  5.0,
                    "sevenDayRemainingDays":  float(data["sevenDayRemainingDays"]),
                    "sevenDayCapacityDays":   7.0,
                },
                "codexQuota": None,
            }
        if "fiveHourFraction" in data and "weeklyFraction" in data:
            return {
                "quotas": None,
                "codexQuota": {
                    "fiveHourFraction": float(data["fiveHourFraction"]),
                    "weeklyFraction":   float(data["weeklyFraction"]),
                },
            }
    except (OSError, json.JSONDecodeError, KeyError, TypeError):
        pass
    return {"quotas": None, "codexQuota": None}


def _build_snapshot() -> dict:
    agents = {agent_id: _read_status(path) for agent_id, path in STATUS_FILES.items()}
    return {"version": 1, "agents": agents, **_read_quota()}


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/status":
            body = json.dumps(_build_snapshot()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/quota":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                data = json.loads(body)
                QUOTA_FILE.parent.mkdir(parents=True, exist_ok=True)
                QUOTA_FILE.write_text(json.dumps(data))
                self.send_response(200)
                self.end_headers()
            except (json.JSONDecodeError, OSError):
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # suppress per-request logs


def _advertise_mdns():
    """Advertise _agentbeacon._tcp via avahi-publish-service (blocks until killed)."""
    try:
        subprocess.run(
            ["avahi-publish-service", "AgentBeacon", "_agentbeacon._tcp", str(PORT)],
            check=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        print("avahi-publish-service not available — mDNS disabled. Install avahi-utils to enable auto-discovery.")


if __name__ == "__main__":
    threading.Thread(target=_advertise_mdns, daemon=True).start()

    server = HTTPServer(("0.0.0.0", PORT), _Handler)
    print(f"ubuntu-beacon listening on port {PORT}")
    print(f"Status files: { {k: str(v) for k, v in STATUS_FILES.items()} }")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
