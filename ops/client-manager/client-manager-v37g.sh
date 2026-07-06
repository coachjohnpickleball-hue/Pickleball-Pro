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
  echo "  7)  Renewal / expiry audit STAGING"
  echo "  8)  Renewal / expiry audit PRODUCTION"
  echo "  9)  Billing summary export STAGING"
  echo " 10)  Billing summary export PRODUCTION"
  echo " 11)  Billing follow-up report STAGING"
  echo " 12)  Billing follow-up report PRODUCTION"
  echo " 13)  Inspect STAGING client"
  echo " 14)  Inspect PRODUCTION client"
  echo ""
  echo "Staging operations"
  echo " 15)  Create STAGING client"
  echo " 16)  Delete STAGING client"
  echo " 17)  Update STAGING license"
  echo " 18)  Suspend / Reactivate STAGING client"
  echo " 19)  Set STAGING renewal / expiry date"
  echo " 20)  Set STAGING billing contact"
  echo ""
  echo "Production operations"
  echo " 21)  Create PRODUCTION client"
  echo " 22)  Delete PRODUCTION client"
  echo " 23)  Update PRODUCTION license"
  echo " 24)  Suspend / Reactivate PRODUCTION client"
  echo " 25)  Set PRODUCTION renewal / expiry date"
  echo " 26)  Set PRODUCTION billing contact"
  echo ""
  echo "Backups"
  echo " 27)  Backup STAGING clients"
  echo " 28)  Backup PRODUCTION clients"
  echo " 29)  Backup inventory"
  echo " 30)  Restore STAGING client from backup"
  echo " 31)  Restore PRODUCTION client from backup"
  echo ""
  echo "Other"
  echo " 32)  Health Check ALL"
  echo " 33)  Show installed tools"
  echo " 34)  Quit"
  echo ""

  read -r -p "Choose an option: " choice

  case "$choice" in
    1)  run_tool "list-clients-v37f.sh" staging ;;
    2)  run_tool "list-clients-v37f.sh" production ;;
    3)  run_tool "audit-clients-v37i.sh" staging ;;
    4)  run_tool "audit-clients-v37i.sh" production ;;
    5)  run_tool "license-usage-audit-v37q.sh" staging ;;
    6)  run_tool "license-usage-audit-v37q.sh" production ;;
    7)  run_tool "renewal-expiry-audit-v38i.sh" staging ;;
    8)  run_tool "renewal-expiry-audit-v38i.sh" production ;;
    9)  run_tool "billing-summary-export-v38l.sh" staging ;;
    10) run_tool "billing-summary-export-v38l.sh" production ;;
    11) run_tool "billing-followup-report-v38o.sh" staging ;;
    12) run_tool "billing-followup-report-v38o.sh" production ;;
    13) run_tool "inspect-client-v37j.sh" staging ;;
    14) run_tool "inspect-client-v37j.sh" production ;;
    15) run_tool "create-staging-client-v37e.sh" ;;
    16) run_tool "delete-staging-client-v37d3.sh" ;;
    17) run_tool "update-staging-license-v37m.sh" ;;
    18) run_tool "update-staging-status-v38c.sh" ;;
    19) run_tool "update-staging-renewal-v38j.sh" ;;
    20) run_tool "update-staging-billing-contact-v38m.sh" ;;
    21) run_tool "create-production-client-v37e.sh" ;;
    22) run_tool "delete-production-client-v37d3.sh" ;;
    23) run_tool "update-production-license-v37m.sh" ;;
    24) run_tool "update-production-status-v38c.sh" ;;
    25) run_tool "update-production-renewal-v38j.sh" ;;
    26) run_tool "update-production-billing-contact-v38m.sh" ;;
    27) run_tool "backup-clients-v37x.sh" staging ;;
    28) run_tool "backup-clients-v37x.sh" production ;;
    29) run_tool "backup-inventory-v38b.sh" ;;
    30) run_tool "restore-client-menu-v38a.sh" staging ;;
    31) run_tool "restore-client-menu-v38a.sh" production ;;
    32) run_tool "health-check-all-v37w.sh" ;;
    33)
      echo ""
      echo "Installed client-manager tools:"
      echo "----------------------------------------"
      ls -1 "$TOOL_DIR"
      pause_menu
      ;;
    34|q|Q|quit|exit)
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
