#!/usr/bin/env bash
set -euo pipefail
set +x

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKER_DIR="$PROJECT_DIR/worker"

cd "$WORKER_DIR"

echo "=============================================="
echo " PickleBall Pro SMS Settings V39A"
echo "=============================================="
echo ""
echo "This sets Cloudflare Worker secrets."
echo "Secrets are NOT written to Git or saved in this script."
echo ""

echo "Choose environment:"
echo "  1) staging"
echo "  2) production"
echo "  3) both"
echo ""
read -r -p "Choice [1/2/3]: " ENV_CHOICE

case "$ENV_CHOICE" in
  1) ENVS=("staging") ;;
  2) ENVS=("rally") ;;
  3) ENVS=("staging" "rally") ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac

echo ""
read -r -p "Twilio Account SID, starts with AC: " TWILIO_ACCOUNT_SID
read -r -s -p "Twilio Auth Token: " TWILIO_AUTH_TOKEN
echo ""
read -r -p "Twilio From phone number, example +14165551234: " TWILIO_FROM
read -r -p "Max SMS per day [200]: " MAX_SMS_PER_DAY
MAX_SMS_PER_DAY="${MAX_SMS_PER_DAY:-200}"

if [[ -z "$TWILIO_ACCOUNT_SID" || -z "$TWILIO_AUTH_TOKEN" || -z "$TWILIO_FROM" ]]; then
  echo "ERROR: SID, token, and from number are required."
  exit 1
fi

if [[ "$TWILIO_ACCOUNT_SID" != AC* ]]; then
  echo "WARNING: Twilio Account SID usually starts with AC."
fi

put_secret() {
  local wrangler_env="$1"
  local name="$2"
  local value="$3"

  echo ""
  echo "Setting $name for env: $wrangler_env"
  printf '%s' "$value" | npx wrangler secret put "$name" --env "$wrangler_env"
}

for ENV in "${ENVS[@]}"; do
  echo ""
  echo "----------------------------------------------"
  echo "Applying SMS settings to: $ENV"
  echo "----------------------------------------------"

  put_secret "$ENV" "TWILIO_ACCOUNT_SID" "$TWILIO_ACCOUNT_SID"
  put_secret "$ENV" "TWILIO_AUTH_TOKEN" "$TWILIO_AUTH_TOKEN"
  put_secret "$ENV" "TWILIO_FROM" "$TWILIO_FROM"
  put_secret "$ENV" "MAX_SMS_PER_DAY" "$MAX_SMS_PER_DAY"

  echo ""
  echo "Secret list for $ENV:"
  npx wrangler secret list --env "$ENV"
done

echo ""
echo "GREEN: SMS Worker secrets updated."
echo ""
echo "Production env name is: rally"
echo "Staging env name is: staging"
