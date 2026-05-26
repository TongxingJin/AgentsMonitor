#!/bin/bash
STATUS_FILE="${CLAUDE_STATUS_FILE:-$HOME/.claude-status}"
TIMER_PID_FILE="${STATUS_FILE}.timer-pid"

# Cancel the pending awaiting_approval timer (tool finished normally)
if [ -f "$TIMER_PID_FILE" ]; then
    kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null || true
    rm -f "$TIMER_PID_FILE"
fi

# Always restore working — covers the case where the 5s timer fired during a slow tool
echo "working" > "$STATUS_FILE"
