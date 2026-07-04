#!/usr/bin/env bash
set -euo pipefail

PROD_URL="${PROD_URL:-https://rally.coachjohnpickleball.workers.dev}"
PROD_CLIENT_ID="${PROD_CLIENT_ID:-rally-coachjohnpickleball-workers-dev}"
TOKEN="${PB_PROD_ADMIN_LICENSE_TOKEN:-}"

if [ -z "$TOKEN" ]; then
  echo "ERROR: PB_PROD_ADMIN_LICENSE_TOKEN is required."
  echo ""
  echo "Example:"
  echo "  PB_PROD_ADMIN_LICENSE_TOKEN=\"paste-token-here\" bash ops/recovery/restore-production-license-v30b.sh"
  exit 1
fi

echo "Restoring production license to Club / Active..."

RESP="$(curl -i -s -X POST "$PROD_URL/api/admin/client-license?clientId=$PROD_CLIENT_ID" -H "Content-Type: application/json" -H "x-admin-license-token: $TOKEN" --data "{\"clientId\":\"rally-coachjohnpickleball-workers-dev\",\"clientName\":\"Rally\",\"licenseLevel\":\"club\",\"licenseLabel\":\"Club\",\"licenseStatus\":\"active\",\"playerLimit\":40,\"adminSeats\":2,\"mobileScoring\":true,\"officialResults\":true,\"supportTier\":\"standard\",\"source\":\"restore-production-license-v30b\"}" || true)"

echo "$RESP" | head -140

if echo "$RESP" | grep -q "401"; then
  echo ""
  echo "ERROR: token was rejected or Cloudflare Access blocked the request."
  exit 1
fi

echo ""
echo "Verifying production license gate..."
VERIFY="$(curl -i -s "$PROD_URL/api/license-gate?clientId=$PROD_CLIENT_ID&v=restore-v30b-$(date +%s)" || true)"
echo "$VERIFY" | head -100

echo ""
echo "Production license restore request complete."
