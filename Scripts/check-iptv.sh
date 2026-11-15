#!/bin/bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# Checks the add-on links saved by Scripts/setup-addon.sh the way CasaPlay's IPTV tab reads them. For each
# add-on it lists the catalogs, asks every channel list for its first page, and asks for the stream of the
# first channel. If the link carries an IPTV login (Xtream), it also tests that login with the IPTV server.
# Nothing secret is printed: no links, keys, logins or stream addresses.
#
#   bash Scripts/check-iptv.sh

cd "$(dirname "$0")/.." || exit 1
FILE="Config/Secrets.xcconfig"

value="$(sed -n 's/^PERSONAL_ADDON_URL[[:space:]]*=[[:space:]]*//p' "$FILE" 2>/dev/null | tail -n 1 | tr -d '\r')"
if [ -z "$value" ]; then
  echo "✗ No add-on links are saved yet. Run Scripts/setup-addon.sh first."
  exit 1
fi

python3 - "$value" <<'PY'
import json, re, subprocess, sys, time, datetime
from urllib.parse import quote, unquote, urlparse

LIVE_TYPES = {"tv", "channel", "channels", "live", "iptv", "livetv", "live_tv", "live-tv"}
VIDEO_TYPES = {"movie", "series", "anime"}
LIVE_WORDS = {"tv", "live", "iptv", "channel", "channels", "livetv"}


def get(url, timeout=45):
    """(status, body bytes, seconds). Uses curl, which trusts the Mac's own certificates."""
    started = time.time()
    p = subprocess.run(
        ["curl", "-sS", "-L", "-m", str(timeout), "-A", "CasaPlay/1.0", "-H", "Accept: application/json",
         "-w", "\n%{http_code}", url],
        capture_output=True)
    body, _, last = p.stdout.rpartition(b"\n")
    try:
        status = int(last)
    except ValueError:
        status = 0
    return status, body, time.time() - started


def as_json(body):
    try:
        return json.loads(body.decode("utf-8", "replace"))
    except Exception:
        return None


def is_live(catalog):
    kind = (catalog.get("type") or "").lower()
    if kind in LIVE_TYPES:
        return True
    if kind in VIDEO_TYPES:
        return False
    text = " ".join([kind, catalog.get("id") or "", catalog.get("name") or ""]).lower()
    return any(word in LIVE_WORDS for word in re.split(r"[^a-z]+", text))


def check_login(link):
    """Tests the Xtream IPTV login carried in the link, without printing it."""
    settings = {}
    for part in link.split("|"):
        if "=" in part:
            key, _, val = part.partition("=")
            settings[key.strip().lower()] = unquote(unquote(val))
    server, user, password = settings.get("xtreamserver"), settings.get("xtreamuser"), settings.get("xtreampass")
    if not (server and user and password):
        print("  IPTV login: this link has none.")
        return
    host = urlparse(server).netloc or server
    api = server.rstrip("/") + "/player_api.php?username=" + quote(user) + "&password=" + quote(password)
    status, body, took = get(api, 30)
    info = as_json(body)
    if status != 200 or not isinstance(info, dict):
        print(f"  ✗ IPTV login: {host} answered HTTP {status or 'nothing'} ({took:.0f}s), so the login can't be checked.")
        return
    user_info = info.get("user_info") or {}
    ok = str(user_info.get("auth")) == "1"
    state = user_info.get("status", "?")
    exp = user_info.get("exp_date")
    when = ""
    try:
        when = ", expires " + datetime.datetime.fromtimestamp(int(exp)).strftime("%Y-%m-%d")
    except Exception:
        pass
    mark = "✓" if ok and str(state).lower() == "active" else "✗"
    print(f"  {mark} IPTV login at {host}: {'accepted' if ok else 'REFUSED'}, status {state}{when}, "
          f"{user_info.get('max_connections', '?')} connection(s) allowed, {user_info.get('active_cons', '?')} in use.")
    if ok:
        status, body, took = get(api + "&action=get_live_streams", 60)
        streams = as_json(body)
        count = len(streams) if isinstance(streams, list) else None
        if count is None:
            print(f"  ✗ The server gave no channel list (HTTP {status}).")
        else:
            print(f"  {'✓' if count else '✗'} The IPTV server lists {count} live channel(s).")


