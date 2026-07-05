#!/usr/bin/env bash
set -euo pipefail

PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

echo "------ SAFE LICENSE UPDATE - PRODUCTION ------"
echo ""
echo "WARNING: This updates a LIVE production client license."
echo ""

read -r -p "Client ID to update in PRODUCTION: " CLIENT
CLIENT="$(echo "$CLIENT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/-+/-/g; s/^-|-$//g')"

if [ -z "$CLIENT" ]; then
  echo "ERROR: No valid client ID."
  exit 1
fi

echo ""
echo "Choose license level:"
echo "1) trial      16 players, no mobile scoring"
echo "2) club       40 players"
echo "3) pro        96 players"
echo "4) enterprise 250 players"
echo ""
read -r -p "Selection: " CHOICE

case "$CHOICE" in
  1) LEVEL="trial" ;;
  2) LEVEL="club" ;;
  3) LEVEL="pro" ;;
  4) LEVEL="enterprise" ;;
  trial|club|pro|enterprise) LEVEL="$CHOICE" ;;
  *)
    echo "Cancelled. Invalid selection."
    exit 0
    ;;
esac

echo ""
echo "This will update this PRODUCTION client:"
echo "Client: $CLIENT"
echo "Level:  $LEVEL"
echo ""
echo "Type exactly:"
echo "UPDATE PRODUCTION $CLIENT $LEVEL"
read -r -p "Confirm: " CONFIRM

if [ "$CONFIRM" != "UPDATE PRODUCTION $CLIENT $LEVEL" ]; then
  echo "Cancelled. Nothing changed."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
BEFORE="$TMP_DIR/before-license.json"
AFTER="$TMP_DIR/after-license.json"

echo ""
echo "------ SAFETY CHECKS ------"

if npx wrangler kv key get "client-deleted:$CLIENT" --namespace-id "$PROD_KV" --remote >/tmp/pb-prod-license-update-tombstone.json 2>/dev/null; then
  echo "ERROR: Client is tombstoned. Refusing to update:"
  echo "client-deleted:$CLIENT"
  exit 1
else
  echo "PASS: no tombstone found."
fi

if ! npx wrangler kv key get "client-license:$CLIENT" --namespace-id "$PROD_KV" --remote > "$BEFORE" 2>/dev/null; then
  echo "ERROR: Client license does not exist:"
  echo "client-license:$CLIENT"
  echo ""
  echo "Create the client first."
  exit 1
fi

echo "PASS: existing production license found."

python3 - "$BEFORE" "$AFTER" "$CLIENT" "$LEVEL" <<'PY'
import json, sys, datetime

before_path, after_path, client_id, level = sys.argv[1:5]

with open(before_path) as f:
    data = json.load(f)

levels = {
    "trial": {
        "licenseLabel": "Trial",
        "licenseStatus": "trial",
        "playerLimit": 16,
        "mobileScoring": False,
        "officialResults": False,
        "support": "Community support",
    },
    "club": {
        "licenseLabel": "Club",
        "licenseStatus": "active",
        "playerLimit": 40,
        "mobileScoring": True,
        "officialResults": True,
        "support": "Standard support",
    },
    "pro": {
        "licenseLabel": "Pro",
        "licenseStatus": "active",
        "playerLimit": 96,
        "mobileScoring": True,
        "officialResults": True,
        "support": "Priority support",
    },
    "enterprise": {
        "licenseLabel": "Enterprise",
        "licenseStatus": "active",
        "playerLimit": 250,
        "mobileScoring": True,
        "officialResults": True,
        "support": "Dedicated support",
    },
}

patch = levels[level]

data["ok"] = True
data["marker"] = "PB_SAFE_LICENSE_UPDATE_V37M"
data["clientId"] = data.get("clientId") or client_id
data["clientName"] = data.get("clientName") or data.get("name") or client_id
data["licenseLevel"] = level
data.update(patch)
data["environment"] = "production"
data["source"] = "ops-update-production-license-v37m"
data["updatedAt"] = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

with open(after_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print("Preview:")
print(json.dumps({
    "clientId": data["clientId"],
    "clientName": data["clientName"],
    "licenseLevel": data["licenseLevel"],
    "licenseLabel": data["licenseLabel"],
    "licenseStatus": data["licenseStatus"],
    "playerLimit": data["playerLimit"],
    "mobileScoring": data["mobileScoring"],
    "officialResults": data["officialResults"],
    "support": data["support"],
    "marker": data["marker"],
}, indent=2))
PY

echo ""
echo "------ WRITE UPDATED PRODUCTION LICENSE ------"

npx wrangler kv key put "client-license:$CLIENT" --path "$AFTER" --namespace-id "$PROD_KV" --remote

echo ""
echo "------ VERIFY UPDATED PRODUCTION LICENSE ------"

npx wrangler kv key get "client-license:$CLIENT" --namespace-id "$PROD_KV" --remote >/tmp/pb-prod-updated-license-check.json

echo "GREEN: Production license updated."
echo ""
echo "Backup folder:"
echo "$TMP_DIR"
