#!/usr/bin/env bash
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "------ PREFLIGHT ------"
cd "$PROJECT"
./scripts/preflight.sh

echo "------ DEPLOY MAIN APP TO PRODUCTION: rally ------"
cd "$PROJECT/worker"
pwd
npx wrangler deploy --env rally

echo "------ DEPLOY MOBILE WORKER TO PRODUCTION ------"
cd "$PROJECT/mobile-sync-worker"
pwd
npx wrangler deploy --name pickleball-mobile-sync-v2

echo "------ PRODUCTION DEPLOY COMPLETE ------"
cd "$PROJECT"
git status --short
