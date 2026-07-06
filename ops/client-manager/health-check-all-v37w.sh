#!/usr/bin/env bash
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TOOL_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

echo "=============================================="
echo " PickleBall Pro Health Check ALL V37W"
echo "=============================================="
echo ""
echo "Read-only checks only. No clients, licenses, or states are changed."
echo ""

run_section() {
  local title="$1"
  shift

  echo ""
  echo "----------------------------------------------"
  echo "$title"
  echo "----------------------------------------------"

  "$@"
}

run_section "1) PRODUCTION client list" \
  "$TOOL_DIR/list-clients-v37f.sh" production

run_section "2) PRODUCTION client audit" \
  "$TOOL_DIR/audit-clients-v37i.sh" production

run_section "3) PRODUCTION license usage audit" \
  "$TOOL_DIR/license-usage-audit-v37q.sh" production

run_section "4) STAGING client list" \
  "$TOOL_DIR/list-clients-v37f.sh" staging

run_section "5) STAGING client audit" \
  "$TOOL_DIR/audit-clients-v37i.sh" staging

run_section "6) STAGING license usage audit" \
  "$TOOL_DIR/license-usage-audit-v37q.sh" staging

echo ""
echo "=============================================="
echo "GREEN: Health Check ALL complete."
echo "=============================================="
