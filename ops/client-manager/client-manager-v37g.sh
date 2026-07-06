#!/usr/bin/env bash
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TOOL_DIR/../.." && pwd)"

cd "$PROJECT_DIR"

pause_menu() {
  echo ""
  read -r -p "Press Enter to return to Client Manager..." _
}

run_tool() {
  local tool="$1"
  shift || true

  if [[ ! -x "$TOOL_DIR/$tool" ]]; then
    echo ""
    echo "ERROR: Tool not found or not executable:"
    echo "$TOOL_DIR/$tool"
    pause_menu
    return
  fi

  echo ""
  echo "Running: $tool $*"
  echo "----------------------------------------"
  "$TOOL_DIR/$tool" "$@"
  pause_menu
}

while true; do
  clear || true

  echo "=============================================="
  echo " PickleBall Pro Client Manager"
  echo "=============================================="
  echo ""
  echo "Read-only"
  echo "  1)  List STAGING clients"
  echo "  2)  List PRODUCTION clients"
  echo "  3)  Audit STAGING clients"
  echo "  4)  Audit PRODUCTION clients"
  echo "  5)  License usage audit STAGING"
  echo "  6)  License usage audit PRODUCTION"
  echo "  7)  Inspect STAGING client"
  echo "  8)  Inspect PRODUCTION client"
  echo ""
  echo "Staging operations"
  echo "  9)  Create STAGING client"
  echo " 10)  Delete STAGING client"
  echo " 11)  Update STAGING license"
  echo " 12)  Suspend / Reactivate STAGING client"
  echo ""
  echo "Production operations"
  echo " 13)  Create PRODUCTION client"
  echo " 14)  Delete PRODUCTION client"
  echo " 15)  Update PRODUCTION license"
  echo " 16)  Suspend / Reactivate PRODUCTION client"
  echo ""
  echo "Backups"
  echo " 17)  Backup STAGING clients"
  echo " 18)  Backup PRODUCTION clients"
  echo " 19)  Backup inventory"
  echo " 20)  Restore STAGING client from backup"
  echo " 21)  Restore PRODUCTION client from backup"
  echo ""
  echo "Other"
  echo " 22)  Health Check ALL"
  echo " 23)  Show installed tools"
  echo " 24)  Quit"
  echo ""

  read -r -p "Choose an option: " choice

  case "$choice" in
    1)  run_tool "list-clients-v37f.sh" staging ;;
    2)  run_tool "list-clients-v37f.sh" production ;;
    3)  run_tool "audit-clients-v37i.sh" staging ;;
    4)  run_tool "audit-clients-v37i.sh" production ;;
    5)  run_tool "license-usage-audit-v37q.sh" staging ;;
    6)  run_tool "license-usage-audit-v37q.sh" production ;;
    7)  run_tool "inspect-client-v37j.sh" staging ;;
    8)  run_tool "inspect-client-v37j.sh" production ;;
    9)  run_tool "create-staging-client-v37e.sh" ;;
    10) run_tool "delete-staging-client-v37d3.sh" ;;
    11) run_tool "update-staging-license-v37m.sh" ;;
    12) run_tool "update-staging-status-v38c.sh" ;;
    13) run_tool "create-production-client-v37e.sh" ;;
    14) run_tool "delete-production-client-v37d3.sh" ;;
    15) run_tool "update-production-license-v37m.sh" ;;
    16) run_tool "update-production-status-v38c.sh" ;;
    17) run_tool "backup-clients-v37x.sh" staging ;;
    18) run_tool "backup-clients-v37x.sh" production ;;
    19) run_tool "backup-inventory-v38b.sh" ;;
    20) run_tool "restore-client-menu-v38a.sh" staging ;;
    21) run_tool "restore-client-menu-v38a.sh" production ;;
    22) run_tool "health-check-all-v37w.sh" ;;
    23)
      echo ""
      echo "Installed client-manager tools:"
      echo "----------------------------------------"
      ls -1 "$TOOL_DIR"
      pause_menu
      ;;
    24|q|Q|quit|exit)
      echo "Goodbye."
      exit 0
      ;;
    *)
      echo ""
      echo "Invalid option: $choice"
      pause_menu
      ;;
  esac
done