def check_addon(raw):
    link = raw if "://" in raw else "https://" + raw
    if not link.endswith("/manifest.json"):
        print("• A saved link doesn't end in /manifest.json, skipped.")
        return
    base = link[: -len("/manifest.json")]
    status, body, took = get(link, 40)
    manifest = as_json(body)
    if status != 200 or not isinstance(manifest, dict):
        print(f"✗ A saved link: the manifest answered HTTP {status or 'nothing'} ({took:.0f}s).")
        return
    print(f"== {manifest.get('name', 'Add-on')} {manifest.get('version', '')}  (manifest in {took:.1f}s)")
    catalogs = manifest.get("catalogs") or []
    print(f"  {len(catalogs)} catalog(s):")
    for catalog in catalogs:
        tag = "live" if is_live(catalog) else "    "
        extras = {e.get("name"): e for e in (catalog.get("extra") or [])}
        notes = []
        genre = extras.get("genre")
        if genre and genre.get("isRequired"):
            notes.append("needs a genre")
        elif genre:
            notes.append(f"{len(genre.get('options') or [])} genres")
        print(f"    [{tag}] {catalog.get('type')} · {catalog.get('name') or catalog.get('id')}"
              + (f"  ({', '.join(notes)})" if notes else ""))

    live = [c for c in catalogs if is_live(c)]
    if not live:
        print("  ✗ None of its catalogs is a channel list, so CasaPlay's IPTV tab only lists it under \"Show every catalog\".")
    for catalog in live[:6]:
        kind, cid = catalog.get("type"), catalog.get("id")
        path = f"{base}/catalog/{quote(str(kind))}/{quote(str(cid))}"
        genre = {e.get("name"): e for e in (catalog.get("extra") or [])}.get("genre")
        if genre and genre.get("isRequired") and genre.get("options"):
            path += "/genre=" + quote(str(genre["options"][0]))
        status, body, took = get(path + ".json", 60)
        page = as_json(body)
        metas = page.get("metas") if isinstance(page, dict) else None
        label = catalog.get("name") or cid
        if status != 200 or metas is None:
            print(f"  ✗ {label}: HTTP {status or 'nothing'} ({took:.0f}s).")
            continue
        print(f"  {'✓' if metas else '✗'} {label}: {len(metas)} entr{'y' if len(metas) == 1 else 'ies'} in {took:.1f}s"
              + ("  <- EMPTY: this is what CasaPlay shows as \"No channels found\"" if not metas else ""))
        if metas:
            print("      e.g. " + ", ".join(str(m.get("name", "?")) for m in metas[:3]))
            first = metas[0]
            skind = first.get("type") or kind
            status, body, took = get(f"{base}/stream/{quote(str(skind))}/{quote(str(first.get('id', '')))}.json", 45)
            streams = (as_json(body) or {}).get("streams") if status == 200 else None
            if streams is None:
                print(f"      ✗ Asking for the first channel's stream: HTTP {status or 'nothing'}.")
            else:
                kinds = []
                for s in streams[:3]:
                    u = s.get("url") or ""
                    if u:
                        kinds.append(urlparse(u).scheme + (" .m3u8" if ".m3u8" in u else ""))
                    elif s.get("externalUrl"):
                        kinds.append("web page")
                    elif s.get("ytId"):
                        kinds.append("YouTube")
                    elif s.get("infoHash"):
                        kinds.append("torrent")
                    else:
                        kinds.append("other")
                print(f"      {'✓' if streams else '✗'} First channel gives {len(streams)} stream(s)"
                      + (f": {', '.join(kinds)}" if kinds else ""))
    check_login(raw)


links = sys.argv[1].split()
print(f"Checking {len(links)} saved add-on link(s). Nothing secret is printed.\n")
for raw in links:
    check_addon(raw)
    print()
print("Reading it:")
print(" • A live list with 0 entries here is empty on the add-on's side (login, key or settings), not in CasaPlay.")
print(" • Entries here but none in CasaPlay: send me this output and a photo of the IPTV tab.")
PY
