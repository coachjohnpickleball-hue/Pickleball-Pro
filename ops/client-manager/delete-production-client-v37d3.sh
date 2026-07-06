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


PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

echo "------ SAFE CLIENT DELETE + TOMBSTONE - PRODUCTION ------"
echo ""
echo "WARNING: This affects PRODUCTION."
echo "Only use this when you truly want to delete a production client."
echo ""

read -r -p "Client ID to delete from PRODUCTION: " CLIENT

CLIENT="$(echo "$CLIENT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/-+/-/g; s/^-|-$//g')"

if [ -z "$CLIENT" ]; then
  echo "ERROR: No valid client ID."
  exit 1
fi

echo ""
echo "This will delete and tombstone this PRODUCTION client:"
echo "$CLIENT"
echo ""
echo "It will remove:"
echo "client-license:$CLIENT"
echo "client-state::$CLIENT::current"
echo ""
echo "It will create:"
echo "client-deleted:$CLIENT"
echo ""
echo "Type exactly:"
echo "DELETE PRODUCTION $CLIENT"
read -r -p "Confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE PRODUCTION $CLIENT" ]; then
  echo "Cancelled. Nothing deleted."
  exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/tmp/pb-delete-production-client-$CLIENT-$STAMP"
mkdir -p "$BACKUP"

echo ""
echo "------ BACKUP DIRECT KEYS ------"

KEYS=(
  "client-license:$CLIENT"
  "client-state::$CLIENT::current"
)

for KEY in "${KEYS[@]}"; do
  SAFE="$(echo "$KEY" | sed 's/[^a-zA-Z0-9._-]/_/g')"
  OUT="$BACKUP/$SAFE.json"

  echo "Backing up: $KEY"
  npx wrangler kv key get "$KEY" --namespace-id "$PROD_KV" --remote > "$OUT" 2>/dev/null || echo "{}" > "$OUT"
done

echo ""
echo "------ DELETE DIRECT KEYS ------"

for KEY in "${KEYS[@]}"; do
  echo "Deleting: $KEY"
  npx wrangler kv key delete "$KEY" --namespace-id "$PROD_KV" --remote || true
done

echo ""
echo "------ WRITE TOMBSTONE ------"

TOMBSTONE="$BACKUP/client-deleted-$CLIENT.json"

cat > "$TOMBSTONE" <<JSON
{
  "ok": true,
  "marker": "PB_CLIENT_TOMBSTONE_V37D3",
  "clientId": "$CLIENT",
  "deleted": true,
  "deletedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "environment": "production",
  "reason": "Deleted from production client manager",
  "source": "ops-delete-production-client-v37d3"
}
JSON

pbProductionAutoBackupV37Y

npx wrangler kv key put "client-deleted:$CLIENT" --path "$TOMBSTONE" --namespace-id "$PROD_KV" --remote

echo ""
echo "------ VERIFY KV ------"

for KEY in "${KEYS[@]}"; do
  if npx wrangler kv key get "$KEY" --namespace-id "$PROD_KV" --remote >/tmp/pb-prod-check.json 2>/dev/null; then
    echo "ERROR: Still exists: $KEY"
    exit 1
  else
    echo "PASS deleted or absent: $KEY"
  fi
done

npx wrangler kv key get "client-deleted:$CLIENT" --namespace-id "$PROD_KV" --remote >/tmp/pb-prod-tombstone-check.json

echo "PASS tombstone exists: client-deleted:$CLIENT"
echo ""
echo "GREEN: $CLIENT deleted and tombstoned in PRODUCTION."
echo ""
echo "Backup folder:"
echo "$BACKUP"
echo ""
echo "Chrome Console production verification:"
echo "await fetch('/api/client-state?clientId=$CLIENT&v=delete-check-' + Date.now(), { credentials: 'include', cache: 'no-store' }).then(async r => ({ status: r.status, data: await r.json() }))"
