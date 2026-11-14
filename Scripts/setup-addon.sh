#!/bin/bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# Saves your own add-on links (for example TorBox MediaFusion or Absolute Cinema) into
# Config/Secrets.xcconfig, which git ignores. CasaPlay installs them by itself the first time it
# opens, on Apple TV, iPhone and iPad, so nothing has to be typed on the Apple TV.
# Run it once per link; each run keeps the links saved before.
#
# The link is tested first (it must answer with an add-on manifest) and is never printed.
#
#   PERSONAL_ADDON_URL='https://…/manifest.json' bash Scripts/setup-addon.sh

cd "$(dirname "$0")/.." || exit 1
FILE="Config/Secrets.xcconfig"

if ! grep -qx 'Config/Secrets.xcconfig' .gitignore 2>/dev/null; then
  echo "✗ $FILE is not listed in .gitignore, so I'm stopping: no link may end up in git."
  exit 1
fi

link="$(printf '%s' "${PERSONAL_ADDON_URL:-}" | tr -d '[:space:]')"
if [ -z "$link" ]; then
  echo "✗ No link given. Run it like this:"
  echo "  PERSONAL_ADDON_URL='https://…/manifest.json' bash Scripts/setup-addon.sh"
  exit 1
fi

# stremio:// links are https links in disguise.
case "$link" in stremio://*) link="https://${link#stremio://}" ;; esac
case "$link" in
  http://*) echo "✗ The link must start with https://"; exit 1 ;;
  https://*) ;;
  *) link="https://$link" ;;
esac

body="$(mktemp)"
trap 'rm -f "$body"' EXIT
code="$(curl -s -o "$body" -w '%{http_code}' --max-time 25 -H 'Accept: application/json' "$link")"
if [ "$code" != "200" ]; then
  echo "✗ The link answered HTTP $code, so I did not save it. Copy it again from the add-on's website."
  exit 1
fi
if ! python3 - "$body" <<'PY'
import json, sys
try:
    m = json.load(open(sys.argv[1]))
    ok = bool(m.get("id")) and bool(m.get("resources"))
    name = m.get("name", "add-on")
except Exception:
    ok = False
if not ok:
    sys.exit(1)
print("✓ Found: " + name)
PY
then
  echo "✗ That link isn't an add-on manifest, so I did not save it."
  exit 1
fi

# xcconfig files treat // as a comment, so the https:// is left off here; the app puts it back.
value="${link#https://}"
case "$value" in
  *//*|*'$('*) echo "✗ This link has // after the address or a \$( in it, which the build settings file can't hold."; exit 1 ;;
esac

# Several links can be saved, separated by spaces. A new link replaces the saved one for the same
# website (so run it again to change a link) and leaves the others alone.
umask 077
old="$(sed -n 's/^PERSONAL_ADDON_URL[[:space:]]*=[[:space:]]*//p' "$FILE" 2>/dev/null | tail -n 1 | tr -d '\r')"
merged="$(python3 - "$value" "$old" <<'PY'
import sys
new, old = sys.argv[1], sys.argv[2]
host = lambda u: u.split("/", 1)[0].lower()
keep = [u for u in old.split() if host(u) != host(new)]
print(" ".join(keep + [new]))
PY
)"
tmp="$(mktemp)"
[ -f "$FILE" ] && grep -v '^PERSONAL_ADDON_URL[[:space:]]*=' "$FILE" > "$tmp"
printf 'PERSONAL_ADDON_URL = %s\n' "$merged" >> "$tmp"
cat "$tmp" > "$FILE"
rm -f "$tmp"
chmod 600 "$FILE"

echo "✓ Saved ($(printf '%s' "$merged" | wc -w | tr -d ' ') add-on link(s) in total). Rebuild and install the app: it installs them the first time it opens."
exit 0
