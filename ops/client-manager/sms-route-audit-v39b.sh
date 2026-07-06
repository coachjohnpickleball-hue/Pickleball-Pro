#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="ops/client-manager/reports"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$REPORT_DIR/sms-route-audit-v39b-$STAMP.txt"

mkdir -p "$REPORT_DIR"

echo "==============================================" | tee "$OUT"
echo " PickleBall Pro SMS Route Audit V39B" | tee -a "$OUT"
echo "==============================================" | tee -a "$OUT"
echo "" | tee -a "$OUT"
echo "Read-only. No deploy. No KV changes. No SMS sent." | tee -a "$OUT"
echo "" | tee -a "$OUT"

echo "------ SMS / TWILIO REFERENCES ------" | tee -a "$OUT"
grep -RIn "TWILIO\|Twilio\|SMS\|sms\|Messages.json\|send.*message\|message.*send" \
  worker/src public mobile-sync-worker/src 2>/dev/null \
  | tee -a "$OUT" || true

echo "" | tee -a "$OUT"
echo "------ POSSIBLE API ROUTES ------" | tee -a "$OUT"
grep -RIn "pathname\|/api/\|url.pathname\|request.url\|fetch(" \
  worker/src/index.js worker/src/app.html public/index.html mobile-sync-worker/src 2>/dev/null \
  | grep -Ei "sms|message|notify|twilio|api" \
  | tee -a "$OUT" || true

echo "" | tee -a "$OUT"
echo "------ WORKER SECRET NAMES IN CODE ------" | tee -a "$OUT"
grep -RIn "TWILIO_ACCOUNT_SID\|TWILIO_AUTH_TOKEN\|TWILIO_FROM\|MAX_SMS_PER_DAY" \
  worker/src public mobile-sync-worker/src 2>/dev/null \
  | tee -a "$OUT" || true

echo "" | tee -a "$OUT"
echo "------ CLOUDFLARE SECRET NAMES: STAGING ------" | tee -a "$OUT"
(
  cd worker
  npx wrangler secret list --env staging | grep -E "TWILIO_ACCOUNT_SID|TWILIO_AUTH_TOKEN|TWILIO_FROM|MAX_SMS_PER_DAY" || true
) | tee -a "$OUT"

echo "" | tee -a "$OUT"
echo "------ CLOUDFLARE SECRET NAMES: PRODUCTION ------" | tee -a "$OUT"
(
  cd worker
  npx wrangler secret list --env rally | grep -E "TWILIO_ACCOUNT_SID|TWILIO_AUTH_TOKEN|TWILIO_FROM|MAX_SMS_PER_DAY" || true
) | tee -a "$OUT"

echo "" | tee -a "$OUT"
echo "GREEN: SMS route audit complete." | tee -a "$OUT"
echo "Report:" | tee -a "$OUT"
echo "$OUT" | tee -a "$OUT"
