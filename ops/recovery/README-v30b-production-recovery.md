# V30B Production Recovery Kit

This recovery kit supports the Pickleball Pro / Rally production Worker.

## Current green stack

- V26B: Protected Advanced License Admin
- V27: Plan Limits + Admin Seats
- V28: License Status Gate
- V29: Server License Enforcement
- V31F: Polished Client Onboarding

## Production URLs

- Production app: https://rally.coachjohnpickleball.workers.dev
- Production health: https://rally.coachjohnpickleball.workers.dev/health
- Production license gate: https://rally.coachjohnpickleball.workers.dev/api/license-gate?clientId=rally-coachjohnpickleball-workers-dev

## Token safety

The production owner admin token is not stored in Git.
Keep the token in a password manager or secure note.
Never paste the production token into committed files.

## Step 1 script

Run:

  bash ops/recovery/verify-production-v30b.sh

## Additional scripts

Deploy a known-good tag to production:

  bash ops/recovery/deploy-production-tag-v30b.sh green-client-onboarding-v31f-YYYYMMDD-HHMMSS

Restore the production license record to Club / Active:

  PB_PROD_ADMIN_LICENSE_TOKEN="paste-token-here" bash ops/recovery/restore-production-license-v30b.sh

Notes:

- These scripts do not store secrets in Git.
- Deploy-from-tag uses a temporary git worktree.
- Restore-license requires the owner admin token.
