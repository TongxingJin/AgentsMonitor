#!/usr/bin/env python3
"""
Push agent status to the iPhone app via USB.
Connects to the iproxy tunnel (localhost:9000 → iPhone:9000)
and streams newline-delimited JSON whenever status changes.
"""
import json
import os
import socket
import time
from pathlib import Path

PORT = 9000

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
        codex_quota: dict = {}
        if "fiveHourFraction" in data:
            codex_quota["fiveHourFraction"] = float(data["fiveHourFraction"])
        elif "fiveHourRemainingHours" in data:
            codex_quota["fiveHourFraction"] = float(data["fiveHourRemainingHours"]) / 5.0
        if "weeklyFraction" in data:
            codex_quota["weeklyFraction"] = float(data["weeklyFraction"])
        elif "sevenDayRemainingDays" in data:
            codex_quota["weeklyFraction"] = float(data["sevenDayRemainingDays"]) / 7.0
        if "fiveHourRemainingHours" in data:
            codex_quota["fiveHourRemainingHours"] = float(data["fiveHourRemainingHours"])
        if "sevenDayRemainingDays" in data:
            codex_quota["sevenDayRemainingDays"] = float(data["sevenDayRemainingDays"])
        if "quotaUpdatedAt" in data:
            codex_quota["quotaUpdatedAt"] = float(data["quotaUpdatedAt"])
        if codex_quota:
            return {"quotas": None, "codexQuota": codex_quota}
    except (OSError, json.JSONDecodeError, KeyError, TypeError):
        pass
    return {"quotas": None, "codexQuota": None}


def _build_snapshot() -> dict:
    agents = {k: _read_status(v) for k, v in STATUS_FILES.items()}
    return {"version": 1, "agents": agents, **_read_quota()}


def _run(sock: socket.socket) -> None:
    last = None
    while True:
        snap = json.dumps(_build_snapshot())
        if snap != last:
            sock.sendall((snap + "\n").encode())
            last = snap
        time.sleep(0.5)


def main() -> None:
    while True:
        try:
            print(f"Connecting to iproxy on localhost:{PORT}…")
            with socket.create_connection(("127.0.0.1", PORT), timeout=5) as s:
                print("Connected — pushing status to iPhone via USB")
                _run(s)
        except KeyboardInterrupt:
            print("Stopped.")
            break
        except Exception as e:
            print(f"Connection lost ({e}), retrying in 3s…")
            time.sleep(3)


if __name__ == "__main__":
    main()
