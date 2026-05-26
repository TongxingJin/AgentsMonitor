#!/bin/bash
STATUS_FILE="${CLAUDE_STATUS_FILE:-$HOME/.claude-status}"
TIMER_PID_FILE="${STATUS_FILE}.timer-pid"

HOOK_DATA=$(cat)

# Cancel any leftover timer
if [ -f "$TIMER_PID_FILE" ]; then
    kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null || true
    rm -f "$TIMER_PID_FILE"
fi

echo "working" > "$STATUS_FILE"

# Determine if this tool call requires user approval
NEEDS_APPROVAL=$(echo "$HOOK_DATA" | python3 -c "
import json, sys, re, os, fnmatch

data = json.load(sys.stdin)
tool      = data.get('tool_name', '')
mode      = data.get('permission_mode', 'default')
tool_input = data.get('tool_input', {})

# Bypass mode: nothing needs approval
if mode == 'bypassPermissions':
    print('no'); sys.exit()

# Ask mode: everything needs approval
if mode == 'ask':
    print('yes'); sys.exit()

# Read-only tools never need approval
if tool in {'Read', 'Glob', 'LS', 'Grep', 'WebSearch', 'WebFetch',
            'TodoRead', 'NotebookRead', 'Task'}:
    print('no'); sys.exit()

# acceptEdits mode: Edit-family tools are auto-accepted
if mode == 'acceptEdits' and tool in {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'}:
    print('no'); sys.exit()

# Check explicit allow list in settings.json
settings_path = os.path.expanduser('~/.claude/settings.json')
try:
    with open(settings_path) as f:
        settings = json.load(f)
    for pattern in settings.get('permissions', {}).get('allow', []):
        m = re.match(r'^(\w+)(?:\((.+)\))?\$', pattern)
        if not m:
            continue
        p_tool, p_cmd = m.group(1), m.group(2)
        if p_tool != tool:
            continue
        if p_cmd is None:
            print('no'); sys.exit()
        cmd = tool_input.get('command', tool_input.get('path', ''))
        if fnmatch.fnmatch(str(cmd), p_cmd):
            print('no'); sys.exit()
except Exception:
    pass

print('yes')
" 2>/dev/null)

if [ "$NEEDS_APPROVAL" = "yes" ]; then
    echo "awaiting_approval" > "$STATUS_FILE"
fi
