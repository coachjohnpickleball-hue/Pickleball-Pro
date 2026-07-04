#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage:"
  echo "  bash ops/recovery/deploy-production-tag-v30b.sh <git-tag>"
  exit 1
fi

TAG="$1"
PROJECT="${PROJECT:-/Users/jmerg/Desktop/! ! Pickleball Pro/Cloudflare Hosting/Rally/ChatGPT/rally.PickleballPro/Pickelball-Pro}"
PROD_URL="${PROD_URL:-https://rally.coachjohnpickleball.workers.dev}"

cd "$PROJECT"

echo "------ Confirm tag exists ------"
git fetch --all --tags
git rev-parse "$TAG^{commit}" >/dev/null

WORKTREE="/tmp/pb-production-deploy-worktree-${TAG}-$(date +%Y%m%d-%H%M%S)"

cleanup() {
  cd "$PROJECT" >/dev/null 2>&1 || true
  git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo ""
echo "------ Create temporary worktree ------"
git worktree add --detach "$WORKTREE" "$TAG"

cd "$WORKTREE"

echo ""
echo "Deploying tag to production:"
echo "$TAG"
git log -1 --oneline --decorate

echo ""
echo "------ Safety checks ------"
if grep -R "PB_CLIENT_ADMIN_CONTROLS_V26\|pbClientAdminV26\|pb-client-admin-controls-card-v26" public/index.html worker/src/app.html worker/src/index.js 2>/dev/null; then
  echo "ERROR: Old broken V26 is present in this tag. Stop."
  exit 1
fi

grep -n "PB_ADVANCED_LICENSE_ADMIN_UI_V26B\|PB_PLAN_LIMITS_ADMIN_SEATS_V27\|PB_LICENSE_GATE_V28\|PB_SERVER_LICENSE_ENFORCEMENT_UI_V29" public/index.html worker/src/app.html | head -220 || true
grep -n "PB_SERVER_LICENSE_ENFORCEMENT_V29\|/api/license-gate" worker/src/index.js | head -120 || true

echo ""
echo "------ Build / test ------"
npm run build
npm test
npm run worker:check
node --check mobile-sync-worker/src/index.js
node --check mobile-sync-worker/src/tournament-room.js

echo ""
echo "------ Deploy to production only ------"
cd "$WORKTREE/worker"
npx wrangler deploy --env rally

echo ""
echo "------ Production edge check ------"
curl -i -s "$PROD_URL/health?v=deploy-tag-v30b-$(date +%s)" | head -80 || true

echo ""
echo "Production deploy from tag complete:"
echo "$TAG"
