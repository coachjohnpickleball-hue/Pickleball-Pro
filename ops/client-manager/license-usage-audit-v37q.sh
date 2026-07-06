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
KEYS="$TMP_DIR/keys.json"
REPORT="$TMP_DIR/report.json"

echo "=============================================="
echo " PickleBall Pro License Usage Audit V38H"
echo "=============================================="
echo ""
echo "Environment: $ENVIRONMENT"
echo "Read-only. No KV changes are made."
echo ""

echo "Loading client license keys..."
npx wrangler kv key list --prefix "client-license:" --namespace-id "$KV" --remote > "$KEYS"

python3 - "$KEYS" "$TMP_DIR" "$KV" <<'PY'
import json, subprocess, sys
from pathlib import Path

keys_file, tmp_dir, kv = sys.argv[1:4]
tmp = Path(tmp_dir)

try:
    keys = json.load(open(keys_file))
except Exception:
    keys = []

clients = []
for item in keys:
    name = item.get("name", "")
    if name.startswith("client-license:"):
        clients.append(name.replace("client-license:", "", 1))

clients = sorted(set(clients))

def wrangler_get(key, out_file):
    result = subprocess.run(
        ["npx", "wrangler", "kv", "key", "get", key, "--namespace-id", kv, "--remote"],
        stdout=open(out_file, "w"),
        stderr=subprocess.DEVNULL,
        text=True
    )
    return result.returncode == 0

def load_json(path):
    try:
        return json.load(open(path))
    except Exception:
        return None

def clean_level(license_data):
    level = (
        license_data.get("licenseLevel")
        or license_data.get("level")
        or license_data.get("plan")
        or "club"
    )
    return str(level).lower()

def clean_status(license_data):
    status = (
        license_data.get("licenseStatus")
        or license_data.get("status")
        or "active"
    )
    return str(status).lower()

def limit_for(level, license_data):
    explicit = (
        license_data.get("playerLimit")
        or license_data.get("maxPlayers")
        or license_data.get("playersLimit")
    )
    try:
        if explicit is not None:
            return int(explicit)
    except Exception:
        pass

    defaults = {
        "trial": 16,
        "club": 40,
        "pro": 96,
        "enterprise": 250,
    }
    return defaults.get(level, 40)

def count_players(state_data):
    if not isinstance(state_data, dict):
        return 0, 0

    state = state_data.get("state", state_data)
    players = state.get("players", []) if isinstance(state, dict) else []

    total = len(players) if isinstance(players, list) else 0
    active = 0

    if isinstance(players, list):
        for p in players:
            if not isinstance(p, dict):
                continue
            if p.get("active") is False:
                continue
            if p.get("waitlist") is True:
                continue
            active += 1

    return active, total

rows = []

for client in clients:
    license_file = tmp / f"license_{client}.json"
    state_file = tmp / f"state_{client}.json"
    tombstone_file = tmp / f"tombstone_{client}.json"

    wrangler_get(f"client-license:{client}", str(license_file))
    license_data = load_json(license_file) or {}

    state_exists = wrangler_get(f"client-state::{client}::current", str(state_file))
    state_data = load_json(state_file) if state_exists else None

    tombstoned = wrangler_get(f"client-deleted:{client}", str(tombstone_file))

    level = clean_level(license_data)
    status = clean_status(license_data)
    limit = limit_for(level, license_data)
    active, total = count_players(state_data)

    if tombstoned:
        health = "TOMBSTONED"
    elif status == "suspended":
        health = "SUSPENDED"
    elif status not in ("active", "trial"):
        health = "INACTIVE"
    elif active > limit:
        health = "OVER_LIMIT"
    elif not state_exists:
        health = "NO_STATE_YET"
    elif level == "trial":
        health = "TRIAL"
    else:
        health = "OK"

    rows.append({
        "clientId": client,
        "clientName": license_data.get("clientName") or license_data.get("name") or "",
        "status": status,
        "level": level,
        "active": active,
        "total": total,
        "limit": limit,
        "health": health,
    })

print("")
print(f"{'CLIENT':34} | {'STATUS':10} | {'LEVEL':10} | {'ACTIVE/LIMIT':12} | HEALTH")
print("-" * 92)

for r in rows:
    client = r["clientId"][:34]
    status = r["status"][:10]
    level = r["level"][:10]
    usage = f'{r["active"]}/{r["limit"]}'
    print(f"{client:34} | {status:10} | {level:10} | {usage:12} | {r['health']}")

counts = {}
for r in rows:
    counts[r["health"]] = counts.get(r["health"], 0) + 1

print("")
print("SUMMARY")
print("-------")
print("Total clients:", len(rows))
for key in ["OK", "TRIAL", "SUSPENDED", "INACTIVE", "OVER_LIMIT", "NO_STATE_YET", "TOMBSTONED"]:
    print(f"{key}: {counts.get(key, 0)}")

bad = counts.get("OVER_LIMIT", 0) + counts.get("INACTIVE", 0)
print("")
if bad:
    print("ATTENTION: audit found clients needing review.")
else:
    print("GREEN: no over-limit or invalid-status clients found.")
PY

echo ""
echo "GREEN: $ENVIRONMENT license usage audit complete."
