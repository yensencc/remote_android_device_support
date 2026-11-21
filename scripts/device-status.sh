#!/usr/bin/env bash
# Onboarding / health check for enrolled devices (read-only).
#   ./scripts/device-status.sh              # all devices, one line each
#   ./scripts/device-status.sh "onn tablet" # one device, full checklist
# Reads the MDM database; changes nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

sql() { docker compose exec -T postgresql psql -U hmdm -d hmdm -At -c "$1"; }

# Expected apps per configuration: action 1 = install.
DATA="$(sql "select json_build_object(
  'now', (extract(epoch from now())*1000)::bigint,
  'devices', (select coalesce(json_agg(json_build_object(
      'number', d.number, 'description', d.description, 'lastupdate', d.lastupdate,
      'enrolltime', d.enrolltime, 'publicip', d.publicip, 'custom1', d.custom1,
      'config', c.name, 'configid', c.id, 'kiosk', c.kioskmode, 'push', c.pushoptions,
      'info', d.info) order by d.number), '[]'::json)
    from devices d left join configurations c on c.id = d.configurationid),
  'expected', (select coalesce(json_agg(json_build_object(
      'configid', ca.configurationid, 'pkg', a.pkg, 'name', a.name,
      'version', av.version, 'action', ca.action)), '[]'::json)
    from configurationapplications ca
    join applications a on a.id = ca.applicationid
    join applicationversions av on av.id = coalesce(ca.applicationversionid, a.latestversion)
    where ca.action = 1 and a.type = 'app' and a.system = false),
  'settings', (select coalesce(json_agg(json_build_object(
      'configid', s.extrefid, 'pkg', a.pkg, 'name', s.name)), '[]'::json)
    from configurationapplicationsettings s join applications a on a.id = s.applicationid),
  'devsettings', (select coalesce(json_agg(json_build_object(
      'device', (select number from devices where id = s.extrefid), 'pkg', a.pkg, 'name', s.name)), '[]'::json)
    from deviceapplicationsettings s join applications a on a.id = s.applicationid)
)::text")"

python3 - "${1:-}" "$DATA" <<'EOF'
import json, sys
want, data = sys.argv[1], json.loads(sys.argv[2])
now = data["now"]
AGENT = "com.lasttechsol.remotesupport"

def age(ms):
    if not ms: return "never"
    m = int((now - ms) / 60000)
    return f"{m} min ago" if m < 120 else f"{m // 60} h ago" if m < 2880 else f"{m // 1440} days ago"

def info(d):
    try: return json.loads(d["info"]) if d["info"] else {}
    except Exception: return {}

def checks(d):
    i = info(d)
    installed = {a.get("pkg"): a.get("version") for a in i.get("applications", [])}
    perms = i.get("permissions") or []
    exp = [e for e in data["expected"] if e["configid"] == d["configid"]]
    # Application settings: from the configuration, or set on this device
    sets = {(s["pkg"], s["name"]) for s in data["settings"] if s["configid"] == d["configid"]}
    sets |= {(s["pkg"], s["name"]) for s in data["devsettings"] if s["device"] == d["number"]}
    online = d["lastupdate"] and now - d["lastupdate"] < 30 * 60000
    rows = [
        ("Syncing with the MDM (last 30 min)", bool(online), f"last sync {age(d['lastupdate'])}"),
        ("Fully managed (device owner)", i.get("mdmMode") is True,
         "QR enrollment after factory reset" if i.get("mdmMode") is not True else "installs are silent"),
        ("MDM agent allowed to draw overlays", len(perms) > 1 and perms[1] == 1, "needed for kiosk / prompts"),
    ]
    for e in exp:
        have = installed.get(e["pkg"])
        rows.append((f"App {e['name']} {e['version']}", have == e["version"],
                     f"installed {have}" if have else "not installed yet"))
    if any(e["pkg"] == AGENT for e in exp):
        for key in ("server_url", "secret"):
            rows.append((f"Remote Support setting '{key}' in the MDM", (AGENT, key) in sets,
                         "set" if (AGENT, key) in sets else "Configuration → Application settings"))
        rows.append(("Remote Support reported a session", bool(d["custom1"]),
                     d["custom1"] or "open the app once (agree + Accessibility), or send a runApp push"))
    else:
        rows.append(("Remote Support in configuration", False, f"add {AGENT} with action Install"))
    return i, rows

devs = [d for d in data["devices"] if not want or d["number"] == want]
if want and not devs:
    sys.exit(f"No device '{want}'. Devices: " + ", ".join(d["number"] for d in data["devices"]))
for d in devs:
    i, rows = checks(d)
    ok = sum(1 for _, good, _ in rows if good)
    if not want:
        print(f"{d['number']:<24} {d['config'] or '-':<24} {ok}/{len(rows)} checks  last sync {age(d['lastupdate'])}")
        continue
    print(f"Device:        {d['number']}  ({d['description'] or 'no description'})")
    print(f"Configuration: {d['config']}   push: {d['push']}   kiosk: {'on' if d['kiosk'] else 'off'}")
    print(f"Hardware:      model {i.get('model','?')}, Android {i.get('androidVersion','?')}, battery {i.get('batteryLevel','?')}%, {i.get('cpu','?')}")
    print(f"Enrolled:      {age(d['enrolltime'])}")
    print()
    for name, good, note in rows:
        print(f"  [{'x' if good else ' '}] {name:<50} {note}")
    print(f"\n  {ok}/{len(rows)} checks passed")
EOF
