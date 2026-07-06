#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  echo "Usage:"
  echo "  ./ops/client-manager/restore-client-menu-v38a.sh staging"
  echo "  ./ops/client-manager/restore-client-menu-v38a.sh production"
  exit 1
fi

echo "------ RESTORE CLIENT FROM BACKUP MENU V38A: $ENVIRONMENT ------"
echo ""
echo "Available backups:"
ls -1dt "ops/client-manager/backups/${ENVIRONMENT}-"* 2>/dev/null || true

LATEST_BACKUP="$(ls -1dt "ops/client-manager/backups/${ENVIRONMENT}-"* 2>/dev/null | head -1 || true)"

echo ""
if [[ -n "$LATEST_BACKUP" ]]; then
  echo "Latest backup:"
  echo "$LATEST_BACKUP"
fi

echo ""
read -r -p "Backup folder [press Enter for latest]: " BACKUP_DIR

if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$LATEST_BACKUP"
fi

if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
  echo "ERROR: backup folder not found."
  exit 1
fi

echo ""
echo "Clients in backup:"
if [[ -f "$BACKUP_DIR/summary.txt" ]]; then
  awk '
    /^License clients:/ {show=1; next}
    /^State clients:/ {show=0}
    show && /^-/ {print}
  ' "$BACKUP_DIR/summary.txt" || true
else
  ls -1 "$BACKUP_DIR/licenses" 2>/dev/null | sed 's/^/- /' || true
fi

echo ""
read -r -p "Client ID to restore: " CLIENT_ID

if [[ -z "$CLIENT_ID" ]]; then
  echo "Cancelled: no client ID entered."
  exit 1
fi

echo ""
echo "Restore mode:"
echo "  1) license-state"
echo "  2) state only"
echo "  3) license only"
echo ""
read -r -p "Choose mode [1]: " MODE_CHOICE

case "$MODE_CHOICE" in
  ""|1) MODE="license-state" ;;
  2) MODE="state" ;;
  3) MODE="license" ;;
  *)
    echo "Invalid mode."
    exit 1
    ;;
esac

echo ""
echo "You selected:"
echo "Environment: $ENVIRONMENT"
echo "Backup:      $BACKUP_DIR"
echo "Client:      $CLIENT_ID"
echo "Mode:        $MODE"
echo ""

./ops/client-manager/restore-client-from-backup-v37z.sh "$ENVIRONMENT" "$BACKUP_DIR" "$CLIENT_ID" "$MODE"
