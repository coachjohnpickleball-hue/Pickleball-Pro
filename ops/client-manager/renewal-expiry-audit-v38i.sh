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
  echo "  ./ops/client-manager/renewal-expiry-audit-v38i.sh staging"
  echo "  ./ops/client-manager/renewal-expiry-audit-v38i.sh production"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
KEYS="$TMP_DIR/keys.json"

echo "=============================================="
echo " PickleBall Pro Renewal / Expiry Audit V38I"
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
from datetime import datetime, timezone, date

keys_file, tmp_dir, kv = sys.argv[1:4]
tmp = Path(tmp_dir)

try:
    keys = json.load(open(keys_file))
except Exception:
    keys = []

clients = sorted({
    item.get("name", "").replace("client-license:", "", 1)
    for item in keys
    if item.get("name", "").startswith("client-license:")
})

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
        return {}

def parse_date(value):
    if not value:
        return None
    value = str(value).strip()
    try:
        if "T" in value:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
        return date.fromisoformat(value[:10])
    except Exception:
        return None

today = datetime.now(timezone.utc).date()
rows = []

for client in clients:
    license_file = tmp / f"license_{client}.json"
    tombstone_file = tmp / f"tombstone_{client}.json"

    wrangler_get(f"client-license:{client}", str(license_file))
    data = load_json(license_file)

    tombstoned = wrangler_get(f"client-deleted:{client}", str(tombstone_file))

    level = str(data.get("licenseLevel") or data.get("level") or data.get("plan") or "club").lower()
    status = str(data.get("licenseStatus") or data.get("status") or "active").lower()

    renewal_raw = (
        data.get("renewalDate")
        or data.get("expiresAt")
        or data.get("subscriptionEndsAt")
        or data.get("trialEndsAt")
        or ""
    )

    renewal_date = parse_date(renewal_raw)
    days_left = None

    if renewal_date:
        days_left = (renewal_date - today).days

    if tombstoned:
        health = "TOMBSTONED"
    elif status == "suspended":
        health = "SUSPENDED"
    elif renewal_date is None:
        health = "NO_RENEWAL_DATE"
    elif days_left < 0:
        health = "EXPIRED"
    elif days_left <= 14:
        health = "EXPIRING_SOON"
    elif level == "trial":
        health = "TRIAL"
    else:
        health = "OK"

    rows.append({
        "clientId": client,
        "clientName": data.get("clientName") or data.get("name") or "",
        "status": status,
        "level": level,
        "renewal": str(renewal_raw or "-"),
        "daysLeft": "" if days_left is None else str(days_left),
        "health": health,
    })

print("")
print(f"{'CLIENT':34} | {'STATUS':10} | {'LEVEL':10} | {'RENEWAL/EXPIRY':18} | {'DAYS':6} | HEALTH")
print("-" * 110)

for r in rows:
    print(f"{r['clientId'][:34]:34} | {r['status'][:10]:10} | {r['level'][:10]:10} | {r['renewal'][:18]:18} | {r['daysLeft'][:6]:6} | {r['health']}")

counts = {}
for r in rows:
    counts[r["health"]] = counts.get(r["health"], 0) + 1

print("")
print("SUMMARY")
print("-------")
print("Total clients:", len(rows))
for key in ["OK", "TRIAL", "EXPIRING_SOON", "EXPIRED", "SUSPENDED", "NO_RENEWAL_DATE", "TOMBSTONED"]:
    print(f"{key}: {counts.get(key, 0)}")

print("")
if counts.get("EXPIRED", 0) or counts.get("EXPIRING_SOON", 0):
    print("ATTENTION: renewal follow-up needed.")
else:
    print("GREEN: no expired or expiring clients found.")
PY

echo ""
echo "GREEN: $ENVIRONMENT renewal / expiry audit complete."
