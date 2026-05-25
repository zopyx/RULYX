#!/bin/bash
# RULYX AI Model Development Server
# Start this before testing model downloads in the simulator.
# The simulator can reach http://localhost:8080

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/models"
PORT="${1:-8080}"

echo "Starting RULYX model server on http://localhost:$PORT"
echo "Available models:"
ls -lh "$MODELS_DIR"
echo ""
echo "Press Ctrl+C to stop."

python3 -m http.server "$PORT" --directory "$MODELS_DIR"
