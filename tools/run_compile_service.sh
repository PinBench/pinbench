#!/usr/bin/env bash
# Run the arduino-cli compile service locally so the web preview
# (`flutter run -d chrome`) can compile edited/custom sketches instead of only
# the bundled precompiled templates.
#
# Prerequisites:
#   - arduino-cli on PATH, with the AVR core installed:
#       arduino-cli core install arduino:avr
#   - node / npm
#
# Usage:
#   tools/run_compile_service.sh            # listens on :8080
#   PORT=9000 tools/run_compile_service.sh  # custom port
#
# Then launch the web app pointed at it (see the
# "pinbench (web + compile service)" VS Code launch config, or):
#   flutter run -d chrome --dart-define=COMPILE_API_URL=http://localhost:8080
set -euo pipefail

cd "$(dirname "$0")/../compile_service"

if ! command -v arduino-cli &>/dev/null; then
  echo "==> Error: arduino-cli not found on PATH. Install it, then: arduino-cli core install arduino:avr"
  exit 1
fi

if ! arduino-cli core list 2>/dev/null | grep -qi 'arduino:avr'; then
  echo "==> Warning: arduino:avr core not detected. Install it with: arduino-cli core install arduino:avr"
fi

if [ ! -d node_modules ]; then
  echo "==> Installing compile service dependencies…"
  npm install
fi

PORT="${PORT:-8080}"
echo "==> Starting compile service on :${PORT} (Ctrl-C to stop)"
PORT="${PORT}" exec node server.js
