#!/usr/bin/env bash
set -euo pipefail

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

ENVIRONMENT="${1:-production}"

case "$ENVIRONMENT" in
  staging)
    KV="$STAGING_KV"
    LABEL="STAGING"
    ;;
  production|prod|rally)
    KV="$PROD_KV"
    LABEL="PRODUCTION"
    ;;
  *)
    echo "ERROR: Use staging or production."
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
LICENSE_KEYS="$TMP_DIR/license-keys.json"
STATE_KEYS="$TMP_DIR/state-keys.json"
TOMBSTONE_KEYS="$TMP_DIR/tombstone-keys.json"

echo "------ READ-ONLY CLIENT AUDIT - $LABEL ------"
echo ""

npx wrangler kv key list --prefix "client-license:" --namespace-id "$KV" --remote > "$LICENSE_KEYS"
npx wrangler kv key list --prefix "client-state::" --namespace-id "$KV" --remote > "$STATE_KEYS"
npx wrangler kv key list --prefix "client-deleted:" --namespace-id "$KV" --remote > "$TOMBSTONE_KEYS"

python3 - "$LICENSE_KEYS" "$STATE_KEYS" "$TOMBSTONE_KEYS" <<'PY'
import json, sys, re

license_path, state_path, tombstone_path = sys.argv[1:4]

def load_names(path):
    try:
        data = json.load(open(path))
    except Exception:
        return []
    out = []
    for item in data:
        if isinstance(item, dict) and item.get("name"):
            out.append(item["name"])
    return out

license_keys = load_names(license_path)
state_keys = load_names(state_path)
tombstone_keys = load_names(tombstone_path)

license_clients = sorted(k.replace("client-license:", "", 1) for k in license_keys)
state_clients = sorted(
    k.replace("client-state::", "", 1).replace("::current", "")
    for k in state_keys
    if k.startswith("client-state::") and k.endswith("::current")
)
tombstone_clients = sorted(k.replace("client-deleted:", "", 1) for k in tombstone_keys)

license_set = set(license_clients)
state_set = set(state_clients)
tombstone_set = set(tombstone_clients)

print("License clients:", len(license_clients))
print("State clients:  ", len(state_clients))
print("Tombstones:     ", len(tombstone_clients))
print("")

suspect_words = [
    "test",
    "stage",
    "staging",
    "original",
    "default",
]

print("------ ACTIVE LICENSE CLIENTS ------")
for client in license_clients:
    flags = []

    if client in tombstone_set:
        flags.append("HAS_TOMBSTONE")
    if client not in state_set:
        flags.append("NO_STATE_YET")
    if client == "client":
        flags.append("GENERIC_CLIENT_ID")
    if any(word in client for word in suspect_words):
        flags.append("POSSIBLE_TEST_OR_STAGING")

    label = ", ".join(flags) if flags else "OK"
    print(f"{client:<55} {label}")

print("")
print("------ ORPHAN STATE WITHOUT LICENSE ------")
orphans = sorted(state_set - license_set)
if not orphans:
    print("None")
else:
    for client in orphans:
        print(client)

print("")
print("------ TOMBSTONES ------")
if not tombstone_clients:
    print("None")
else:
    for client in tombstone_clients:
        extra = []
        if client in license_set:
            extra.append("LICENSE_STILL_EXISTS")
        if client in state_set:
            extra.append("STATE_STILL_EXISTS")
        label = ", ".join(extra) if extra else "OK"
        print(f"{client:<55} {label}")

print("")
print("READ-ONLY AUDIT COMPLETE.")
PY

echo ""
echo "GREEN: Audit complete. No changes made."
