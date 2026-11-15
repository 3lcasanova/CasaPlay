#!/usr/bin/env bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# Opens CasaPlay on a connected device and prints everything the app says, live. If the app ever crashes,
# the last lines show where. Press Ctrl+C to stop.
#
#   bash Scripts/launch-with-log.sh              # the first iPhone or iPad it finds
#   bash Scripts/launch-with-log.sh Goddess      # a specific device: its name or ID (an Apple TV too)

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.casanova.CasaPlay"
list="$(mktemp)"
trap 'rm -f "$list"' EXIT

xcrun devicectl list devices --json-output "$list" >/dev/null

if ! device_id="$(python3 - "$list" "${1:-}" <<'PY'
import json, sys

path, query = sys.argv[1], sys.argv[2].strip().lower()
devices = json.load(open(path))["result"]["devices"]
rows = []
for d in devices:
    hw, props, link = d.get("hardwareProperties", {}), d.get("deviceProperties", {}), d.get("connectionProperties", {})
    rows.append({
        "id": d.get("identifier", ""), "udid": hw.get("udid", ""), "name": props.get("name", ""),
        "kind": (hw.get("deviceType") or hw.get("marketingName") or ""), "state": link.get("tunnelState", ""),
    })

def matches(r):
    if query:
        return query in (r["id"].lower(), r["udid"].lower()) or query in r["name"].lower()
    return any(k in (r["kind"] + " " + r["name"]).lower() for k in ("iphone", "ipad"))

found = sorted([r for r in rows if matches(r)], key=lambda r: r["state"] != "connected")
if not found:
    print("No device found. Devices I can see:", file=sys.stderr)
    for r in rows:
        print("  -", r["name"] or "(no name)", "|", r["kind"], "|", r["state"], file=sys.stderr)
    sys.exit(1)
print(found[0]["id"])
PY
)"; then
  echo "Plug the device in, unlock it, then run this again (or add its name: bash Scripts/launch-with-log.sh \"its name\")."
  exit 1
fi

echo "• Opening CasaPlay. Now do what crashes it. Everything it prints shows below; Ctrl+C stops."
xcrun devicectl device process launch --console --terminate-existing --device "$device_id" "$BUNDLE_ID"
