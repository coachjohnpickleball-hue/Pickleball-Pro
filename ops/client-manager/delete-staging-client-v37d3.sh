#!/usr/bin/env bash
set -euo pipefail

STAGING_KV="d4be478f609e4696aae597c6adf6c533"

echo "------ SAFE CLIENT DELETE + TOMBSTONE - STAGING ONLY ------"
echo ""
read -r -p "Client ID to delete from staging: " CLIENT

CLIENT="$(echo "$CLIENT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/-+/-/g; s/^-|-$//g')"

if [ -z "$CLIENT" ]; then
  echo "ERROR: No valid client ID."
  exit 1
fi

echo ""
echo "This will delete and tombstone this STAGING client:"
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
echo "DELETE $CLIENT"
read -r -p "Confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE $CLIENT" ]; then
  echo "Cancelled. Nothing deleted."
  exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/tmp/pb-delete-staging-client-$CLIENT-$STAMP"
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
  npx wrangler kv key get "$KEY" --namespace-id "$STAGING_KV" --remote > "$OUT" 2>/dev/null || echo "{}" > "$OUT"
done

echo ""
echo "------ DELETE DIRECT KEYS ------"

for KEY in "${KEYS[@]}"; do
  echo "Deleting: $KEY"
  npx wrangler kv key delete "$KEY" --namespace-id "$STAGING_KV" --remote || true
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
  "environment": "staging",
  "reason": "Deleted from staging client manager",
  "source": "ops-delete-staging-client-v37d3"
}
JSON

npx wrangler kv key put "client-deleted:$CLIENT" --path "$TOMBSTONE" --namespace-id "$STAGING_KV" --remote

echo ""
echo "------ VERIFY KV ------"

for KEY in "${KEYS[@]}"; do
  if npx wrangler kv key get "$KEY" --namespace-id "$STAGING_KV" --remote >/tmp/pb-check.json 2>/dev/null; then
    echo "ERROR: Still exists: $KEY"
    exit 1
  else
    echo "PASS deleted or absent: $KEY"
  fi
done

npx wrangler kv key get "client-deleted:$CLIENT" --namespace-id "$STAGING_KV" --remote >/tmp/pb-tombstone-check.json

echo "PASS tombstone exists: client-deleted:$CLIENT"
echo ""
echo "GREEN: $CLIENT deleted and tombstoned in staging."
echo ""
echo "Backup folder:"
echo "$BACKUP"
echo ""
echo "Chrome Console verification:"
echo "await fetch('/api/client-state?clientId=$CLIENT&v=delete-check-' + Date.now(), { credentials: 'include', cache: 'no-store' }).then(async r => ({ status: r.status, data: await r.json() }))"
