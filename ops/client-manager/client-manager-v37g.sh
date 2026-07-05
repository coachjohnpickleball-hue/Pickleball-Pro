#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_tool() {
  local tool="$1"
  local arg="${2:-}"

  if [ ! -f "$SCRIPT_DIR/$tool" ]; then
    echo ""
    echo "ERROR: Missing tool:"
    echo "$SCRIPT_DIR/$tool"
    echo ""
    echo "Run ls -l ops/client-manager to check installed tools."
    exit 1
  fi

  if [ -n "$arg" ]; then
    "$SCRIPT_DIR/$tool" "$arg"
  else
    "$SCRIPT_DIR/$tool"
  fi
}

while true; do
  clear || true

  echo "=============================================="
  echo " PickleBall Pro Client Manager V37G"
  echo "=============================================="
  echo ""
  echo "Safe operations:"
  echo "  1) List STAGING clients"
  echo "  2) List PRODUCTION clients"
  echo "  3) Create STAGING client"
  echo "  4) Delete STAGING client"
  echo ""
  echo "Production operations:"
  echo "  5) Create PRODUCTION client"
  echo "  6) Delete PRODUCTION client"
  echo ""
  echo "Other:"
  echo "  7) Show installed tools"
  echo "  8) Quit"
  echo ""
  read -r -p "Choose option: " CHOICE

  case "$CHOICE" in
    1)
      echo ""
      run_tool "list-clients-v37f.sh" "staging"
      ;;
    2)
      echo ""
      run_tool "list-clients-v37f.sh" "production"
      ;;
    3)
      echo ""
      run_tool "create-staging-client-v37e.sh"
      ;;
    4)
      echo ""
      run_tool "delete-staging-client-v37d3.sh"
      ;;
    5)
      echo ""
      echo "WARNING: This creates a live PRODUCTION client."
      echo "The create tool will ask for exact confirmation."
      echo ""
      read -r -p "Continue? Type YES: " CONFIRM
      if [ "$CONFIRM" = "YES" ]; then
        run_tool "create-production-client-v37e.sh"
      else
        echo "Cancelled."
      fi
      ;;
    6)
      echo ""
      echo "WARNING: This deletes a PRODUCTION client and writes a tombstone."
      echo "The delete tool will ask for exact confirmation."
      echo ""
      read -r -p "Continue? Type YES: " CONFIRM
      if [ "$CONFIRM" = "YES" ]; then
        run_tool "delete-production-client-v37d3.sh"
      else
        echo "Cancelled."
      fi
      ;;
    7)
      echo ""
      echo "Installed client manager tools:"
      ls -l "$SCRIPT_DIR"
      ;;
    8|q|Q|quit|exit)
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
