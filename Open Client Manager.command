#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

clear || true

echo "Opening PickleBall Pro Client Manager..."
echo ""

./ops/client-manager/client-manager-v37g.sh
