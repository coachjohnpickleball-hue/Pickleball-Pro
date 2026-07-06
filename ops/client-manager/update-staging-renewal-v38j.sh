#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="staging"
KV="d4be478f609e4696aae597c6adf6c533"
CONFIRM_PREFIX="RENEWAL"

CLIENT_ID="${1:-}"
RENEWAL_DATE="${2:-}"
FIELD="${3:-renewalDate}"

if [[ -z "$CLIENT_ID" || -z "$RENEWAL_DATE" ]]; then
  echo "Usage:"
  echo "  $0 <clientId> <YYYY-MM-DD|clear> [renewalDate|expiresAt|subscriptionEndsAt|trialEndsAt]"
  echo ""
  echo "Examples:"
  echo "  $0 blue-zone-pickleball 2026-12-31"
  echo "  $0 blue-zone-pickleball clear"
  exit 1
fi

case "$FIELD" in
  renewalDate|expiresAt|subscriptionEndsAt|trialEndsAt) ;;
  *)
    echo "ERROR: invalid field: $FIELD"
    echo "Allowed: renewalDate, expiresAt, subscriptionEndsAt, trialEndsAt"
    exit 1
    ;;
esac

if [[ "$RENEWAL_DATE" != "clear" ]]; then
  python3 - "$RENEWAL_DATE" <<'PYDATE'
import sys
from datetime import date
try:
    date.fromisoformat(sys.argv[1])
except Exception:
    print("ERROR: date must be YYYY-MM-DD or clear")
    raise SystemExit(1)
PYDATE
fi

TMP_DIR="$(mktemp -d)"
CURRENT="$TMP_DIR/current-license.json"
NEW="$TMP_DIR/new-license.json"

echo "------ UPDATE $ENVIRONMENT RENEWAL / EXPIRY DATE V38J ------"
echo ""
echo "Client: $CLIENT_ID"
echo "Field:  $FIELD"
echo "Value:  $RENEWAL_DATE"
echo ""

if ! npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$KV" --remote > "$CURRENT" 2>/dev/null; then
  echo "ERROR: license not found for $CLIENT_ID"
  exit 1
fi

echo "Current license summary:"
python3 - "$CURRENT" <<'PYSUM'
import json, sys
data=json.load(open(sys.argv[1]))
print("clientId:", data.get("clientId"))
print("clientName:", data.get("clientName") or data.get("name"))
print("level:", data.get("licenseLevel") or data.get("level") or data.get("plan"))
print("status:", data.get("licenseStatus") or data.get("status"))
print("renewalDate:", data.get("renewalDate"))
print("expiresAt:", data.get("expiresAt"))
print("subscriptionEndsAt:", data.get("subscriptionEndsAt"))
print("trialEndsAt:", data.get("trialEndsAt"))
PYSUM

if [[ "$ENVIRONMENT" == "production" ]]; then
  echo ""
  echo "------ AUTO-BACKUP BEFORE PRODUCTION RENEWAL DATE CHANGE ------"
  ./ops/client-manager/backup-clients-v37x.sh production
fi

echo ""
CONFIRM_PHRASE="$CONFIRM_PREFIX $CLIENT_ID $FIELD $RENEWAL_DATE"
read -r -p "Type '$CONFIRM_PHRASE' to continue, or press Enter to cancel: " CONFIRM

if [[ "$CONFIRM" != "$CONFIRM_PHRASE" ]]; then
  echo "Cancelled safely. No renewal date change made."
  exit 1
fi

python3 - "$CURRENT" "$NEW" "$FIELD" "$RENEWAL_DATE" "$ENVIRONMENT" <<'PYWRITE'
import json, sys
from datetime import datetime, timezone

current_file, new_file, field, value, environment = sys.argv[1:6]
data=json.load(open(current_file))

data["ok"] = True
data["renewalMarker"] = "PB_CLIENT_RENEWAL_DATE_UPDATE_V38J"
data["environment"] = environment
data["updatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00","Z")

if value == "clear":
    data.pop(field, None)
else:
    data[field] = value

json.dump(data, open(new_file, "w"), indent=2)
PYWRITE

echo ""
echo "Writing updated license..."
npx wrangler kv key put "client-license:$CLIENT_ID" --path "$NEW" --namespace-id "$KV" --remote

echo ""
echo "Verify:"
npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$KV" --remote

echo ""
echo "GREEN: $ENVIRONMENT renewal / expiry date updated."
