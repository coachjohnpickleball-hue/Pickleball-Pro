#!/usr/bin/env bash
set -euo pipefail

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

STAGING_URL="https://rally-staging.coachjohnpickleball.workers.dev"
PROD_URL="https://rally.coachjohnpickleball.workers.dev"

ENVIRONMENT="${1:-}"

if [ -z "$ENVIRONMENT" ]; then
  echo "Choose environment:"
  echo "1) staging"
  echo "2) production"
  read -r -p "Selection: " CHOICE

  if [ "$CHOICE" = "1" ]; then
    ENVIRONMENT="staging"
  elif [ "$CHOICE" = "2" ]; then
    ENVIRONMENT="production"
  else
    echo "Cancelled."
    exit 0
  fi
fi

case "$ENVIRONMENT" in
  staging)
    KV="$STAGING_KV"
    BASE_URL="$STAGING_URL"
    LABEL="STAGING"
    ;;
  production|prod|rally)
    KV="$PROD_KV"
    BASE_URL="$PROD_URL"
    LABEL="PRODUCTION"
    ;;
  *)
    echo "ERROR: Use staging or production."
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
KEYS_FILE="$TMP_DIR/client-license-keys.json"
OUT_FILE="$TMP_DIR/client-links-$ENVIRONMENT.txt"

echo "------ READ-ONLY CLIENT LIST - $LABEL ------"
echo ""

npx wrangler kv key list --prefix "client-license:" --namespace-id "$KV" --remote > "$KEYS_FILE"

python3 - "$KEYS_FILE" > "$TMP_DIR/keys.txt" <<'PY'
import json, sys

path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    data = []

for item in data:
    name = item.get("name") if isinstance(item, dict) else ""
    if name:
        print(name)
PY

TOTAL=0
VISIBLE=0
HIDDEN=0

{
  echo "Environment: $LABEL"
  echo "Base URL: $BASE_URL"
  echo ""
  printf "%-34s | %-30s | %-10s | %-8s | %s\n" "CLIENT ID" "NAME" "STATUS" "LEVEL" "PRIVATE LINK"
  printf "%-34s-+-%-30s-+-%-10s-+-%-8s-+-%s\n" "----------------------------------" "------------------------------" "----------" "--------" "----------------------------------------"
} > "$OUT_FILE"

while IFS= read -r KEY; do
  [ -z "$KEY" ] && continue

  TOTAL=$((TOTAL + 1))
  CLIENT_ID="${KEY#client-license:}"

  if npx wrangler kv key get "client-deleted:$CLIENT_ID" --namespace-id "$KV" --remote >/dev/null 2>&1; then
    HIDDEN=$((HIDDEN + 1))
    continue
  fi

  LICENSE_FILE="$TMP_DIR/$CLIENT_ID.json"

  if ! npx wrangler kv key get "$KEY" --namespace-id "$KV" --remote > "$LICENSE_FILE" 2>/dev/null; then
    continue
  fi

  python3 - "$LICENSE_FILE" "$CLIENT_ID" "$BASE_URL" >> "$OUT_FILE" <<'PY'
import json, sys

path, fallback_id, base_url = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    data = json.load(open(path))
except Exception:
    data = {}

client_id = str(data.get("clientId") or fallback_id)
name = str(data.get("clientName") or client_id)
status = str(data.get("licenseStatus") or data.get("status") or "active")
level = str(data.get("licenseLevel") or data.get("level") or "club")
link = f"{base_url}/?clientId={client_id}"

print(f"{client_id[:34]:<34} | {name[:30]:<30} | {status[:10]:<10} | {level[:8]:<8} | {link}")
PY

  VISIBLE=$((VISIBLE + 1))
done < "$TMP_DIR/keys.txt"

cat "$OUT_FILE"

echo ""
echo "Total license keys: $TOTAL"
echo "Visible clients:    $VISIBLE"
echo "Hidden tombstoned:  $HIDDEN"
echo ""
echo "Links file:"
echo "$OUT_FILE"
echo ""
echo "GREEN: Read-only client list complete."
