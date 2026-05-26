#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "==> Compiling AgentStatusBeacon..."
swiftc \
    -framework CoreBluetooth \
    -framework Foundation \
    "$DIR/Sources/AgentStatusBeacon/main.swift" \
    -o "$DIR/AgentStatusBeacon"
echo "==> Built: $DIR/AgentStatusBeacon"
echo ""
echo "Run with:"
echo "  $DIR/AgentStatusBeacon"
