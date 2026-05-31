#!/usr/bin/env python3
"""
Read Codex and Claude usage from provider usage endpoints, then write
~/.codex/agent-status/quota.json.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from typing import Any, Dict, Optional, Tuple
from urllib import error, request

QUOTA_FILE = os.path.expanduser("~/.codex/agent-status/quota.json")
LOCK_FILE  = os.path.expanduser("~/.codex/agent-status/quota-check.lock")
DEBUG_FILE = os.path.expanduser("~/.codex/agent-status/quota-debug.txt")


def _effective_min_refresh_seconds() -> float:
    raw = os.environ.get("QUOTA_MIN_REFRESH_SECONDS")
    if raw:
        try:
            return max(60.0, float(raw))
        except ValueError:
            pass

    return 300.0


def _load_existing_payload() -> Optional[Dict[str, Any]]:
    data = _read_json(QUOTA_FILE)
    return data if isinstance(data, dict) else None


def _is_payload_fresh(payload: Dict[str, Any], min_interval_sec: float) -> bool:
    ts = payload.get("quotaUpdatedAt")
    if not isinstance(ts, (int, float)):
        return False
    return (time.time() - float(ts)) < min_interval_sec


def _read_json(path: str) -> Optional[Dict[str, Any]]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            obj = json.load(f)
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


def _http_json(url: str, headers: Dict[str, str], body: Optional[Dict[str, Any]] = None, timeout: int = 10) -> Tuple[Optional[int], Optional[Dict[str, Any]], Optional[str]]:
    payload = None
    if body is not None:
        payload = json.dumps(body).encode("utf-8")

    req = request.Request(url=url, data=payload, method="POST" if payload else "GET")
    for k, v in headers.items():
        req.add_header(k, v)

    try:
        with request.urlopen(req, timeout=timeout) as resp:
            status = getattr(resp, "status", 200)
            data = resp.read()
            try:
                obj = json.loads(data.decode("utf-8"))
            except Exception:
                return status, None, "parse error"
            if not isinstance(obj, dict):
                return status, None, "parse error"
            return status, obj, None
    except error.HTTPError as e:
        try:
            data = e.read()
            obj = json.loads(data.decode("utf-8")) if data else None
            if isinstance(obj, dict):
                return e.code, obj, None
        except Exception:
            pass
        return e.code, None, str(e)
    except Exception as e:
        return None, None, str(e)


def _read_codex_access_token() -> Optional[str]:
    auth_path = os.path.expanduser("~/.codex/auth.json")
    data = _read_json(auth_path)
    if not data:
        return None
    tokens = data.get("tokens")
    if not isinstance(tokens, dict):
        return None
    token = tokens.get("access_token")
    return token if isinstance(token, str) and token else None


def _fetch_codex_usage() -> Tuple[Optional[Dict[str, Any]], str]:
    token = _read_codex_access_token()
    if not token:
        return None, "no codex auth"

    status, obj, err = _http_json(
        "https://chatgpt.com/backend-api/wham/usage",
        headers={"Authorization": f"Bearer {token}"},
    )

    if status == 401:
        return None, "auth expired — codex login"
    if status != 200 or obj is None:
        return None, f"http {status}" if status else (err or "network error")

    rl = obj.get("rate_limit")
    if not isinstance(rl, dict):
        return None, "parse error"

    def parse_window(window_obj: Any) -> Tuple[float, Optional[float]]:
        if not isinstance(window_obj, dict):
            return 0.0, None
        used = window_obj.get("used_percent")
        frac = float(used) / 100.0 if isinstance(used, (int, float)) else 0.0
        reset = window_obj.get("reset_at")
        if isinstance(reset, (int, float)):
            remaining = max((float(reset) - time.time()) / 3600.0, 0.0)
            return frac, remaining
        return frac, None

    f_frac, f_hours = parse_window(rl.get("primary_window"))
    w_frac, w_hours = parse_window(rl.get("secondary_window"))

    payload: Dict[str, Any] = {
        "fiveHourFraction": max(0.0, min(1.0, f_frac)),
        "weeklyFraction": max(0.0, min(1.0, w_frac)),
        "quotaUpdatedAt": time.time(),
    }
    if f_hours is not None:
        payload["fiveHourRemainingHours"] = f_hours
    if w_hours is not None:
        payload["sevenDayRemainingDays"] = w_hours / 24.0
    return payload, "ok"


def _read_claude_keychain_token() -> Tuple[Optional[str], Optional[str], Optional[str], Optional[str], Optional[Dict[str, Any]]]:
    if sys.platform != "darwin":
        return None, None, None, None, None

    try:
        acct_proc = subprocess.run(
            ["/usr/bin/security", "find-generic-password", "-s", "Claude Code-credentials"],
            capture_output=True,
            text=True,
            check=False,
        )
        output = (acct_proc.stdout or "") + "\n" + (acct_proc.stderr or "")
        account = None
        for raw_line in output.splitlines():
            line = raw_line.strip()
            if not line.startswith('"acct"'):
                continue
            eq = line.find("=")
            if eq == -1:
                continue
            val = line[eq + 1:].strip()
            if len(val) >= 2 and val[0] == '"' and val[-1] == '"':
                account = val[1:-1]
                break
        if not account:
            return None, None, None, None, None

        pwd_proc = subprocess.run(
            [
                "/usr/bin/security",
                "find-generic-password",
                "-s",
                "Claude Code-credentials",
                "-a",
                account,
                "-w",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        raw = (pwd_proc.stdout or "").strip()
        outer = json.loads(raw)
        oauth = outer.get("claudeAiOauth") if isinstance(outer, dict) else None
        if not isinstance(oauth, dict):
            return None, None, None, None, None
        access = oauth.get("accessToken")
        refresh = oauth.get("refreshToken")
        plan = oauth.get("subscriptionType")
        if isinstance(access, str) and access:
            return (
                access,
                refresh if isinstance(refresh, str) else None,
                plan if isinstance(plan, str) else None,
                account,
                oauth,
            )
        return None, None, None, None, None
    except Exception:
        return None, None, None, None, None


def _write_claude_keychain_tokens(account: str, oauth: Dict[str, Any]) -> bool:
    if sys.platform != "darwin":
        return False

    payload = {"claudeAiOauth": oauth}
    try:
        raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        proc = subprocess.run(
            [
                "/usr/bin/security",
                "add-generic-password",
                "-U",
                "-s",
                "Claude Code-credentials",
                "-a",
                account,
                "-w",
                raw,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        return proc.returncode == 0
    except Exception:
        return False


def _refresh_claude_token(refresh_token: str) -> Optional[Tuple[str, str, int]]:
    status, obj, _ = _http_json(
        "https://platform.claude.com/v1/oauth/token",
        headers={"Content-Type": "application/json"},
        body={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        },
    )
    if status != 200 or obj is None:
        return None
    access = obj.get("access_token")
    refresh = obj.get("refresh_token")
    expires_in = obj.get("expires_in")
    if not isinstance(access, str) or not access:
        return None
    if not isinstance(refresh, str) or not refresh:
        return None
    if not isinstance(expires_in, (int, float)):
        expires_in = 28800
    expires_at_ms = int((time.time() + float(expires_in)) * 1000)
    return access, refresh, expires_at_ms


def _parse_iso8601(value: str) -> Optional[datetime]:
    try:
        if value.endswith("Z"):
            value = value[:-1] + "+00:00"
        return datetime.fromisoformat(value)
    except Exception:
        return None


def _fetch_claude_usage() -> Tuple[Optional[Dict[str, Any]], str]:
    plan: Optional[str] = None
    tokens: list[Tuple[str, Optional[str], Optional[str], Optional[Dict[str, Any]]]] = []

    env_token = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN")
    if env_token:
        tokens.append((env_token, None, None, None))

    access, refresh, plan, account, oauth = _read_claude_keychain_token()
    if access:
        tokens.append((access, refresh, account, oauth))

    if not tokens:
        return None, "auth required — run claude"

    def fetch_with_token(token: str) -> Tuple[Optional[Dict[str, Any]], str, bool]:
        status, obj, err = _http_json(
            "https://api.anthropic.com/api/oauth/usage",
            headers={
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "claude-code/2.1.121",
            },
        )
        if status == 401:
            return None, "unauthorized", True
        if status == 403:
            return None, "re-login: claude /login", False
        if status == 429:
            return None, "rate limited", False
        if status != 200 or obj is None:
            return None, f"http {status}" if status else (err or "network error"), False

        err_obj = obj.get("error") if isinstance(obj, dict) else None
        if isinstance(err_obj, dict) and err_obj.get("type") == "rate_limit_error":
            return None, "rate limited", False

        five = obj.get("five_hour") if isinstance(obj, dict) else None
        seven = obj.get("seven_day") if isinstance(obj, dict) else None
        if not isinstance(five, dict) or not isinstance(seven, dict):
            return None, "parse error", False

        def frac(window_obj: Dict[str, Any]) -> float:
            raw = window_obj.get("utilization")
            if not isinstance(raw, (int, float)):
                raw = window_obj.get("used_percent")
            raw_num = float(raw) if isinstance(raw, (int, float)) else 0.0
            return max(0.0, min(1.0, raw_num / 100.0))

        def remaining_hours(window_obj: Dict[str, Any]) -> Optional[float]:
            reset = window_obj.get("resets_at")
            dt = None
            if isinstance(reset, (int, float)):
                dt = datetime.fromtimestamp(float(reset))
            elif isinstance(reset, str):
                dt = _parse_iso8601(reset)
            if dt is None:
                return None
            return max((dt.timestamp() - time.time()) / 3600.0, 0.0)

        f_hours = remaining_hours(five)
        s_hours = remaining_hours(seven)
        payload: Dict[str, Any] = {
            "fiveHourFraction": frac(five),
            "weeklyFraction": frac(seven),
            "quotaUpdatedAt": time.time(),
        }
        if f_hours is not None:
            payload["fiveHourRemainingHours"] = f_hours
        if s_hours is not None:
            payload["sevenDayRemainingDays"] = s_hours / 24.0
        if plan:
            payload["plan"] = plan
        return payload, "ok", False

    last_error = "auth required — run claude"
    for token, refresh, account, oauth in tokens:
        payload, reason, retryable = fetch_with_token(token)
        if payload is not None:
            return payload, "ok"
        last_error = reason
        if retryable and refresh:
            refreshed = _refresh_claude_token(refresh)
            if refreshed:
                refreshed_access, refreshed_refresh, refreshed_expires_at = refreshed
                if account and isinstance(oauth, dict):
                    updated = dict(oauth)
                    updated["accessToken"] = refreshed_access
                    updated["refreshToken"] = refreshed_refresh
                    updated["expiresAt"] = refreshed_expires_at
                    _write_claude_keychain_tokens(account, updated)

                payload, reason2, _ = fetch_with_token(refreshed_access)
                if payload is not None:
                    return payload, "ok"
                last_error = reason2

    return None, last_error


def main():
    # Prevent concurrent quota checks
    if os.path.exists(LOCK_FILE):
        sys.exit(0)

    open(LOCK_FILE, "w").close()
    try:
        min_refresh = _effective_min_refresh_seconds()
        existing = _load_existing_payload()
        if existing and _is_payload_fresh(existing, min_refresh):
            print("Quota refresh skipped: cached payload still fresh")
            return

        codex_payload, codex_reason = _fetch_codex_usage()
        claude_payload, claude_reason = _fetch_claude_usage()

        payload: Dict[str, Any] = {
            "version": 2,
            "quotaUpdatedAt": time.time(),
            "codex": codex_payload,
            "claude": claude_payload,
            "codexError": None if codex_payload else codex_reason,
            "claudeError": None if claude_payload else claude_reason,
        }

        os.makedirs(os.path.dirname(QUOTA_FILE), exist_ok=True)
        with open(DEBUG_FILE, "w", encoding="utf-8") as f:
            f.write(json.dumps(payload, indent=2, ensure_ascii=False))

        with open(QUOTA_FILE, "w") as f:
            json.dump(payload, f)

        if codex_payload:
            print(
                "Codex quota: 5h={:.0%} weekly={:.0%}".format(
                    codex_payload["fiveHourFraction"],
                    codex_payload["weeklyFraction"],
                )
            )
        else:
            print(f"Codex quota unavailable: {codex_reason}")

        if claude_payload:
            print(
                "Claude quota: 5h={:.0%} weekly={:.0%}".format(
                    claude_payload["fiveHourFraction"],
                    claude_payload["weeklyFraction"],
                )
            )
        else:
            print(f"Claude quota unavailable: {claude_reason}")

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
