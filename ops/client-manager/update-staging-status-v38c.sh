#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="staging"
KV="d4be478f609e4696aae597c6adf6c533"
CONFIRM_PREFIX="STATUS"

CLIENT_ID="${1:-}"
STATUS="${2:-}"

if [[ -z "$CLIENT_ID" || -z "$STATUS" ]]; then
  echo "Usage: $0 <clientId> <active|suspended|trial>"
  exit 1
fi

case "$STATUS" in
  active|suspended|trial) ;;
  *)
    echo "ERROR: invalid status: $STATUS"
    echo "Allowed: active, suspended, trial"
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
CURRENT="$TMP_DIR/current-license.json"
NEW="$TMP_DIR/new-license.json"

echo "------ UPDATE $ENVIRONMENT CLIENT STATUS V38C ------"
echo "Client: $CLIENT_ID"
echo "New status: $STATUS"

if ! npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$KV" --remote > "$CURRENT" 2>/dev/null; then
  echo "ERROR: license not found for $CLIENT_ID"
  exit 1
fi

if [[ "$ENVIRONMENT" == "production" ]]; then
  echo ""
  echo "------ AUTO-BACKUP BEFORE PRODUCTION STATUS CHANGE ------"
  ./ops/client-manager/backup-clients-v37x.sh production
fi

CONFIRM_PHRASE="$CONFIRM_PREFIX $CLIENT_ID $STATUS"
read -r -p "Type '$CONFIRM_PHRASE' to continue, or press Enter to cancel: " CONFIRM

if [[ "$CONFIRM" != "$CONFIRM_PHRASE" ]]; then
  echo "Cancelled safely. No status change made."
  exit 1
fi

python3 - "$CURRENT" "$NEW" "$STATUS" "$ENVIRONMENT" <<'PYWRITE'
import json, sys
from datetime import datetime, timezone

current_file, new_file, status, environment = sys.argv[1:5]
data = json.load(open(current_file))

data["ok"] = True
data["statusMarker"] = "PB_CLIENT_STATUS_UPDATE_V38C"
data["licenseStatus"] = status
data["status"] = status
data["environment"] = environment
data["updatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

json.dump(data, open(new_file, "w"), indent=2)
PYWRITE

npx wrangler kv key put "client-license:$CLIENT_ID" --path "$NEW" --namespace-id "$KV" --remote

echo ""
echo "GREEN: $ENVIRONMENT client status updated."
