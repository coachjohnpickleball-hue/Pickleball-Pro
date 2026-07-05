#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_tool() {
  local tool="$1"
  local arg1="${2:-}"
  local arg2="${3:-}"

  if [ ! -f "$SCRIPT_DIR/$tool" ]; then
    echo ""
    echo "ERROR: Missing tool:"
    echo "$SCRIPT_DIR/$tool"
    exit 1
  fi

  if [ -n "$arg2" ]; then
    "$SCRIPT_DIR/$tool" "$arg1" "$arg2"
  elif [ -n "$arg1" ]; then
    "$SCRIPT_DIR/$tool" "$arg1"
  else
    "$SCRIPT_DIR/$tool"
  fi
}

while true; do
  clear || true

  echo "=============================================="
  echo " PickleBall Pro Client Manager V37N"
  echo "=============================================="
  echo ""
  echo "Read-only:"
  echo "  1) List STAGING clients"
  echo "  2) List PRODUCTION clients"
  echo "  3) Audit STAGING clients"
  echo "  4) Audit PRODUCTION clients"
  echo "  5) Inspect STAGING client"
  echo "  6) Inspect PRODUCTION client"
  echo ""
  echo "Staging operations:"
  echo "  7) Create STAGING client"
  echo "  8) Delete STAGING client"
  echo "  9) Update STAGING license"
  echo ""
  echo "Production operations:"
  echo " 10) Create PRODUCTION client"
  echo " 11) Delete PRODUCTION client"
  echo " 12) Update PRODUCTION license"
  echo ""
  echo "Other:"
  echo " 13) Show installed tools"
  echo " 14) Quit"
  echo ""
  read -r -p "Choose option: " CHOICE

  case "$CHOICE" in
    1)
      run_tool "list-clients-v37f.sh" "staging"
      ;;
    2)
      run_tool "list-clients-v37f.sh" "production"
      ;;
    3)
      run_tool "audit-clients-v37i.sh" "staging"
      ;;
    4)
      run_tool "audit-clients-v37i.sh" "production"
      ;;
    5)
      read -r -p "STAGING clientId to inspect: " CLIENT_ID
      run_tool "inspect-client-v37j.sh" "staging" "$CLIENT_ID"
      ;;
    6)
      read -r -p "PRODUCTION clientId to inspect: " CLIENT_ID
      run_tool "inspect-client-v37j.sh" "production" "$CLIENT_ID"
      ;;
    7)
      run_tool "create-staging-client-v37e.sh"
      ;;
    8)
      run_tool "delete-staging-client-v37d3.sh"
      ;;
    9)
      run_tool "update-staging-license-v37m.sh"
      ;;
    10)
      echo ""
      echo "WARNING: This creates a live PRODUCTION client."
      read -r -p "Continue? Type YES: " CONFIRM
      if [ "$CONFIRM" = "YES" ]; then
        run_tool "create-production-client-v37e.sh"
      else
        echo "Cancelled."
      fi
      ;;
    11)
      echo ""
      echo "WARNING: This deletes a PRODUCTION client and writes a tombstone."
      read -r -p "Continue? Type YES: " CONFIRM
      if [ "$CONFIRM" = "YES" ]; then
        run_tool "delete-production-client-v37d3.sh"
      else
        echo "Cancelled."
      fi
      ;;
    12)
      echo ""
      echo "WARNING: This updates a live PRODUCTION client license."
      read -r -p "Continue? Type YES: " CONFIRM
      if [ "$CONFIRM" = "YES" ]; then
        run_tool "update-production-license-v37m.sh"
      else
        echo "Cancelled."
      fi
      ;;
    13)
      echo ""
      echo "Installed client manager tools:"
      ls -l "$SCRIPT_DIR"
      ;;
    14|q|Q|quit|exit)
      echo "Done."
      exit 0
      ;;
    *)
      echo ""
      echo "Invalid choice."
      ;;
  esac

  echo ""
  read -r -p "Press Enter to return to menu..."
done
