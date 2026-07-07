#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ENVIRONMENT="${1:-production}"
CLIENT_ID="${2:-all}"

if [ "$ENVIRONMENT" = "production" ]; then
  KV_ID="faac1bcc30ef4711a9377e60ef70636d"
  MOBILE_URL="https://pickleball-mobile-sync-v2.coachjohnpickleball.workers.dev"
elif [ "$ENVIRONMENT" = "staging" ]; then
  KV_ID="d4be478f609e4696aae597c6adf6c533"
  MOBILE_URL="https://pickleball-mobile-sync-v2-staging.coachjohnpickleball.workers.dev"
else
  echo "ERROR: use production or staging"
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="ops/client-manager/reports/client-health-report-v39r-${ENVIRONMENT}-${CLIENT_ID}-${STAMP}.txt"

echo "PickleBall Pro Client Health Report V39R" | tee "$OUT"
echo "Generated: $(date)" | tee -a "$OUT"
echo "Environment: $ENVIRONMENT" | tee -a "$OUT"
echo "Client: $CLIENT_ID" | tee -a "$OUT"
echo "Read-only. No deploy. No production writes." | tee -a "$OUT"
echo "" | tee -a "$OUT"

echo "------ GIT STATUS ------" | tee -a "$OUT"
git status --short | tee -a "$OUT"
echo "" | tee -a "$OUT"

echo "------ RECENT COMMITS ------" | tee -a "$OUT"
git log --oneline -6 | tee -a "$OUT"
echo "" | tee -a "$OUT"

echo "------ LOCAL RELEASE MARKERS ------" | tee -a "$OUT"
grep -o "PB_ADMIN_STATIC_HEADER_V39K\|PB_SMS_SETTINGS_PERSIST_V39L\|PB_PLAYER_IMPORT_EXPORT_CLEANUP_V39M\|PB_PLAYER_SEARCH_FILTER_V39N\|PB_ADMIN_DIRECT_HTML_CLEANUP_V39O" public/index.html worker/src/app.html \
  | sort | uniq | tee -a "$OUT" || true
echo "" | tee -a "$OUT"

echo "------ MOBILE LIVE MARKER ------" | tee -a "$OUT"
curl -L -s "$MOBILE_URL?v=v39r-$STAMP" \
  | grep -o "PB_MOBILE_SYNC_UI_POLISH_V39P" \
  | head -3 | tee -a "$OUT" || true
echo "" | tee -a "$OUT"

echo "------ BAD ADMIN MARKERS CHECK ------" | tee -a "$OUT"
BAD="$(grep -o "PB_ADMIN_LAYOUT_POLISH_V39E\|PB_ADMIN_CARD_ORGANIZER_V39F\|PB_GAME_DAY_CONTROL_CENTER\|PB_CLIENT_ACCOUNT_STATUS" public/index.html worker/src/app.html || true)"
if [ -z "$BAD" ]; then
  echo "GREEN: no twitchy admin markers found." | tee -a "$OUT"
else
  echo "$BAD" | sort | uniq | tee -a "$OUT"
fi
echo "" | tee -a "$OUT"

echo "------ CLIENT LIST ------" | tee -a "$OUT"

list_kv_names() {
  local TMP
  TMP="$(mktemp)"

  # Capture Wrangler output to a file first. Do not pipe into python with a heredoc,
  # because the heredoc becomes python's stdin and hides the Wrangler output.
  npx wrangler kv key list --namespace-id "$KV_ID" --remote > "$TMP" 2>&1 || true

  python3 - "$TMP" <<'PY2'
import re, sys

path = sys.argv[1]
raw = open(path, "r", encoding="utf-8", errors="ignore").read()

# Primary parser for Wrangler JSON output.
names = re.findall(r'"name"\s*:\s*"([^"]+)"', raw)

# Fallback parser if Wrangler output format changes.
if not names:
    names = re.findall(r'((?:license|client-state)::[A-Za-z0-9_.:-]+)', raw)

for name in sorted(set(names)):
    print(name)
PY2

  rm -f "$TMP"
}


if [ "$CLIENT_ID" = "all" ]; then
  TMP_LICENSES="$(mktemp)"
  npx wrangler kv key list --namespace-id "$KV_ID" --remote --prefix "license::" > "$TMP_LICENSES" 2>&1 || true

  CLIENTS="$(python3 - "$TMP_LICENSES" <<'PY2'
import re, sys
raw = open(sys.argv[1], "r", encoding="utf-8", errors="ignore").read()
names = re.findall(r'"name"\s*:\s*"license::([^"]+)"', raw)
for name in sorted(set(names)):
    print(name)
PY2
)"
  rm -f "$TMP_LICENSES"
else
  CLIENTS="$CLIENT_ID"
fi

if [ -z "${CLIENTS:-}" ]; then
  echo "No clients found." | tee -a "$OUT"
else
  echo "$CLIENTS" | sed 's/^/- /' | tee -a "$OUT"
fi

for C in $CLIENTS; do
  echo "" | tee -a "$OUT"
  echo "===== CLIENT: $C =====" | tee -a "$OUT"

  echo "--- License ---" | tee -a "$OUT"
  npx wrangler kv key get "license::$C" --namespace-id "$KV_ID" --remote 2>/dev/null \
    | python3 -m json.tool 2>/dev/null \
    | tee -a "$OUT" || echo "No readable license record." | tee -a "$OUT"

  echo "--- State Summary ---" | tee -a "$OUT"
  TMP="$(mktemp)"
  npx wrangler kv key get "client-state::$C::current" --namespace-id "$KV_ID" --remote > "$TMP" 2>/dev/null || true

  python3 - "$TMP" <<'PY' | tee -a "$OUT"
import json, sys
path = sys.argv[1]
raw = open(path, "r", encoding="utf-8", errors="ignore").read().strip()
if not raw or raw == "null":
    print("No client state found.")
    sys.exit(0)

try:
    data = json.loads(raw)
except Exception as e:
    print("Could not parse state JSON:", e)
    sys.exit(0)

players = data.get("players") or []
schedule = data.get("schedule") or []
matches = 0
complete = 0

for rnd in schedule:
    if isinstance(rnd, list):
        for m in rnd:
            if isinstance(m, dict):
                matches += 1
                if m.get("complete") or m.get("completed") or str(m.get("scoreA","")).strip() or str(m.get("scoreB","")).strip():
                    complete += 1

sms = ((data.get("riverState") or {}).get("smsSettingsV39L") or {})

print("Players:", len(players))
print("Rounds:", len(schedule))
print("Matches:", matches)
print("Completed/scored matches:", complete)
print("SMS settings saved:", "yes" if sms else "no")
print("Saved at:", data.get("savedAt") or data.get("updatedAt") or "unknown")
PY

  rm -f "$TMP"
done

echo "" | tee -a "$OUT"
echo "GREEN: V39R client health report complete." | tee -a "$OUT"
echo "Report: $OUT" | tee -a "$OUT"
