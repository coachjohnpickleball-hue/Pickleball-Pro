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
  echo " 13)  Billing email drafts STAGING"
  echo " 14)  Billing email drafts PRODUCTION"
  echo " 15)  Inspect STAGING client"
  echo " 16)  Inspect PRODUCTION client"
  echo ""
  echo "Staging operations"
  echo " 17)  Create STAGING client"
  echo " 18)  Delete STAGING client"
  echo " 19)  Update STAGING license"
  echo " 20)  Suspend / Reactivate STAGING client"
  echo " 21)  Set STAGING renewal / expiry date"
  echo " 22)  Set STAGING billing contact"
  echo ""
  echo "Production operations"
  echo " 23)  Create PRODUCTION client"
  echo " 24)  Delete PRODUCTION client"
  echo " 25)  Update PRODUCTION license"
  echo " 26)  Suspend / Reactivate PRODUCTION client"
  echo " 27)  Set PRODUCTION renewal / expiry date"
  echo " 28)  Set PRODUCTION billing contact"
  echo ""
  echo "Backups"
  echo " 29)  Backup STAGING clients"
  echo " 30)  Backup PRODUCTION clients"
  echo " 31)  Backup inventory"
  echo " 32)  Restore STAGING client from backup"
  echo " 33)  Restore PRODUCTION client from backup"
  echo ""
  echo "Other"
  echo " 34)  Health Check ALL"
  echo " 35)  Show installed tools"
  echo " 36)  Quit"
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
    13) run_tool "billing-email-drafts-v38p.sh" staging ;;
    14) run_tool "billing-email-drafts-v38p.sh" production ;;
    15) run_tool "inspect-client-v37j.sh" staging ;;
    16) run_tool "inspect-client-v37j.sh" production ;;
    17) run_tool "create-staging-client-v37e.sh" ;;
    18) run_tool "delete-staging-client-v37d3.sh" ;;
    19) run_tool "update-staging-license-v37m.sh" ;;
    20) run_tool "update-staging-status-v38c.sh" ;;
    21) run_tool "update-staging-renewal-v38j.sh" ;;
    22) run_tool "update-staging-billing-contact-v38m.sh" ;;
    23) run_tool "create-production-client-v37e.sh" ;;
    24) run_tool "delete-production-client-v37d3.sh" ;;
    25) run_tool "update-production-license-v37m.sh" ;;
    26) run_tool "update-production-status-v38c.sh" ;;
    27) run_tool "update-production-renewal-v38j.sh" ;;
    28) run_tool "update-production-billing-contact-v38m.sh" ;;
    29) run_tool "backup-clients-v37x.sh" staging ;;
    30) run_tool "backup-clients-v37x.sh" production ;;
    31) run_tool "backup-inventory-v38b.sh" ;;
    32) run_tool "restore-client-menu-v38a.sh" staging ;;
    33) run_tool "restore-client-menu-v38a.sh" production ;;
    34) run_tool "health-check-all-v37w.sh" ;;
    35)
      echo ""
      echo "Installed client-manager tools:"
      echo "----------------------------------------"
      ls -1 "$TOOL_DIR"
      pause_menu
      ;;
    36|q|Q|quit|exit)
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
