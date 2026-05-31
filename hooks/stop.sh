#!/bin/bash
STATUS_FILE="${CLAUDE_STATUS_FILE:-$HOME/.claude-status}"
TIMER_PID_FILE="${STATUS_FILE}.timer-pid"

# Cancel any pending timer
if [ -f "$TIMER_PID_FILE" ]; then
    kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null || true
    rm -f "$TIMER_PID_FILE"
fi

echo "idle" > "$STATUS_FILE"

# Refresh provider quotas in background if the shared quota reader exists.
CODEX_QUOTA_READER="$HOME/.codex/agent-status-hooks/read_quota.py"
if [ -f "$CODEX_QUOTA_READER" ]; then
    PATH="$HOME/.local/bin:$PATH" QUOTA_PUSH_URL="${QUOTA_PUSH_URL:-}" python3 "$CODEX_QUOTA_READER" &>/dev/null &
fi
