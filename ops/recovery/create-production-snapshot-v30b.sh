#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-/Users/jmerg/Desktop/! ! Pickleball Pro/Cloudflare Hosting/Rally/ChatGPT/rally.PickleballPro/Pickelball-Pro}"
PROD_URL="${PROD_URL:-https://rally.coachjohnpickleball.workers.dev}"
PROD_CLIENT_ID="${PROD_CLIENT_ID:-rally-coachjohnpickleball-workers-dev}"

cd "$PROJECT"

OUT="/tmp/pb-production-recovery-v30b-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

echo "Creating production recovery snapshot:"
echo "$OUT"

echo ""
echo "------ Git status ------"
git status --short | tee "$OUT/git-status.txt"

echo ""
echo "------ Current HEAD ------"
git rev-parse HEAD | tee "$OUT/git-head.txt"

echo ""
echo "------ Current branch ------"
git branch --show-current | tee "$OUT/git-branch.txt"

echo ""
echo "------ Recent commits ------"
git log --oneline --decorate -40 | tee "$OUT/git-log-recent.txt"

echo ""
echo "------ Recent tags ------"
git tag --sort=-creatordate | head -100 | tee "$OUT/git-tags-recent.txt"

echo ""
echo "------ File checksums ------"
shasum -a 256 public/index.html worker/src/app.html worker/src/index.js worker/wrangler.toml package.json | tee "$OUT/file-checksums-sha256.txt"

echo ""
echo "------ Copy key files ------"
cp worker/wrangler.toml "$OUT/wrangler.toml"
cp package.json "$OUT/package.json"
cp worker/package.json "$OUT/worker-package.json" 2>/dev/null || true
cp ops/recovery/README-v30b-production-recovery.md "$OUT/README-v30b-production-recovery.md" 2>/dev/null || true

echo ""
echo "------ Build / test source before snapshot ------"
npm run build
npm test
npm run worker:check
node --check mobile-sync-worker/src/index.js
node --check mobile-sync-worker/src/tournament-room.js

echo ""
echo "------ Create git bundle ------"
git bundle create "$OUT/repo-all-refs.bundle" --all
git bundle verify "$OUT/repo-all-refs.bundle" | tee "$OUT/git-bundle-verify.txt"

echo ""
echo "------ Production health check ------"
curl -L -s "$PROD_URL/health?v=snapshot-v30b-$(date +%s)" | tee "$OUT/production-health.txt" || true

echo ""
echo "------ Production license gate check ------"
curl -s "$PROD_URL/api/license-gate?clientId=$PROD_CLIENT_ID&v=snapshot-v30b-$(date +%s)" | tee "$OUT/production-license-gate.json" || true

echo ""
echo "------ Public POST block check ------"
curl -i -s -X POST "$PROD_URL/api/client-license?clientId=$PROD_CLIENT_ID" -H "Content-Type: application/json" --data "{\"licenseLevel\":\"enterprise\",\"licenseStatus\":\"active\",\"playerLimit\":250,\"adminSeats\":25}" | tee "$OUT/production-public-post-block-check.txt" || true

printf "%s\n" "Pickleball Pro / Rally Production Recovery Snapshot" "" "Created: $(date)" "Project: $PROJECT" "Production URL: $PROD_URL" "Production Client ID: $PROD_CLIENT_ID" "" "This package does not include Cloudflare secrets or the production owner admin token." "" "To inspect bundle:" "  git bundle verify repo-all-refs.bundle" "" "To restore from bundle into a new folder:" "  git clone repo-all-refs.bundle restored-repo" > "$OUT/README.txt"

echo ""
echo "Snapshot complete:"
echo "$OUT"
