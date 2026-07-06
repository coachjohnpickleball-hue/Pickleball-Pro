#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

if [[ "$ENVIRONMENT" == "staging" ]]; then
  KV="$STAGING_KV"
elif [[ "$ENVIRONMENT" == "production" ]]; then
  KV="$PROD_KV"
else
  echo "Usage:"
  echo "  ./ops/client-manager/backup-clients-v37x.sh staging"
  echo "  ./ops/client-manager/backup-clients-v37x.sh production"
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="ops/client-manager/backups/${ENVIRONMENT}-${STAMP}"
mkdir -p "$OUT_DIR/licenses" "$OUT_DIR/states" "$OUT_DIR/tombstones" "$OUT_DIR/raw"

echo "------ CLIENT BACKUP / EXPORT V37X: $ENVIRONMENT ------"
echo ""
echo "Output folder:"
echo "$OUT_DIR"
echo ""

npx wrangler kv key list --namespace-id "$KV" --prefix "client-license:" --remote > "$OUT_DIR/raw/client-license-keys.json"
npx wrangler kv key list --namespace-id "$KV" --prefix "client-state::" --remote > "$OUT_DIR/raw/client-state-keys.json"
npx wrangler kv key list --namespace-id "$KV" --prefix "client-deleted:" --remote > "$OUT_DIR/raw/client-deleted-keys.json"

python3 - "$OUT_DIR" "$KV" "$ENVIRONMENT" <<'PYBACKUP'
import json, sys, subprocess, re
from pathlib import Path
from datetime import datetime, timezone

out_dir = Path(sys.argv[1])
kv = sys.argv[2]
environment = sys.argv[3]

def load_keys(path):
    try:
        data = json.load(open(path))
        return [x.get("name", "") for x in data if isinstance(x, dict) and x.get("name")]
    except Exception:
        return []

def safe_name(key):
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", key)
    return name[:180] + ".json"

def kv_get(key):
    try:
        out = subprocess.check_output(
            ["npx", "wrangler", "kv", "key", "get", key, "--namespace-id", kv, "--remote"],
            text=True,
            stderr=subprocess.DEVNULL
        )
        return out
    except Exception as e:
        return ""

license_keys = load_keys(out_dir / "raw" / "client-license-keys.json")
state_keys = load_keys(out_dir / "raw" / "client-state-keys.json")
tombstone_keys = load_keys(out_dir / "raw" / "client-deleted-keys.json")

manifest = {
    "marker": "PB_CLIENT_BACKUP_EXPORT_V37X",
    "environment": environment,
    "createdAt": datetime.now(timezone.utc).isoformat(),
    "counts": {
        "licenseKeys": len(license_keys),
        "stateKeys": len(state_keys),
        "tombstoneKeys": len(tombstone_keys)
    },
    "files": []
}

for key in license_keys:
    data = kv_get(key)
    path = out_dir / "licenses" / safe_name(key)
    path.write_text(data)
    manifest["files"].append({"type": "license", "key": key, "file": str(path)})

for key in state_keys:
    data = kv_get(key)
    path = out_dir / "states" / safe_name(key)
    path.write_text(data)
    manifest["files"].append({"type": "state", "key": key, "file": str(path)})

for key in tombstone_keys:
    data = kv_get(key)
    path = out_dir / "tombstones" / safe_name(key)
    path.write_text(data)
    manifest["files"].append({"type": "tombstone", "key": key, "file": str(path)})

(out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))

summary = []
summary.append(f"CLIENT BACKUP / EXPORT V37X")
summary.append(f"Environment: {environment}")
summary.append(f"Created: {manifest['createdAt']}")
summary.append("")
summary.append(f"License keys:   {len(license_keys)}")
summary.append(f"State keys:     {len(state_keys)}")
summary.append(f"Tombstone keys: {len(tombstone_keys)}")
summary.append("")
summary.append("License clients:")
for key in license_keys:
    summary.append(f"- {key.replace('client-license:', '', 1)}")
summary.append("")
summary.append("State clients:")
for key in state_keys:
    client = key.replace("client-state::", "", 1).replace("::current", "", 1)
    summary.append(f"- {client}")
summary.append("")
summary.append("Tombstoned clients:")
for key in tombstone_keys:
    summary.append(f"- {key.replace('client-deleted:', '', 1)}")

(out_dir / "summary.txt").write_text("\n".join(summary) + "\n")

print("")
print("Backup summary:")
print("----------------")
print("\n".join(summary))
PYBACKUP

echo ""
echo "GREEN: $ENVIRONMENT client backup complete."
echo "Backup folder:"
echo "$OUT_DIR"
