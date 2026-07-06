#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

if [[ "$ENVIRONMENT" == "staging" ]]; then
  KV="$STAGING_KV"
  BASE_URL="https://rally-staging.coachjohnpickleball.workers.dev"
elif [[ "$ENVIRONMENT" == "production" ]]; then
  KV="$PROD_KV"
  BASE_URL="https://rally.coachjohnpickleball.workers.dev"
else
  echo "Usage:"
  echo "  ./ops/client-manager/billing-summary-export-v38l.sh staging"
  echo "  ./ops/client-manager/billing-summary-export-v38l.sh production"
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="ops/client-manager/reports"
OUT_CSV="$REPORT_DIR/${ENVIRONMENT}-billing-summary-${STAMP}.csv"
OUT_JSON="$REPORT_DIR/${ENVIRONMENT}-billing-summary-${STAMP}.json"

mkdir -p "$REPORT_DIR"

TMP_DIR="$(mktemp -d)"
KEYS="$TMP_DIR/keys.json"

echo "=============================================="
echo " PickleBall Pro Billing Summary Export V38L"
echo "=============================================="
echo ""
echo "Environment: $ENVIRONMENT"
echo "Read-only. No KV changes are made."
echo ""

echo "Loading client license keys..."
npx wrangler kv key list --prefix "client-license:" --namespace-id "$KV" --remote > "$KEYS"

python3 - "$KEYS" "$TMP_DIR" "$KV" "$BASE_URL" "$OUT_CSV" "$OUT_JSON" <<'PY'
import csv, json, subprocess, sys
from pathlib import Path
from datetime import datetime, timezone, date

keys_file, tmp_dir, kv, base_url, out_csv, out_json = sys.argv[1:7]
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

def default_limit(level, data):
    explicit = data.get("playerLimit") or data.get("maxPlayers") or data.get("playersLimit")
    try:
        if explicit is not None:
            return int(explicit)
    except Exception:
        pass

    return {
        "trial": 16,
        "club": 40,
        "pro": 96,
        "enterprise": 250,
    }.get(level, 40)

today = datetime.now(timezone.utc).date()
rows = []

for client in clients:
    license_file = tmp / f"license_{client}.json"
    state_file = tmp / f"state_{client}.json"
    tombstone_file = tmp / f"tombstone_{client}.json"

    wrangler_get(f"client-license:{client}", str(license_file))
    data = load_json(license_file)

    state_exists = wrangler_get(f"client-state::{client}::current", str(state_file))
    state_data = load_json(state_file) if state_exists else {}

    tombstoned = wrangler_get(f"client-deleted:{client}", str(tombstone_file))

    level = str(data.get("licenseLevel") or data.get("level") or data.get("plan") or "club").lower()
    status = str(data.get("licenseStatus") or data.get("status") or "active").lower()
    limit = default_limit(level, data)
    active, total = count_players(state_data)

    renewal_raw = (
        data.get("renewalDate")
        or data.get("expiresAt")
        or data.get("subscriptionEndsAt")
        or data.get("trialEndsAt")
        or ""
    )

    renewal_date = parse_date(renewal_raw)
    days_left = ""
    if renewal_date:
        days_left = (renewal_date - today).days

    if tombstoned:
        health = "TOMBSTONED"
    elif status == "suspended":
        health = "SUSPENDED"
    elif status not in ("active", "trial"):
        health = "INACTIVE"
    elif active > limit:
        health = "OVER_LIMIT"
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
        "billingName": data.get("billingName") or "",
        "billingEmail": data.get("billingEmail") or "",
        "billingPhone": data.get("billingPhone") or "",
        "billingNotes": data.get("billingNotes") or "",
        "status": status,
        "level": level,
        "activePlayers": active,
        "totalPlayers": total,
        "playerLimit": limit,
        "renewalDate": str(renewal_raw or ""),
        "daysLeft": days_left,
        "billingHealth": health,
        "privateLink": f"{base_url}/?clientId={client}",
    })

fieldnames = [
    "clientId",
    "clientName",
    "billingName",
    "billingEmail",
    "billingPhone",
    "billingNotes",
    "status",
    "level",
    "activePlayers",
    "totalPlayers",
    "playerLimit",
    "renewalDate",
    "daysLeft",
    "billingHealth",
    "privateLink",
]

with open(out_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

with open(out_json, "w") as f:
    json.dump(rows, f, indent=2)

print("")
print(f"{'CLIENT':34} | {'STATUS':10} | {'LEVEL':10} | {'PLAYERS':9} | {'RENEWAL':12} | HEALTH")
print("-" * 100)

for r in rows:
    players = f"{r['activePlayers']}/{r['playerLimit']}"
    renewal = r["renewalDate"] or "-"
    print(f"{r['clientId'][:34]:34} | {r['status'][:10]:10} | {r['level'][:10]:10} | {players:9} | {renewal[:12]:12} | {r['billingHealth']}")

counts = {}
for r in rows:
    counts[r["billingHealth"]] = counts.get(r["billingHealth"], 0) + 1

print("")
print("SUMMARY")
print("-------")
print("Total clients:", len(rows))
for key in ["OK", "TRIAL", "EXPIRING_SOON", "EXPIRED", "SUSPENDED", "INACTIVE", "OVER_LIMIT", "NO_RENEWAL_DATE", "TOMBSTONED"]:
    print(f"{key}: {counts.get(key, 0)}")

print("")
print("CSV report:", out_csv)
print("JSON report:", out_json)

print("")
if counts.get("EXPIRED", 0) or counts.get("EXPIRING_SOON", 0) or counts.get("SUSPENDED", 0) or counts.get("OVER_LIMIT", 0):
    print("ATTENTION: billing follow-up may be needed.")
else:
    print("GREEN: billing summary export complete.")
PY

echo ""
echo "GREEN: $ENVIRONMENT billing summary export complete."
