#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  new-client.sh — onboard a new Pickleball Pro client
#
#  Usage:  ./new-client.sh
#
#  This script walks you through every step to get a new client
#  fully isolated and running on your Cloudflare account:
#    1. Creates their config file in clients/
#    2. Creates their KV namespace on Cloudflare
#    3. Builds and deploys their Worker
#    4. Prompts you to set their secrets
#    5. Reminds you to set up Cloudflare Access
# ─────────────────────────────────────────────────────────────────
set -e

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Pickleball Pro — New Client Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Collect client info ────────────────────────────────────
echo "Step 1 of 5: Client details"
echo ""

read -p "  Client ID (lowercase, no spaces — e.g. burlington): " CLIENT_ID
if [ -z "$CLIENT_ID" ]; then echo "✗ Client ID required"; exit 1; fi
if [ -f "clients/${CLIENT_ID}.json" ]; then
  echo "✗ clients/${CLIENT_ID}.json already exists. Edit it directly or delete it first."
  exit 1
fi

read -p "  Club name (e.g. Burlington Pickleball Club): " CLIENT_NAME
if [ -z "$CLIENT_NAME" ]; then echo "✗ Club name required"; exit 1; fi

read -p "  Admin email (gets login alerts + admin reports): " ADMIN_EMAIL
if [ -z "$ADMIN_EMAIL" ]; then echo "✗ Admin email required"; exit 1; fi

read -p "  App name shown in UI (default: Pickleball Pro): " APP_NAME
APP_NAME="${APP_NAME:-Pickleball Pro}"

WORKER_NAME="pickleball-relay-${CLIENT_ID}"

echo ""
echo "  Will create:"
echo "    Config:  clients/${CLIENT_ID}.json"
echo "    Worker:  ${WORKER_NAME}.$(npx wrangler whoami 2>/dev/null | grep 'workers.dev' | head -1 || echo 'your-account').workers.dev"
echo ""
read -p "  Looks good? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then echo "Cancelled."; exit 0; fi

# ── Step 2: Create KV namespace ────────────────────────────────────
echo ""
echo "Step 2 of 5: Creating KV namespace..."
echo ""

KV_OUTPUT=$(cd worker && npx wrangler kv namespace create USAGE --env "$CLIENT_ID" 2>&1 || true)
echo "$KV_OUTPUT"

# Extract the KV namespace ID from wrangler output
KV_ID=$(echo "$KV_OUTPUT" | grep -o '"id": "[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$KV_ID" ]; then
  echo ""
  echo "  Could not auto-detect KV namespace ID from wrangler output."
  read -p "  Paste the KV namespace ID from above: " KV_ID
fi
echo "  KV namespace ID: $KV_ID"

# ── Step 3: Create client config ───────────────────────────────────
echo ""
echo "Step 3 of 5: Creating client config..."

cat > "clients/${CLIENT_ID}.json" << CFGEOF
{
  "client": {
    "id":          "${CLIENT_ID}",
    "name":        "${CLIENT_NAME}",
    "adminEmail":  "${ADMIN_EMAIL}"
  },

  "branding": {
    "appName":     "${APP_NAME}",
    "logoEmoji":   "🏓",
    "primaryColor": "#C6FF00",
    "accentColor":  "#FF9800"
  },

  "worker": {
    "name":        "${WORKER_NAME}",
    "kvNamespaceId": "${KV_ID}"
  },

  "limits": {
    "maxSmsPerDay":   200,
    "maxEmailPerDay": 500
  },

  "features": {
    "sms":         true,
    "email":       true,
    "mobileSync":  true,
    "playoffs":    true,
    "season":      true,
    "duprExport":  true
  }
}
CFGEOF

echo "  Created clients/${CLIENT_ID}.json"

# ── Step 4: Add env block to wrangler.toml ─────────────────────────
echo ""
echo "Step 4 of 5: Updating wrangler.toml..."

TOML_PATH="worker/wrangler.toml"
ENV_MARKER="[env.${CLIENT_ID}]"

if grep -q "$ENV_MARKER" "$TOML_PATH"; then
  echo "  wrangler.toml already has ${ENV_MARKER} — skipping."
else
  cat >> "$TOML_PATH" << TOMLEOF

[env.${CLIENT_ID}]
name = "${WORKER_NAME}"

[[env.${CLIENT_ID}.kv_namespaces]]
binding = "USAGE"
id = "${KV_ID}"

[env.${CLIENT_ID}.vars]
MAX_SMS_PER_DAY   = "200"
MAX_EMAIL_PER_DAY = "500"
TOMLEOF
  echo "  Added [env.${CLIENT_ID}] to wrangler.toml"
fi

# ── Step 5: Build and deploy ───────────────────────────────────────
echo ""
echo "Step 5 of 5: Building and deploying..."
echo ""

node build.js --client "${CLIENT_ID}"
cd worker && npx wrangler deploy --env "${CLIENT_ID}" && cd ..

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ ${CLIENT_NAME} is deployed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Set secrets for this client:"
echo "     cd worker"
echo "     npx wrangler secret put TWILIO_ACCOUNT_SID --env ${CLIENT_ID}"
echo "     npx wrangler secret put TWILIO_AUTH_TOKEN  --env ${CLIENT_ID}"
echo "     npx wrangler secret put TWILIO_FROM        --env ${CLIENT_ID}"
echo "     npx wrangler secret put BREVO_API_KEY      --env ${CLIENT_ID}"
echo "     npx wrangler secret put SMTP_FROM          --env ${CLIENT_ID}"
echo "     npx wrangler secret put SMTP_FROM_NAME     --env ${CLIENT_ID}"
echo "     cd .."
echo ""
echo "  2. Set up Cloudflare Access:"
echo "     → dash.cloudflare.com > Zero Trust > Access > Applications"
echo "     → Add application for: ${WORKER_NAME}.*.workers.dev"
echo "     → Add ${ADMIN_EMAIL} (and any other approved users) to the policy"
echo ""
echo "  3. Share the URL with your client:"
echo "     https://${WORKER_NAME}.coachjohnpickleball.workers.dev"
echo ""
echo "  To redeploy after changes:"
echo "     ./deploy.sh ${CLIENT_ID}"
echo ""
