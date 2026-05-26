#!/bin/bash

# Skip everything when running inside a quota-check session
if [ "${CODEX_QUOTA_CHECK}" = "1" ]; then
    exit 0
fi

STATUS_FILE="${CODEX_STATUS_FILE:-$HOME/.codex/agent-status/status.txt}"

write_status() {
    mkdir -p "$(dirname "$STATUS_FILE")"
    echo "$1" > "$STATUS_FILE"
}
