#!/bin/bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# Saves your IPTV (Xtream Codes) login into Config/Secrets.xcconfig, which git ignores. CasaPlay adds it to
# its IPTV list by itself the first time it opens, on Apple TV, iPhone and iPad, so nothing has to be typed
# on the Apple TV. Run it again to change the login.
#
# The login is tested with the server first. Nothing secret is printed, the password is typed hidden (so it
# stays out of the shell history), and the login never appears in a command line.
#
#   bash Scripts/setup-xtream.sh
#   Or from the environment:  XTREAM_SERVER=... XTREAM_USERNAME=... XTREAM_PASSWORD=... bash Scripts/setup-xtream.sh

cd "$(dirname "$0")/.." || exit 1
FILE="Config/Secrets.xcconfig"

if ! grep -qx 'Config/Secrets.xcconfig' .gitignore 2>/dev/null; then
  echo "✗ $FILE is not listed in .gitignore, so I'm stopping: no login may end up in git."
  exit 1
fi

server="${XTREAM_SERVER:-}"
user="${XTREAM_USERNAME:-}"
pass="${XTREAM_PASSWORD:-}"
if [ -t 0 ]; then
  [ -n "$server" ] || read -r -p "Portal URL (for example https://iptv.example.org): " server
  [ -n "$user" ]   || read -r -p "Username: " user
  [ -n "$pass" ]   || { read -r -s -p "Password (hidden): " pass; echo; }
fi

server="$(printf '%s' "$server" | tr -d '[:space:]')"
case "$server" in
  http://*) echo "✗ The portal address must start with https:// (Apple blocks plain http on the internet)."; exit 1 ;;
  https://*) server="${server#https://}" ;;
esac
while [ "${server%/}" != "$server" ]; do server="${server%/}"; done

if [ -z "$server" ] || [ -z "$user" ] || [ -z "$pass" ]; then
  echo "✗ The portal address, username and password are all needed."
  exit 1
fi
case "$server" in
  *[!A-Za-z0-9.:-]*) echo "✗ Give only the portal address, like https://iptv.example.org (no path, no login in it)."; exit 1 ;;
esac
# .xcconfig files can't hold some characters; the in-app form (Servers › Add Server) takes anything.
bad='[[:space:]$"\\<>&]|//'
if printf '%s\n%s' "$user" "$pass" | grep -Eq "$bad"; then
  echo "✗ The username or password has a space or one of  \$ \" \\ < > &  or //, which the build settings file can't hold."
  echo "  Add the server inside the app instead: Servers › Add Server."
  exit 1
fi

body="$(mktemp)"
trap 'rm -f "$body"' EXIT
# The login goes to curl through its config on stdin, so it never shows in a process list.
code="$(curl -s -G -o "$body" -w '%{http_code}' --max-time 25 -A 'CasaPlay/1.0' -H 'Accept: application/json' \
  -K - "https://$server/player_api.php" <<EOF
data-urlencode = "username=$user"
data-urlencode = "password=$pass"
EOF
)"
if [ "$code" != "200" ]; then
  echo "✗ The server answered HTTP $code, so I did not save the login. Check the portal address."
  exit 1
fi
if ! python3 - "$body" <<'PY'
import datetime, json, sys
try:
    info = json.load(open(sys.argv[1])).get("user_info") or {}
except Exception:
    sys.exit(2)
if str(info.get("auth")) not in ("1", "True", "true"):
    sys.exit(1)
text = "✓ The server accepted the login"
if info.get("status"):
    text += " (status: %s" % info["status"]
    try:
        text += ", expires %s" % datetime.datetime.fromtimestamp(int(info["exp_date"])).strftime("%Y-%m-%d")
    except Exception:
        pass
    text += ")"
print(text)
PY
then
  echo "✗ The server did not accept this username and password (or doesn't answer like an Xtream Codes server). Nothing was saved."
  exit 1
fi

umask 077
mkdir -p "$(dirname "$FILE")"
tmp="$(mktemp)"
if [ -f "$FILE" ]; then grep -Ev '^(XTREAM_SERVER|XTREAM_USERNAME|XTREAM_PASSWORD)[[:space:]]*=' "$FILE" > "$tmp"; fi
{
  printf 'XTREAM_SERVER = %s\n' "$server"
  printf 'XTREAM_USERNAME = %s\n' "$user"
  printf 'XTREAM_PASSWORD = %s\n' "$pass"
} >> "$tmp"
cat "$tmp" > "$FILE"
rm -f "$tmp"
chmod 600 "$FILE"

echo "✓ Saved. Rebuild and install the app: it adds the IPTV list the first time it opens."
exit 0
