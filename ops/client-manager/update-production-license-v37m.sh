#!/usr/bin/env bash
set -euo pipefail

pbProductionAutoBackupV37Y() {
  echo ""
  echo "------ AUTO-BACKUP BEFORE PRODUCTION CHANGE V37Y ------"

  if [[ -x "./ops/client-manager/backup-clients-v37x.sh" ]]; then
    ./ops/client-manager/backup-clients-v37x.sh production
  else
    echo "ERROR: backup tool missing: ./ops/client-manager/backup-clients-v37x.sh"
    echo "Refusing production change without backup."
    exit 1
  fi

  echo ""
  echo "GREEN: production backup completed before change."
}


ENVIRONMENT="production"
KV="faac1bcc30ef4711a9377e60ef70636d"
CONFIRM_PREFIX="UPDATE PRODUCTION"
FORCE_PREFIX="FORCE PRODUCTION DOWNGRADE"

CLIENT_ID="${1:-}"
LEVEL="${2:-}"

if [[ -z "$CLIENT_ID" || -z "$LEVEL" ]]; then
  echo "Usage:"
  echo "  $0 <clientId> <trial|club|pro|enterprise>"
  exit 1
fi

case "$LEVEL" in
  trial)
    LABEL="Trial"; LIMIT=16; MOBILE=false; OFFICIAL=false ;;
  club)
    LABEL="Club"; LIMIT=40; MOBILE=true; OFFICIAL=true ;;
  pro)
    LABEL="Pro"; LIMIT=96; MOBILE=true; OFFICIAL=true ;;
  enterprise)
    LABEL="Enterprise"; LIMIT=250; MOBILE=true; OFFICIAL=true ;;
  *)
    echo "ERROR: invalid level: $LEVEL"
    echo "Allowed: trial, club, pro, enterprise"
    exit 1 ;;
esac

TMP_DIR="$(mktemp -d)"
STATE_FILE="$TMP_DIR/current-state.json"
LICENSE_FILE="$TMP_DIR/license.json"

echo "------ UPDATE $ENVIRONMENT LICENSE V37M/V37T ------"
echo "Client: $CLIENT_ID"
echo "New level: $LEVEL"
echo "New player limit: $LIMIT"
echo ""

echo "------ CURRENT PLAYER USAGE CHECK ------"

ACTIVE_PLAYERS=0
TOTAL_PLAYERS=0
HAS_STATE="no"

if npx wrangler kv key get "client-state::$CLIENT_ID::current" --namespace-id "$KV" --remote > "$STATE_FILE" 2>/dev/null; then
  HAS_STATE="yes"
  COUNTS="$(python3 - "$STATE_FILE" <<'PYCOUNTS'
import json, sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("0 0")
    raise SystemExit

state = data.get("state", data) if isinstance(data, dict) else {}
players = state.get("players", []) if isinstance(state, dict) else []

if not isinstance(players, list):
    players = []

active = [
    p for p in players
    if isinstance(p, dict)
    and p.get("active", True) is not False
    and p.get("waitlist", False) is not True
]

print(len(active), len(players))
PYCOUNTS
)"
  ACTIVE_PLAYERS="$(echo "$COUNTS" | awk '{print $1}')"
  TOTAL_PLAYERS="$(echo "$COUNTS" | awk '{print $2}')"
fi

echo "State found: $HAS_STATE"
echo "Active players: $ACTIVE_PLAYERS"
echo "Total players: $TOTAL_PLAYERS"
echo "Requested limit: $LIMIT"

if [[ "$ACTIVE_PLAYERS" -gt "$LIMIT" ]]; then
  echo ""
  echo "STOP: This license change would put the client over limit."
  echo "Client has $ACTIVE_PLAYERS active players."
  echo "$LABEL allows only $LIMIT active players."
  echo ""
  echo "Recommended: choose a plan that supports at least $ACTIVE_PLAYERS players, or deactivate players first."
  echo ""
  read -r -p "Type '$FORCE_PREFIX $CLIENT_ID $LEVEL' to override, or press Enter to cancel: " FORCE_CONFIRM

  if [[ "$FORCE_CONFIRM" != "$FORCE_PREFIX $CLIENT_ID $LEVEL" ]]; then
    echo "Cancelled safely. No license change made."
    exit 1
  fi

  echo "Override accepted. Continuing."
fi

echo ""
echo "------ CONFIRM LICENSE UPDATE ------"

CONFIRM_PHRASE="$CONFIRM_PREFIX $CLIENT_ID $LEVEL"
read -r -p "Type '$CONFIRM_PHRASE' to continue: " CONFIRM

if [[ "$CONFIRM" != "$CONFIRM_PHRASE" ]]; then
  echo "Cancelled. No license change made."
  exit 1
fi

cat > "$LICENSE_FILE" <<EOF
{
  "ok": true,
  "marker": "PB_SAFE_LICENSE_UPDATE_V37M",
  "safetyMarker": "PB_LICENSE_DOWNGRADE_GUARD_V37T",
  "clientId": "$CLIENT_ID",
  "licenseLevel": "$LEVEL",
  "licenseLabel": "$LABEL",
  "licenseStatus": "active",
  "playerLimit": $LIMIT,
  "mobileScoring": $MOBILE,
  "officialResults": $OFFICIAL,
  "environment": "$ENVIRONMENT",
  "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo ""
echo "------ WRITE LICENSE ------"
pbProductionAutoBackupV37Y

npx wrangler kv key put "client-license:$CLIENT_ID" --path "$LICENSE_FILE" --namespace-id "$KV" --remote

echo ""
echo "------ VERIFY LICENSE ------"
npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$KV" --remote

echo ""
echo "GREEN: $ENVIRONMENT license updated safely."
