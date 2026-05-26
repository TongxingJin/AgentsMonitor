#!/bin/bash
STATUS_FILE="${CLAUDE_STATUS_FILE:-$HOME/.claude-status}"
TIMER_PID_FILE="${STATUS_FILE}.timer-pid"

# Cancel any pending timer
if [ -f "$TIMER_PID_FILE" ]; then
    kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null || true
    rm -f "$TIMER_PID_FILE"
fi

echo "idle" > "$STATUS_FILE"
