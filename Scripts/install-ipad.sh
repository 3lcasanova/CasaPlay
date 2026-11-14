#!/usr/bin/env bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# Builds CasaPlay for iPad and installs it on an iPad that is connected to this Mac.
#
#   bash Scripts/install-ipad.sh                          # the first iPad it finds
#   IPAD="Casanova's iPad" bash Scripts/install-ipad.sh   # a specific one: its name or ID
#
# The iPad must be unlocked, trusted, and have Developer Mode on
# (Settings › Privacy & Security › Developer Mode).

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.casanova.CasaPlay"
APP="build/Build/Products/Debug-iphoneos/CasaPlay.app"

list="$(mktemp)"
trap 'rm -f "$list"' EXIT

echo "• Looking for your iPad"
xcrun devicectl list devices --json-output "$list" >/dev/null

if ! pick="$(python3 - "$list" "${IPAD:-}" <<'PY'
import json, sys

path, query = sys.argv[1], sys.argv[2].strip().lower()
try:
    devices = json.load(open(path))["result"]["devices"]
except Exception as error:
    print("Couldn't read the device list:", error, file=sys.stderr)
    sys.exit(2)

rows = []
for d in devices:
    hardware = d.get("hardwareProperties", {})
    props = d.get("deviceProperties", {})
    link = d.get("connectionProperties", {})
    rows.append({
        "id": d.get("identifier", ""),
        "udid": hardware.get("udid", ""),
        "name": props.get("name", ""),
        "kind": hardware.get("deviceType") or hardware.get("marketingName") or "",
        "state": link.get("tunnelState", ""),
    })

def matches(row):
    if query:
        return query in (row["id"].lower(), row["udid"].lower()) or query in row["name"].lower()
    return "ipad" in (row["kind"] + " " + row["name"]).lower()

found = [r for r in rows if matches(r) and r["udid"]]
found.sort(key=lambda r: r["state"] != "connected")   # connected ones first
if not found:
    print("No iPad found. Devices I can see:", file=sys.stderr)
    for r in rows:
        print("  -", r["name"] or "(no name)", "|", r["kind"], "|", r["state"], file=sys.stderr)
    if not rows:
        print("  (none)", file=sys.stderr)
    sys.exit(1)
best = found[0]
print("\t".join([best["id"], best["udid"], best["name"], best["state"]]))
PY
)"; then
  echo
  echo "Plug the iPad in with a cable (or put it on the same Wi-Fi), unlock it, tap Trust,"
  echo "then run this again. If it has a special name, use:"
  echo "  IPAD=\"its name\" bash Scripts/install-ipad.sh"
  exit 1
fi

IFS=$'\t' read -r device_id udid name state <<<"$pick"
echo "✓ Using $name"
if [ "$state" != "connected" ]; then
  echo "  (It shows as \"${state:-not connected}\". Unlock it and keep it awake if anything below fails.)"
fi

if command -v xcodegen >/dev/null 2>&1; then
  echo "• Preparing the project"
  xcodegen generate >/dev/null
fi

echo "• Building CasaPlay for iPad (the first build takes a few minutes)"
xcodebuild -project CasaPlay.xcodeproj -scheme CasaPlay-iOS \
  -destination "platform=iOS,id=$udid" -derivedDataPath build \
  -allowProvisioningUpdates -quiet build

if [ ! -d "$APP" ]; then
  echo "The build finished but $APP isn't there." >&2
  exit 1
fi
echo "✓ Built"

echo "• Installing on $name"
xcrun devicectl device install app --device "$device_id" "$APP"

echo "• Opening CasaPlay"
if ! xcrun devicectl device process launch --device "$device_id" "$BUNDLE_ID"; then
  echo "Installed. Unlock the iPad and open CasaPlay from the Home Screen."
  echo "If it says \"Untrusted Developer\": Settings › General › VPN & Device Management › your name › Trust."
fi
