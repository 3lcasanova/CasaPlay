#!/bin/bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# One-time setup on your Mac: gets NihonSub (github.com/Abhishantpadam/NihonSub), installs
# it, and stores your Groq key for it. Safe to run again.
#
#   bash companion/setup.sh

set -e
NIHONSUB_DIR="${NIHONSUB_DIR:-$HOME/NihonSub}"
# The version of NihonSub this bridge was written and checked against.
NIHONSUB_COMMIT="63ae91e2202b20dac8fd20c7c0e29598ce96f4c3"

command -v node >/dev/null || { echo "✗ Node.js is missing. Install it with:  brew install node"; exit 1; }
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 18 ? 0 : 1)' \
  || { echo "✗ Node 18 or newer is needed (this Mac has $(node -v))."; exit 1; }
command -v ffmpeg >/dev/null || { echo "✗ FFmpeg is missing. Install it with:  brew install ffmpeg"; exit 1; }
command -v git >/dev/null || { echo "✗ git is missing."; exit 1; }

if [ ! -d "$NIHONSUB_DIR/.git" ]; then
  echo "• Getting NihonSub into $NIHONSUB_DIR"
  git clone --quiet https://github.com/Abhishantpadam/NihonSub "$NIHONSUB_DIR"
  git -C "$NIHONSUB_DIR" checkout --quiet "$NIHONSUB_COMMIT"
else
  have="$(git -C "$NIHONSUB_DIR" rev-parse HEAD 2>/dev/null || true)"
  if [ "$have" = "$NIHONSUB_COMMIT" ]; then
    echo "✓ NihonSub is already in $NIHONSUB_DIR"
  else
    echo "• NihonSub in $NIHONSUB_DIR is a different version than the one this bridge was checked against. Leaving it as it is."
  fi
fi

echo "• Installing NihonSub's packages"
(cd "$NIHONSUB_DIR" && npm ci --omit=dev --silent)

if [ -f "$NIHONSUB_DIR/.env" ] && grep -q '^GROQ_API_KEY=.\{10,\}' "$NIHONSUB_DIR/.env"; then
  echo "✓ A Groq key is already saved for NihonSub"
else
  echo
  echo "NihonSub uses Groq (Whisper) to hear the Japanese speech. Get a free key at:"
  echo "  https://console.groq.com/keys"
  printf "Paste your Groq key (hidden), or press Return to add it later: "
  read -rs key
  echo
  if [ -n "$key" ]; then
    umask 077
    printf 'PORT=3000\nGROQ_API_KEY=%s\n' "$key" > "$NIHONSUB_DIR/.env"
    echo "✓ Saved to $NIHONSUB_DIR/.env (only you can read it)"
  else
    echo "• Skipped. Add GROQ_API_KEY=... to $NIHONSUB_DIR/.env before making subtitles."
  fi
fi

echo
echo "Done. Start everything with:  bash companion/start.sh"
