#!/usr/bin/env sh
# Runs the dedicated online server (headless). Usage: tools/server/run_server.sh [port] [fill]
# GODOT can point at the Godot 4.7.2 binary; defaults to `godot` on PATH.
cd "$(dirname "$0")/../.." || exit 1
GODOT="${GODOT:-godot}"
exec "$GODOT" --headless --path . -- --server --port "${1:-7350}" --fill "${2:-4}"
