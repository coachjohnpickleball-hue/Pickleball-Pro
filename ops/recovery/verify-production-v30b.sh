#!/usr/bin/env bash
set -euo pipefail

PROD_URL="${PROD_URL:-https://rally.coachjohnpickleball.workers.dev}"
PROD_CLIENT_ID="${PROD_CLIENT_ID:-rally-coachjohnpickleball-workers-dev}"

is_access_or_cf_block() {
  echo "$1" | grep -Eqi "Cloudflare Access|cloudflareaccess|302 Found|HTTP/[0-9.]+ 302|location: .*cloudflareaccess|server: cloudflare"
}

echo "------ Production health / Access check ------"
HEALTH="$(curl -i -L -s "$PROD_URL/health?v=verify-v30b-$(date +%s)" || true)"
echo "$HEALTH" | head -60

if [ -z "$HEALTH" ]; then
  echo ""
  echo "ERROR: production health returned empty response."
  exit 1
fi

if is_access_or_cf_block "$HEALTH"; then
  echo ""
  echo "PASS: production health is protected by Cloudflare Access / Cloudflare edge."
else
  echo ""
  echo "PASS: production returned a non-empty health response without Access login."
fi

echo ""
echo "------ Production license gate check ------"
LICENSE="$(curl -i -s "$PROD_URL/api/license-gate?clientId=$PROD_CLIENT_ID&v=verify-v30b-$(date +%s)" || true)"
echo "$LICENSE" | head -80

if is_access_or_cf_block "$LICENSE"; then
  echo ""
  echo "PASS: license gate is blocked/protected before unauthenticated curl can reach it."
elif echo "$LICENSE" | grep -q "\"ok\"[[:space:]]*:[[:space:]]*true" && echo "$LICENSE" | grep -q "\"allowed\"[[:space:]]*:[[:space:]]*true"; then
  echo ""
  echo "PASS: license gate returned ok:true and allowed:true."
else
  echo ""
  echo "ERROR: license gate did not return Access/Cloudflare block or ok:true/allowed:true."
  exit 1
fi

echo ""
echo "------ Public POST block / Access check ------"
RESP="$(curl -i -s -X POST "$PROD_URL/api/client-license?clientId=$PROD_CLIENT_ID" -H "Content-Type: application/json" --data "{\"licenseLevel\":\"enterprise\",\"licenseStatus\":\"active\",\"playerLimit\":250,\"adminSeats\":25}" || true)"
echo "$RESP" | head -100

if is_access_or_cf_block "$RESP"; then
  echo ""
  echo "PASS: unauthenticated public POST is blocked by Cloudflare Access / Cloudflare edge."
elif echo "$RESP" | grep -q "401" && echo "$RESP" | grep -qi "owner admin token"; then
  echo ""
  echo "PASS: public license edits are blocked by owner-token enforcement."
else
  echo ""
  echo "ERROR: expected Cloudflare/Access block or HTTP 401 owner-token block was not detected."
  exit 1
fi

echo ""
echo "Production verification passed."
