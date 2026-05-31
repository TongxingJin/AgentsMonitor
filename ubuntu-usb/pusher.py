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

        def _normalize_provider(provider_data: dict | None) -> dict | None:
            if not isinstance(provider_data, dict):
                return None
            if "fiveHourFraction" not in provider_data or "weeklyFraction" not in provider_data:
                return None
            out: dict = {
                "fiveHourFraction": float(provider_data["fiveHourFraction"]),
                "weeklyFraction": float(provider_data["weeklyFraction"]),
            }
            if "fiveHourRemainingHours" in provider_data:
                out["fiveHourRemainingHours"] = float(provider_data["fiveHourRemainingHours"])
            if "sevenDayRemainingDays" in provider_data:
                out["sevenDayRemainingDays"] = float(provider_data["sevenDayRemainingDays"])
            if "quotaUpdatedAt" in provider_data:
                out["quotaUpdatedAt"] = float(provider_data["quotaUpdatedAt"])
            return out

        codex_quota = _normalize_provider(data.get("codex") if isinstance(data, dict) else None)
        claude_quota = _normalize_provider(data.get("claude") if isinstance(data, dict) else None)
        quotas = {}
        if codex_quota:
            quotas["codex"] = codex_quota
        if claude_quota:
            quotas["claude"] = claude_quota
        return {"quotas": quotas or None}
    except (OSError, json.JSONDecodeError, KeyError, TypeError):
        pass
    return {"quotas": None}


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
