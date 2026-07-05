#!/usr/bin/env bash
set -euo pipefail

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
STAGING_URL="https://rally-staging.coachjohnpickleball.workers.dev"

echo "------ SAFE CLIENT CREATE - STAGING ONLY ------"
echo ""

read -r -p "Client display name, example Blue Zone Pickleball: " CLIENT_NAME

if [ -z "${CLIENT_NAME// }" ]; then
  echo "ERROR: Client display name is required."
  exit 1
fi

SUGGESTED_ID="$(echo "$CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-|-$//g')"

echo ""
echo "Suggested clientId:"
echo "$SUGGESTED_ID"
echo ""
read -r -p "Client ID to use, press Enter for suggested: " CLIENT_ID

CLIENT_ID="${CLIENT_ID:-$SUGGESTED_ID}"
CLIENT_ID="$(echo "$CLIENT_ID" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/-+/-/g; s/^-|-$//g')"

if [ -z "$CLIENT_ID" ]; then
  echo "ERROR: No valid client ID."
  exit 1
fi

echo ""
echo "This will create this STAGING client:"
echo "Name: $CLIENT_NAME"
echo "ID:   $CLIENT_ID"
echo ""
echo "Type exactly:"
echo "CREATE $CLIENT_ID"
read -r -p "Confirm: " CONFIRM

if [ "$CONFIRM" != "CREATE $CLIENT_ID" ]; then
  echo "Cancelled. Nothing created."
  exit 0
fi

echo ""
echo "------ SAFETY CHECKS ------"

if npx wrangler kv key get "client-deleted:$CLIENT_ID" --namespace-id "$STAGING_KV" --remote >/tmp/pb-create-tombstone-check.json 2>/dev/null; then
  echo "ERROR: This client has a tombstone and cannot be recreated safely:"
  echo "client-deleted:$CLIENT_ID"
  echo ""
  echo "Use a different clientId, or build a separate revive tool later."
  exit 1
else
  echo "PASS: no tombstone found."
fi

if npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$STAGING_KV" --remote >/tmp/pb-create-license-check.json 2>/dev/null; then
  echo "ERROR: Client license already exists:"
  echo "client-license:$CLIENT_ID"
  echo ""
  echo "Nothing changed."
  exit 1
else
  echo "PASS: no existing license found."
fi

STAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TMP="/tmp/pb-create-staging-client-$CLIENT_ID.json"

cat > "$TMP" <<JSON
{
  "ok": true,
  "marker": "PB_SAFE_CLIENT_CREATE_V37E",
  "clientId": "$CLIENT_ID",
  "clientName": "$CLIENT_NAME",
  "licenseLevel": "club",
  "licenseLabel": "Club",
  "licenseStatus": "active",
  "playerLimit": 40,
  "mobileScoring": true,
  "officialResults": true,
  "support": "Standard support",
  "environment": "staging",
  "source": "ops-create-staging-client-v37e",
  "createdAt": "$STAMP",
  "updatedAt": "$STAMP"
}
JSON

echo ""
echo "------ WRITE LICENSE ------"

npx wrangler kv key put "client-license:$CLIENT_ID" --path "$TMP" --namespace-id "$STAGING_KV" --remote

echo ""
echo "------ VERIFY LICENSE ------"

npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$STAGING_KV" --remote >/tmp/pb-created-client-check.json

echo "GREEN: Client created in staging."
echo ""
echo "Private staging link:"
echo "$STAGING_URL/?clientId=$CLIENT_ID"
echo ""
echo "Admin check:"
echo "await fetch('/admin/clients?v=create-check-' + Date.now(), { credentials: 'include', cache: 'no-store' }).then(r => r.json()).then(d => d.clients.filter(c => String(c.clientId || c.clientName).includes('$CLIENT_ID')))"
