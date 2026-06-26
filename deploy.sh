#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  deploy.sh — build and deploy Pickleball Pro for a specific client
#
#  Usage:
#    ./deploy.sh coachjohn       # redeploy your own instance
#    ./deploy.sh burlington      # redeploy a client
#
#  To onboard a NEW client from scratch, use:
#    ./new-client.sh
# ─────────────────────────────────────────────────────────────────
set -e

CLIENT=$1

if [ -z "$CLIENT" ]; then
  echo "Usage: ./deploy.sh <clientid>"
  echo ""
  echo "Available clients:"
  ls clients/*.json 2>/dev/null | sed 's|clients/||;s|\.json||' | grep -v template | sed 's/^/  /'
  echo ""
  echo "To add a new client: ./new-client.sh"
  exit 1
fi

if [ ! -f "clients/${CLIENT}.json" ]; then
  echo "✗ No config found for client '${CLIENT}'"
  echo "  Run ./new-client.sh to set up a new client."
  exit 1
fi

# Install build dependencies if needed
if [ ! -d "node_modules" ]; then
  echo "→ Installing build dependencies..."
  npm install
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Deploying: ${CLIENT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "→ Building..."
node build.js --client "${CLIENT}"

echo ""
echo "→ Deploying to Cloudflare (env: ${CLIENT})..."
cd worker && npx wrangler deploy --env "${CLIENT}" && cd ..

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Done! ${CLIENT} is live."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
