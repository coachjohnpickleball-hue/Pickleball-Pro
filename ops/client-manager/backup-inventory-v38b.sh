#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="ops/client-manager/backups"

echo "=============================================="
echo " PickleBall Pro Backup Inventory V38B"
echo "=============================================="
echo ""
echo "Read-only. No backup files are changed."
echo ""

if [[ ! -d "$BASE_DIR" ]]; then
  echo "No backup folder found:"
  echo "$BASE_DIR"
  exit 0
fi

python3 - "$BASE_DIR" <<'PYINV'
import json, sys
from pathlib import Path

base = Path(sys.argv[1])
folders = sorted([p for p in base.iterdir() if p.is_dir()], reverse=True)

if not folders:
    print("No backups found.")
    raise SystemExit

rows = []

for folder in folders:
    manifest = folder / "manifest.json"
    summary = folder / "summary.txt"

    env = "unknown"
    created = folder.name
    license_count = len(list((folder / "licenses").glob("*.json"))) if (folder / "licenses").exists() else 0
    state_count = len(list((folder / "states").glob("*.json"))) if (folder / "states").exists() else 0
    tombstone_count = len(list((folder / "tombstones").glob("*.json"))) if (folder / "tombstones").exists() else 0

    if folder.name.startswith("production-"):
        env = "production"
        created = folder.name.replace("production-", "", 1)
    elif folder.name.startswith("staging-"):
        env = "staging"
        created = folder.name.replace("staging-", "", 1)

    if manifest.exists():
        try:
            data = json.load(open(manifest))
            env = data.get("environment", env)
            created = data.get("createdAt", created)
            counts = data.get("counts", {})
            license_count = counts.get("licenseKeys", license_count)
            state_count = counts.get("stateKeys", state_count)
            tombstone_count = counts.get("tombstoneKeys", tombstone_count)
        except Exception:
            pass

    rows.append({
        "folder": str(folder),
        "env": env,
        "created": created,
        "licenses": license_count,
        "states": state_count,
        "tombstones": tombstone_count,
        "hasSummary": summary.exists()
    })

print(f"{'ENV':12} {'LICENSES':>8} {'STATES':>8} {'TOMBS':>8} CREATED / FOLDER")
print("-" * 110)

for r in rows:
    print(f"{r['env'][:12]:12} {r['licenses']:8} {r['states']:8} {r['tombstones']:8} {r['created']}  {r['folder']}")

print("")
print("SUMMARY")
print("-------")
print("Total backups:", len(rows))
print("Production backups:", sum(1 for r in rows if r["env"] == "production"))
print("Staging backups:", sum(1 for r in rows if r["env"] == "staging"))

latest_prod = next((r for r in rows if r["env"] == "production"), None)
latest_staging = next((r for r in rows if r["env"] == "staging"), None)

print("")
print("LATEST")
print("------")
print("Production:", latest_prod["folder"] if latest_prod else "(none)")
print("Staging:", latest_staging["folder"] if latest_staging else "(none)")
PYINV

echo ""
echo "GREEN: Backup inventory complete."
