#!/usr/bin/env python3
"""
Start a minimal Codex session in a PTY, send /status, parse quota percentages,
write to ~/.codex/agent-status/quota.json, then exit.

Sets CODEX_QUOTA_CHECK=1 so all hooks skip themselves and avoid side effects.
No user prompt is sent to the model, so no tokens are consumed.
"""
import fcntl
import json
import os
import re
import select
import shutil
import signal
import struct
import sys
import termios
import time
import pty
from datetime import datetime, timedelta
from typing import Optional, Tuple

QUOTA_FILE = os.path.expanduser("~/.codex/agent-status/quota.json")
LOCK_FILE  = os.path.expanduser("~/.codex/agent-status/quota-check.lock")
DEBUG_FILE = os.path.expanduser("~/.codex/agent-status/quota-debug.txt")
TIMEOUT    = 30  # seconds


def _strip_ansi(text: str) -> str:
    return re.sub(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])", "", text)


def _is_snap_wrapper(path: str) -> bool:
    real_path = os.path.realpath(path)
    return path.startswith("/snap/bin/") or real_path == "/usr/bin/snap"


def _resolve_codex_command() -> str:
    override = os.environ.get("CODEX_QUOTA_COMMAND")
    if override:
        return os.path.expanduser(override)

    candidates = []
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        if not entry:
            continue
        candidate = os.path.join(entry, "codex")
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            candidates.append(candidate)

    for candidate in candidates:
        if not _is_snap_wrapper(candidate):
            return candidate

    fallback = shutil.which("codex")
    if fallback:
        return fallback

    raise FileNotFoundError("Could not find a codex executable in PATH")


def _run() -> Tuple[str, str]:
    master_fd, slave_fd = pty.openpty()
    fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 220, 0, 0))
    codex_cmd = _resolve_codex_command()
    launch_cwd = os.environ.get("PWD") or os.getcwd()
    if not os.path.isdir(launch_cwd):
        launch_cwd = os.path.expanduser("~")

    pid = os.fork()
    if pid == 0:
        os.close(master_fd)
        os.setsid()
        fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
        for fd in range(3):
            os.dup2(slave_fd, fd)
        os.close(slave_fd)
        os.chdir(launch_cwd)
        env = os.environ.copy()
        env["CODEX_QUOTA_CHECK"] = "1"
        if not env.get("TERM") or env.get("TERM") == "dumb":
            env["TERM"] = "xterm-256color"
        os.execve(codex_cmd, [codex_cmd], env)
        sys.exit(1)

    os.close(slave_fd)
    buf = b""
    status_sent = False
    status_retry_sent = False
    skip_update_sent = False
    trust_sent = False
    quota_seen_at = None
    prompt_seen_at = None
    last_booting_seen_at = None
    status_sent_at = None
    start = time.monotonic()

    try:
        while time.monotonic() - start < TIMEOUT:
            r, _, _ = select.select([master_fd], [], [], 0.3)
            if r:
                try:
                    chunk = os.read(master_fd, 8192)
                    if not chunk:
                        break
                    buf += chunk
                except OSError:
                    break

                text = buf.decode("utf-8", errors="replace")
                plain_text = _strip_ansi(text)
                compact_text = re.sub(r"\s+", "", plain_text).lower()

                if not skip_update_sent and "Update available!" in plain_text:
                    os.write(master_fd, b"2\n")
                    skip_update_sent = True
                    time.sleep(0.8)
                    continue

                if not trust_sent and (
                    "trust the contents" in plain_text.lower()
                    or "do you trust" in plain_text.lower()
                    or "doyoutrustthecontentsofthisdirectory" in compact_text
                ):
                    os.write(master_fd, b"\r")
                    trust_sent = True
                    time.sleep(0.8)
                    continue

                if "booting mcp server" in plain_text.lower():
                    last_booting_seen_at = time.monotonic()

                if (
                    ">" in plain_text
                    or "Codex" in plain_text
                    or "cwd:" in plain_text.lower()
                    or "messages" in plain_text.lower()
                ):
                    prompt_seen_at = prompt_seen_at or time.monotonic()

                if status_sent and quota_seen_at is None and (
                    "Weekly limit" in plain_text
                    or "weekly limit" in plain_text
                    or "5h limit" in plain_text
                ):
                    quota_seen_at = time.monotonic()

                if status_sent and quota_seen_at is not None and (
                    "Warning:" in plain_text or time.monotonic() - quota_seen_at > 1.5
                ):
                    os.write(master_fd, b"\x03")  # Ctrl-C to exit
                    time.sleep(0.5)
                    break

            now_monotonic = time.monotonic()
            if (
                not status_sent
                and prompt_seen_at is not None
                and now_monotonic - prompt_seen_at > 2.0
                and (
                    last_booting_seen_at is None
                    or now_monotonic - last_booting_seen_at > 2.5
                )
            ):
                os.write(master_fd, b"/status\r")
                status_sent = True
                status_sent_at = now_monotonic

            if (
                status_sent
                and not status_retry_sent
                and quota_seen_at is None
                and status_sent_at is not None
                and now_monotonic - status_sent_at > 8.0
            ):
                os.write(master_fd, b"/status\r")
                status_retry_sent = True
    finally:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(pid, os.WNOHANG)
        except Exception:
            pass
        try:
            os.close(master_fd)
        except OSError:
            pass

    return buf.decode("utf-8", errors="replace"), codex_cmd


