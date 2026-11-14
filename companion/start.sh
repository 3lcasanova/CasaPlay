#!/bin/bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# Starts NihonSub (this Mac only) and the CasaPlay bridge. Press Control-C to stop both.
#
#   bash companion/start.sh

HERE="$(cd "$(dirname "$0")" && pwd)"
NIHONSUB_DIR="${NIHONSUB_DIR:-$HOME/NihonSub}"

[ -f "$NIHONSUB_DIR/server.js" ] || { echo "✗ NihonSub isn't set up yet. Run:  bash companion/setup.sh"; exit 1; }

( cd "$NIHONSUB_DIR" && exec node --import "$HERE/localhost-only.mjs" server.js ) > "$HERE/nihonsub.log" 2>&1 &
NIHONSUB_PID=$!
trap 'kill "$NIHONSUB_PID" 2>/dev/null' EXIT INT TERM
sleep 2
if ! kill -0 "$NIHONSUB_PID" 2>/dev/null; then
  echo "✗ NihonSub didn't start. Last lines of its log:"
  tail -n 8 "$HERE/nihonsub.log"
  exit 1
fi

NIHONSUB_URL="${NIHONSUB_URL:-http://127.0.0.1:3000}" node "$HERE/nihonsub-bridge.mjs"
