#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

if [[ "$ENVIRONMENT" == "staging" ]]; then
  KV="$STAGING_KV"
elif [[ "$ENVIRONMENT" == "production" ]]; then
  KV="$PROD_KV"
else
  echo "Usage:"
  echo "  ./ops/client-manager/license-usage-audit-v37q.sh staging"
  echo "  ./ops/client-manager/license-usage-audit-v37q.sh production"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
LICENSE_KEYS="$TMP_DIR/license-keys.json"
STATE_KEYS="$TMP_DIR/state-keys.json"
TOMBSTONE_KEYS="$TMP_DIR/tombstone-keys.json"
REPORT_JSON="$TMP_DIR/report.json"

echo "------ LICENSE USAGE AUDIT V37Q: $ENVIRONMENT ------"
echo ""

npx wrangler kv key list --namespace-id "$KV" --prefix "client-license:" --remote > "$LICENSE_KEYS"
npx wrangler kv key list --namespace-id "$KV" --prefix "client-state::" --remote > "$STATE_KEYS"
npx wrangler kv key list --namespace-id "$KV" --prefix "client-deleted:" --remote > "$TOMBSTONE_KEYS"

python3 - "$LICENSE_KEYS" "$STATE_KEYS" "$TOMBSTONE_KEYS" "$REPORT_JSON" <<'PY'
import json, sys, subprocess, tempfile, os

license_keys_file, state_keys_file, tombstone_keys_file, report_file = sys.argv[1:5]

def load_keys(path):
    try:
        data = json.load(open(path))
        return [x.get("name", "") for x in data if isinstance(x, dict) and x.get("name")]
    except Exception:
        return []

license_keys = load_keys(license_keys_file)
state_keys = load_keys(state_keys_file)
tombstone_keys = load_keys(tombstone_keys_file)

clients = set()

for k in license_keys:
    if k.startswith("client-license:"):
        clients.add(k.replace("client-license:", "", 1))

for k in state_keys:
    if k.startswith("client-state::") and k.endswith("::current"):
        clients.add(k.replace("client-state::", "", 1).replace("::current", "", 1))

tombstoned = {
    k.replace("client-deleted:", "", 1)
    for k in tombstone_keys
    if k.startswith("client-deleted:")
}

limits = {
    "trial": 16,
    "club": 40,
    "pro": 96,
    "enterprise": 250
}

report = {
    "clients": sorted(clients),
    "tombstoned": sorted(tombstoned),
    "licenseKeys": license_keys,
    "stateKeys": state_keys,
    "tombstoneKeys": tombstone_keys,
    "limits": limits
}

json.dump(report, open(report_file, "w"), indent=2)
PY

echo "Clients discovered:"
python3 - "$REPORT_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for c in data["clients"]:
    tomb = " TOMBSTONED" if c in data["tombstoned"] else ""
    print("-", c + tomb)
PY

echo ""
echo "------ DETAILED USAGE REPORT ------"

python3 - "$REPORT_JSON" "$KV" <<'PY'
import json, sys, subprocess, tempfile, os

report_file, kv = sys.argv[1], sys.argv[2]
data = json.load(open(report_file))

limits = data["limits"]
clients = data["clients"]
tombstoned = set(data["tombstoned"])

def kv_get(key):
    try:
        out = subprocess.check_output(
            ["npx", "wrangler", "kv", "key", "get", key, "--namespace-id", kv, "--remote"],
            text=True,
            stderr=subprocess.DEVNULL
        )
        if not out.strip():
            return None
        return json.loads(out)
    except Exception:
        return None

rows = []

for client in clients:
    lic = kv_get("client-license:" + client) or {}
    rec = kv_get("client-state::" + client + "::current") or {}

    state = rec.get("state", rec) if isinstance(rec, dict) else {}
    players = state.get("players", []) if isinstance(state, dict) else []
    if not isinstance(players, list):
        players = []

    active_players = [
        p for p in players
        if isinstance(p, dict)
        and p.get("active", True) is not False
        and p.get("waitlist", False) is not True
    ]

    level = str(
        lic.get("licenseLevel")
        or lic.get("level")
        or lic.get("plan")
        or "club"
    ).lower()

    status = str(
        lic.get("licenseStatus")
        or lic.get("status")
        or "active"
    ).lower()

    explicit_limit = lic.get("playerLimit") or lic.get("maxPlayers") or lic.get("playersLimit")
    try:
        player_limit = int(explicit_limit) if explicit_limit else limits.get(level, 40)
    except Exception:
        player_limit = limits.get(level, 40)

    active_count = len(active_players)
    total_count = len(players)

    if client in tombstoned:
        health = "TOMBSTONED"
    elif not lic:
        health = "NO_LICENSE"
    elif not rec:
        health = "NO_STATE_YET"
    elif active_count > player_limit:
        health = "OVER_LIMIT"
    else:
        health = "OK"

    rows.append({
        "client": client,
        "level": level,
        "status": status,
        "limit": player_limit,
        "active": active_count,
        "total": total_count,
        "health": health
    })

print(f"{'CLIENT':38} {'LEVEL':12} {'STATUS':10} {'ACTIVE':>7} {'LIMIT':>7} {'TOTAL':>7} HEALTH")
print("-" * 100)

for r in rows:
    print(f"{r['client'][:38]:38} {r['level'][:12]:12} {r['status'][:10]:10} {r['active']:7} {r['limit']:7} {r['total']:7} {r['health']}")

print("")
print("SUMMARY")
print("-------")
for health in ["OK", "OVER_LIMIT", "NO_LICENSE", "NO_STATE_YET", "TOMBSTONED"]:
    count = sum(1 for r in rows if r["health"] == health)
    print(f"{health}: {count}")

bad = [r for r in rows if r["health"] in ("OVER_LIMIT", "NO_LICENSE")]
if bad:
    print("")
    print("ACTION NEEDED")
    print("-------------")
    for r in bad:
        print(f"- {r['client']}: {r['health']} active={r['active']} limit={r['limit']} level={r['level']}")
else:
    print("")
    print("GREEN: no over-limit or missing-license active clients found.")
PY

echo ""
echo "Audit temp files:"
echo "$TMP_DIR"
