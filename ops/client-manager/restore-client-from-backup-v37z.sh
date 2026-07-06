#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
BACKUP_DIR="${2:-}"
CLIENT_ID="${3:-}"
MODE="${4:-license-state}"

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

if [[ "$ENVIRONMENT" == "staging" ]]; then
  KV="$STAGING_KV"
  CONFIRM_PREFIX="RESTORE STAGING"
elif [[ "$ENVIRONMENT" == "production" ]]; then
  KV="$PROD_KV"
  CONFIRM_PREFIX="RESTORE PRODUCTION"
else
  echo "Usage:"
  echo "  ./ops/client-manager/restore-client-from-backup-v37z.sh <staging|production> <backupFolder> <clientId> [license|state|license-state]"
  echo ""
  echo "Example:"
  echo "  ./ops/client-manager/restore-client-from-backup-v37z.sh production ops/client-manager/backups/production-YYYYMMDD-HHMMSS blue-zone-pickleball license-state"
  echo ""
  echo "Available backups:"
  ls -1d ops/client-manager/backups/* 2>/dev/null || true
  exit 1
fi

case "$MODE" in
  license|state|license-state)
    ;;
  *)
    echo "ERROR: invalid mode: $MODE"
    echo "Allowed: license, state, license-state"
    exit 1
    ;;
esac

if [[ -z "$BACKUP_DIR" || -z "$CLIENT_ID" ]]; then
  echo "Usage:"
  echo "  ./ops/client-manager/restore-client-from-backup-v37z.sh <staging|production> <backupFolder> <clientId> [license|state|license-state]"
  echo ""
  echo "Available backups:"
  ls -1d ops/client-manager/backups/${ENVIRONMENT}-* 2>/dev/null || true
  exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "ERROR: backup folder not found:"
  echo "$BACKUP_DIR"
  exit 1
fi

LICENSE_FILE="$BACKUP_DIR/licenses/client-license_${CLIENT_ID}.json"
STATE_FILE="$BACKUP_DIR/states/client-state_${CLIENT_ID}_current.json"

echo "------ RESTORE CLIENT FROM BACKUP V37Z ------"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Client:      $CLIENT_ID"
echo "Mode:        $MODE"
echo "Backup:      $BACKUP_DIR"
echo ""

if [[ "$MODE" == "license" || "$MODE" == "license-state" ]]; then
  if [[ ! -f "$LICENSE_FILE" ]]; then
    echo "ERROR: license backup file not found:"
    echo "$LICENSE_FILE"
    exit 1
  fi
fi

if [[ "$MODE" == "state" || "$MODE" == "license-state" ]]; then
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "ERROR: state backup file not found:"
    echo "$STATE_FILE"
    exit 1
  fi
fi

echo "------ BACKUP CONTENT SUMMARY ------"

if [[ -f "$LICENSE_FILE" ]]; then
  echo ""
  echo "License backup:"
  python3 - "$LICENSE_FILE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print("clientId:", data.get("clientId"))
print("licenseLevel:", data.get("licenseLevel") or data.get("level") or data.get("plan"))
print("licenseStatus:", data.get("licenseStatus") or data.get("status"))
print("playerLimit:", data.get("playerLimit") or data.get("maxPlayers") or data.get("playersLimit"))
PY
fi

if [[ -f "$STATE_FILE" ]]; then
  echo ""
  echo "State backup:"
  python3 - "$STATE_FILE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
state = data.get("state", data) if isinstance(data, dict) else {}
players = state.get("players", []) if isinstance(state, dict) else []
names = [str(p.get("name", "")) for p in players if isinstance(p, dict)]
print("players:", len(players))
print("first 5:", names[:5])
PY
fi

echo ""
echo "------ CURRENT LIVE CONTENT SUMMARY ------"

TMP_DIR="$(mktemp -d)"
CURRENT_LICENSE="$TMP_DIR/current-license.json"
CURRENT_STATE="$TMP_DIR/current-state.json"

if npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$KV" --remote > "$CURRENT_LICENSE" 2>/dev/null; then
  echo ""
  echo "Current live license:"
  python3 - "$CURRENT_LICENSE" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("(unreadable)")
    raise SystemExit
print("licenseLevel:", data.get("licenseLevel") or data.get("level") or data.get("plan"))
print("licenseStatus:", data.get("licenseStatus") or data.get("status"))
print("playerLimit:", data.get("playerLimit") or data.get("maxPlayers") or data.get("playersLimit"))
PY
else
  echo ""
  echo "Current live license: missing"
fi

if npx wrangler kv key get "client-state::$CLIENT_ID::current" --namespace-id "$KV" --remote > "$CURRENT_STATE" 2>/dev/null; then
  echo ""
  echo "Current live state:"
  python3 - "$CURRENT_STATE" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("(unreadable)")
    raise SystemExit
state = data.get("state", data) if isinstance(data, dict) else {}
players = state.get("players", []) if isinstance(state, dict) else []
names = [str(p.get("name", "")) for p in players if isinstance(p, dict)]
print("players:", len(players))
print("first 5:", names[:5])
PY
else
  echo ""
  echo "Current live state: missing"
fi

if [[ "$ENVIRONMENT" == "production" ]]; then
  echo ""
  echo "------ AUTO-BACKUP CURRENT PRODUCTION BEFORE RESTORE ------"
  ./ops/client-manager/backup-clients-v37x.sh production
fi

echo ""
echo "------ CONFIRM RESTORE ------"

CONFIRM_PHRASE="$CONFIRM_PREFIX $CLIENT_ID FROM BACKUP"
read -r -p "Type '$CONFIRM_PHRASE' to restore, or press Enter to cancel: " CONFIRM

if [[ "$CONFIRM" != "$CONFIRM_PHRASE" ]]; then
  echo "Cancelled safely. No restore performed."
  exit 1
fi

echo ""
echo "------ RESTORE NOW ------"

if [[ "$MODE" == "license" || "$MODE" == "license-state" ]]; then
  echo "Restoring license..."
  npx wrangler kv key put "client-license:$CLIENT_ID" --path "$LICENSE_FILE" --namespace-id "$KV" --remote
fi

if [[ "$MODE" == "state" || "$MODE" == "license-state" ]]; then
  echo "Restoring state..."
  npx wrangler kv key put "client-state::$CLIENT_ID::current" --path "$STATE_FILE" --namespace-id "$KV" --remote
fi

echo ""
echo "------ VERIFY RESTORE ------"

./ops/client-manager/inspect-client-v37j.sh "$ENVIRONMENT" "$CLIENT_ID" || true
./ops/client-manager/license-usage-audit-v37q.sh "$ENVIRONMENT" | grep -E "$CLIENT_ID|OVER_LIMIT|GREEN" || true

echo ""
echo "GREEN: $ENVIRONMENT restore completed for $CLIENT_ID."
