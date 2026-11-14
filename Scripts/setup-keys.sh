#!/bin/bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# Tests the TMDB, TheTVDB and OpenSubtitles keys against the live services and saves
# the ones that work into Config/Secrets.xcconfig, which git ignores.
#
# For each service:
#   1. A key already in Secrets.xcconfig is tested first and kept if it works.
#   2. Otherwise the key given on the command line (environment) is tested, and saved if it works.
# Other lines in Secrets.xcconfig (for example the OMDb key) are left alone.
# Keys are never printed.
#
#   TMDB_API_KEY=... TVDB_API_KEY=... OPENSUBTITLES_API_KEY=... bash scripts/setup-keys.sh

cd "$(dirname "$0")/.." || exit 1
FILE="Config/Secrets.xcconfig"

if ! grep -qx 'Config/Secrets.xcconfig' .gitignore 2>/dev/null; then
  echo "✗ $FILE is not listed in .gitignore, so I'm stopping: no key may end up in git."
  exit 1
fi

# The value saved in Secrets.xcconfig for a name, or nothing.
current() {
  [ -f "$FILE" ] || return 0
  sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$FILE" | tail -n 1 | tr -d '\r' | sed 's/[[:space:]]*$//'
}

# Prints just the HTTP status of a request (000 when the network can't be reached).
status() { curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$@"; }

test_tmdb() {
  case "$1" in
    *.*) status -H "Authorization: Bearer $1" "https://api.themoviedb.org/3/configuration" ;;
    *)   status "https://api.themoviedb.org/3/configuration?api_key=$1" ;;
  esac
}

test_tvdb() {
  status -X POST -H "Content-Type: application/json" -d "{\"apikey\":\"$1\"}" "https://api4.thetvdb.com/v4/login"
}

test_opensubtitles() {
  status -H "Api-Key: $1" -H "User-Agent: CasaPlay v0.1.0" -H "Accept: application/json" \
    "https://api.opensubtitles.com/api/v1/infos/formats"
}

# Replaces (or adds) one line, leaving every other line as it was.
save() {
  umask 077
  mkdir -p "$(dirname "$FILE")"
  tmp="$(mktemp)"
  if [ -f "$FILE" ]; then grep -v "^$1[[:space:]]*=" "$FILE" > "$tmp"; fi
  printf '%s = %s\n' "$1" "$2" >> "$tmp"
  cat "$tmp" > "$FILE"
  rm -f "$tmp"
  chmod 600 "$FILE"
}

# check_one <label> <NAME in Secrets.xcconfig> <test function> <key from the command line>
check_one() {
  label="$1"; name="$2"; tester="$3"; given="$4"
  have="$(current "$name")"
  if [ -n "$have" ]; then
    code="$($tester "$have")"
    if [ "$code" = "200" ]; then
      echo "✓ $label: the saved key works"
      return 0
    fi
    echo "• $label: the saved key was refused (HTTP $code)"
  else
    echo "• $label: no key saved yet"
  fi
  if [ -n "$given" ]; then
    code="$($tester "$given")"
    if [ "$code" = "200" ]; then
      save "$name" "$given"
      echo "✓ $label: the new key works and is saved"
      return 0
    fi
    echo "✗ $label: the new key was refused (HTTP $code). Copy it again from the website."
  else
    echo "✗ $label: no new key was given"
  fi
  return 1
}

failed=0
check_one "TMDB"          TMDB_API_KEY          test_tmdb          "${TMDB_API_KEY:-}"          || failed=1
check_one "TheTVDB"       TVDB_API_KEY          test_tvdb          "${TVDB_API_KEY:-}"          || failed=1
check_one "OpenSubtitles" OPENSUBTITLES_API_KEY test_opensubtitles "${OPENSUBTITLES_API_KEY:-}" || failed=1

echo
if [ "$failed" = "0" ]; then
  echo "All three keys work. Rebuild the app to pick them up."
else
  echo "Some keys need attention (see above). The app still builds, and you can paste keys in Profile › Online services."
fi
exit 0
