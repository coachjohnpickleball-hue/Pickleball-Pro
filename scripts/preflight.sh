#!/usr/bin/env bash
set -e

echo "------ BUILD ------"
npm run build

echo "------ TESTS ------"
npm test

echo "------ MAIN WORKER CHECK ------"
npm run worker:check

echo "------ MOBILE WORKER SYNTAX CHECK ------"
node --check mobile-sync-worker/src/index.js
node --check mobile-sync-worker/src/tournament-room.js

echo "------ PREFLIGHT PASSED ------"
git status --short
