#!/usr/bin/env bash
set -euo pipefail

PROD_KV="faac1bcc30ef4711a9377e60ef70636d"
PROD_URL="https://rally.coachjohnpickleball.workers.dev"

echo "------ SAFE CLIENT CREATE - PRODUCTION ------"
echo ""
echo "WARNING: This creates a PRODUCTION client."
echo "Only continue when you truly want a new live client."
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
echo "This will create this PRODUCTION client:"
echo "Name: $CLIENT_NAME"
echo "ID:   $CLIENT_ID"
echo ""
echo "It will create:"
echo "client-license:$CLIENT_ID"
echo ""
echo "Type exactly:"
echo "CREATE PRODUCTION $CLIENT_ID"
read -r -p "Confirm: " CONFIRM

if [ "$CONFIRM" != "CREATE PRODUCTION $CLIENT_ID" ]; then
  echo "Cancelled. Nothing created."
  exit 0
fi

echo ""
echo "------ SAFETY CHECKS ------"

if npx wrangler kv key get "client-deleted:$CLIENT_ID" --namespace-id "$PROD_KV" --remote >/tmp/pb-prod-create-tombstone-check.json 2>/dev/null; then
  echo "ERROR: This production client has a tombstone and cannot be recreated safely:"
  echo "client-deleted:$CLIENT_ID"
  echo ""
  echo "Use a different clientId, or build a separate revive tool later."
  exit 1
else
  echo "PASS: no tombstone found."
fi

if npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$PROD_KV" --remote >/tmp/pb-prod-create-license-check.json 2>/dev/null; then
  echo "ERROR: Production client license already exists:"
  echo "client-license:$CLIENT_ID"
  echo ""
  echo "Nothing changed."
  exit 1
else
  echo "PASS: no existing license found."
fi

if npx wrangler kv key get "client-state::$CLIENT_ID::current" --namespace-id "$PROD_KV" --remote >/tmp/pb-prod-create-state-check.json 2>/dev/null; then
  echo "ERROR: Production client state already exists:"
  echo "client-state::$CLIENT_ID::current"
  echo ""
  echo "Nothing changed."
  exit 1
else
  echo "PASS: no existing client state found."
fi

STAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TMP="/tmp/pb-create-production-client-$CLIENT_ID.json"

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
  "environment": "production",
  "source": "ops-create-production-client-v37e",
  "createdAt": "$STAMP",
  "updatedAt": "$STAMP"
}
JSON

echo ""
echo "------ WRITE PRODUCTION LICENSE ------"

npx wrangler kv key put "client-license:$CLIENT_ID" --path "$TMP" --namespace-id "$PROD_KV" --remote

echo ""
echo "------ VERIFY PRODUCTION LICENSE ------"

npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$PROD_KV" --remote >/tmp/pb-prod-created-client-check.json

echo "GREEN: Client created in PRODUCTION."
echo ""
echo "Private production link:"
echo "$PROD_URL/?clientId=$CLIENT_ID"
echo ""
echo "Admin check:"
echo "await fetch('/admin/clients?v=create-prod-check-' + Date.now(), { credentials: 'include', cache: 'no-store' }).then(r => r.json()).then(d => d.clients.filter(c => String(c.clientId || c.clientName).includes('$CLIENT_ID')))"
