#!/usr/bin/env bash
set -euo pipefail

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

STAGING_URL="https://rally-staging.coachjohnpickleball.workers.dev"
PROD_URL="https://rally.coachjohnpickleball.workers.dev"

ENVIRONMENT="${1:-}"
CLIENT="${2:-}"

if [ -z "$ENVIRONMENT" ]; then
  read -r -p "Environment, staging or production: " ENVIRONMENT
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

if [ -z "$CLIENT" ]; then
  read -r -p "Client ID to inspect: " CLIENT
fi

CLIENT="$(echo "$CLIENT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/-+/-/g; s/^-|-$//g')"

if [ -z "$CLIENT" ]; then
  echo "ERROR: No valid client ID."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
LICENSE_FILE="$TMP_DIR/license.json"
STATE_FILE="$TMP_DIR/state.json"
TOMBSTONE_FILE="$TMP_DIR/tombstone.json"

LICENSE_EXISTS="no"
STATE_EXISTS="no"
TOMBSTONE_EXISTS="no"

if npx wrangler kv key get "client-license:$CLIENT" --namespace-id "$KV" --remote > "$LICENSE_FILE" 2>/dev/null; then
  LICENSE_EXISTS="yes"
else
  echo "{}" > "$LICENSE_FILE"
fi

if npx wrangler kv key get "client-state::$CLIENT::current" --namespace-id "$KV" --remote > "$STATE_FILE" 2>/dev/null; then
  STATE_EXISTS="yes"
else
  echo "{}" > "$STATE_FILE"
fi

if npx wrangler kv key get "client-deleted:$CLIENT" --namespace-id "$KV" --remote > "$TOMBSTONE_FILE" 2>/dev/null; then
  TOMBSTONE_EXISTS="yes"
else
  echo "{}" > "$TOMBSTONE_FILE"
fi

echo "------ READ-ONLY CLIENT INSPECT - $LABEL ------"
echo "Client: $CLIENT"
echo ""

python3 - "$CLIENT" "$BASE_URL" "$LICENSE_FILE" "$STATE_FILE" "$TOMBSTONE_FILE" "$LICENSE_EXISTS" "$STATE_EXISTS" "$TOMBSTONE_EXISTS" <<'PY'
import json, sys

client, base_url, license_path, state_path, tombstone_path, license_exists, state_exists, tombstone_exists = sys.argv[1:9]

def load(path):
    try:
        return json.load(open(path))
    except Exception:
        return {}

license_data = load(license_path)
state_data = load(state_path)
tombstone_data = load(tombstone_path)

def first_list_count(obj, keys):
    for key in keys:
        val = obj.get(key)
        if isinstance(val, list):
            return len(val)
    return 0

players = first_list_count(state_data, ["players", "activePlayers"])
matches = first_list_count(state_data, ["matches", "schedule"])
rounds = first_list_count(state_data, ["rounds"])

saved_at = (
    state_data.get("savedAt")
    or state_data.get("updatedAt")
    or state_data.get("lastSavedAt")
    or ""
)

license_name = license_data.get("clientName") or license_data.get("name") or client
license_status = license_data.get("licenseStatus") or license_data.get("status") or ""
license_level = license_data.get("licenseLevel") or license_data.get("level") or ""

flags = []
if license_exists == "no":
    flags.append("NO_LICENSE")
if state_exists == "no":
    flags.append("NO_STATE")
if tombstone_exists == "yes":
    flags.append("HAS_TOMBSTONE")
if client == "client":
    flags.append("GENERIC_CLIENT_ID")
if any(word in client for word in ["test", "stage", "staging", "original"]):
    flags.append("POSSIBLE_TEST_OR_STAGING")

print(f"Private link: {base_url}/?clientId={client}")
print("")
print("License exists:   ", license_exists)
print("State exists:     ", state_exists)
print("Tombstone exists: ", tombstone_exists)
print("")
print("License name:     ", license_name)
print("License status:   ", license_status)
print("License level:    ", license_level)
print("")
print("State players:    ", players)
print("State matches:    ", matches)
print("State rounds:     ", rounds)
print("State savedAt:    ", saved_at or "-")
print("")
print("Flags:            ", ", ".join(flags) if flags else "OK")
print("")
print("Raw files saved in temporary folder for this inspection.")
PY

echo ""
echo "Temporary files:"
echo "$TMP_DIR"
echo ""
echo "GREEN: Inspect complete. No changes made."
