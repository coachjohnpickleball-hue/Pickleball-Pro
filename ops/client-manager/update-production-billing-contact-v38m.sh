#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="production"
KV="faac1bcc30ef4711a9377e60ef70636d"
CONFIRM_PREFIX="BILLING PRODUCTION"

CLIENT_ID="${1:-}"

if [[ -z "$CLIENT_ID" ]]; then
  read -r -p "Client ID: " CLIENT_ID
fi

if [[ -z "$CLIENT_ID" ]]; then
  echo "Cancelled: no client ID entered."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
CURRENT="$TMP_DIR/current-license.json"
NEW="$TMP_DIR/new-license.json"

echo "------ UPDATE $ENVIRONMENT BILLING CONTACT V38M ------"
echo ""
echo "Client: $CLIENT_ID"
echo ""

if ! npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$KV" --remote > "$CURRENT" 2>/dev/null; then
  echo "ERROR: license not found for $CLIENT_ID"
  exit 1
fi

echo "Current billing contact:"
python3 - "$CURRENT" <<'PYSUM'
import json, sys
data=json.load(open(sys.argv[1]))
print("clientName:", data.get("clientName") or data.get("name") or "")
print("billingName:", data.get("billingName") or "")
print("billingEmail:", data.get("billingEmail") or "")
print("billingPhone:", data.get("billingPhone") or "")
print("billingNotes:", data.get("billingNotes") or "")
PYSUM

echo ""
read -r -p "Billing name  [blank to keep current]: " BILLING_NAME
read -r -p "Billing email [blank to keep current]: " BILLING_EMAIL
read -r -p "Billing phone [blank to keep current]: " BILLING_PHONE
read -r -p "Billing notes [blank to keep current]: " BILLING_NOTES

if [[ "$ENVIRONMENT" == "production" ]]; then
  echo ""
  echo "------ AUTO-BACKUP BEFORE PRODUCTION BILLING CONTACT CHANGE ------"
  ./ops/client-manager/backup-clients-v37x.sh production
fi

echo ""
CONFIRM_PHRASE="$CONFIRM_PREFIX $CLIENT_ID"
read -r -p "Type '$CONFIRM_PHRASE' to continue, or press Enter to cancel: " CONFIRM

if [[ "$CONFIRM" != "$CONFIRM_PHRASE" ]]; then
  echo "Cancelled safely. No billing contact change made."
  exit 1
fi

python3 - "$CURRENT" "$NEW" "$ENVIRONMENT" "$BILLING_NAME" "$BILLING_EMAIL" "$BILLING_PHONE" "$BILLING_NOTES" <<'PYWRITE'
import json, sys
from datetime import datetime, timezone

current_file, new_file, environment, billing_name, billing_email, billing_phone, billing_notes = sys.argv[1:8]
data=json.load(open(current_file))

data["ok"] = True
data["billingContactMarker"] = "PB_CLIENT_BILLING_CONTACT_UPDATE_V38M"
data["environment"] = environment
data["updatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00","Z")

if billing_name.strip():
    data["billingName"] = billing_name.strip()
if billing_email.strip():
    data["billingEmail"] = billing_email.strip()
if billing_phone.strip():
    data["billingPhone"] = billing_phone.strip()
if billing_notes.strip():
    data["billingNotes"] = billing_notes.strip()

json.dump(data, open(new_file, "w"), indent=2)
PYWRITE

echo ""
echo "Writing updated billing contact..."
npx wrangler kv key put "client-license:$CLIENT_ID" --path "$NEW" --namespace-id "$KV" --remote

echo ""
echo "Verify billing contact:"
python3 - "$NEW" <<'PYVERIFY'
import json, sys
data=json.load(open(sys.argv[1]))
print("clientId:", data.get("clientId"))
print("billingName:", data.get("billingName") or "")
print("billingEmail:", data.get("billingEmail") or "")
print("billingPhone:", data.get("billingPhone") or "")
print("billingNotes:", data.get("billingNotes") or "")
PYVERIFY

echo ""
echo "GREEN: $ENVIRONMENT billing contact updated."
