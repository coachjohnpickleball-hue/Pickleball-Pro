#!/usr/bin/env bash
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "------ PREFLIGHT ------"
cd "$PROJECT"
./scripts/preflight.sh

echo "------ DEPLOY MAIN APP TO STAGING: rally-staging ------"
cd "$PROJECT/worker"
pwd
npx wrangler deploy --env staging

echo "------ DEPLOY MOBILE WORKER TO STAGING ------"
cd "$PROJECT/mobile-sync-worker"
pwd
npx wrangler deploy --name pickleball-mobile-sync-v2-staging

echo "------ STAGING DEPLOY COMPLETE ------"
cd "$PROJECT"
git status --short
