#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "==> Compiling AgentStatusBLEBeacon..."
swiftc \
    -framework CoreBluetooth \
    -framework Foundation \
    "$DIR/Sources/AgentStatusBLEBeacon/main.swift" \
    -o "$DIR/AgentStatusBLEBeacon"
echo "==> Built: $DIR/AgentStatusBLEBeacon"
echo ""
echo "Run with:"
echo "  $DIR/AgentStatusBLEBeacon"