def _next_reset_today_or_tomorrow(raw_time: str, now: datetime) -> datetime:
    hour, minute = map(int, raw_time.split(":"))
    candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if candidate <= now:
        candidate += timedelta(days=1)
    return candidate


def _next_named_reset(raw_time: str, raw_day_month: str, now: datetime) -> Optional[datetime]:
    day_month = raw_day_month.strip()
    for fmt in ("%d %b", "%d %B"):
        try:
            parsed = datetime.strptime(day_month, fmt)
            candidate = now.replace(
                month=parsed.month,
                day=parsed.day,
                hour=int(raw_time.split(":")[0]),
                minute=int(raw_time.split(":")[1]),
                second=0,
                microsecond=0,
            )
            if candidate <= now:
                candidate = candidate.replace(year=candidate.year + 1)
            return candidate
        except ValueError:
            continue
    return None


def _parse(raw: str):
    text = _strip_ansi(raw)
    now = datetime.now()

    m5 = re.search(r"5h limit[^\n]*?(\d+(?:\.\d+)?)%\s+left", text)
    mw = re.search(r"[Ww]eekly limit[^\n]*?(\d+(?:\.\d+)?)%\s+left", text)
    if not m5:
        m5 = re.search(r"\b5h\s+(\d+(?:\.\d+)?)%", text)
    if not mw:
        mw = re.search(r"\bweekly\s+(\d+(?:\.\d+)?)%", text, re.IGNORECASE)

    if not m5 or not mw:
        return None

    payload = {
        "fiveHourFraction": float(m5.group(1)) / 100.0,
        "weeklyFraction": float(mw.group(1)) / 100.0,
        "source": "codex-status",
    }

    five_reset_match = re.search(
        r"5h limit[^\n]*?\(resets\s+(\d{1,2}:\d{2})\)",
        text,
        re.IGNORECASE,
    )
    if five_reset_match:
        reset_at = _next_reset_today_or_tomorrow(five_reset_match.group(1), now)
        payload["fiveHourRemainingHours"] = max((reset_at - now).total_seconds() / 3600.0, 0.0)

    weekly_reset_match = re.search(
        r"[Ww]eekly limit.*?\(resets\s+(\d{1,2}:\d{2})\s+on\s+(\d{1,2}\s+[A-Za-z]+)\)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if weekly_reset_match:
        reset_at = _next_named_reset(
            weekly_reset_match.group(1),
            weekly_reset_match.group(2),
            now,
        )
        if reset_at is not None:
            payload["sevenDayRemainingDays"] = max((reset_at - now).total_seconds() / 86400.0, 0.0)

    return payload


def main():
    # Prevent concurrent quota checks
    if os.path.exists(LOCK_FILE):
        sys.exit(0)

    open(LOCK_FILE, "w").close()
    try:
        raw, codex_cmd = _run()
        plain = _strip_ansi(raw)
        os.makedirs(os.path.dirname(QUOTA_FILE), exist_ok=True)
        with open(DEBUG_FILE, "w") as f:
            f.write(f"codex_cmd={codex_cmd}\n")
            f.write(plain)

        payload = _parse(raw)
        if payload is None:
            print("Could not parse quota from /status output", file=sys.stderr)
            sys.exit(1)

        payload["quotaUpdatedAt"] = time.time()
        with open(QUOTA_FILE, "w") as f:
            json.dump(payload, f)
        print(
            "Quota: 5h={:.0%}  weekly={:.0%}".format(
                payload["fiveHourFraction"],
                payload["weeklyFraction"],
            )
        )

        push_url = os.environ.get("QUOTA_PUSH_URL")
        if push_url:
            import urllib.request
            try:
                data = json.dumps(payload).encode()
                req = urllib.request.Request(push_url, data=data, method="POST")
                req.add_header("Content-Type", "application/json")
                urllib.request.urlopen(req, timeout=5)
            except Exception:
                pass
    finally:
        try:
            os.remove(LOCK_FILE)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    main()
