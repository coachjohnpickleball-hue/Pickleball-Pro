# PickleBall Pro Client Manager Runbook

## Current Status

Client Manager is green and backed up to GitHub.

Current tools:

- client-manager-v37g.sh
- list-clients-v37f.sh
- create-staging-client-v37e.sh
- create-production-client-v37e.sh
- delete-staging-client-v37d3.sh
- delete-production-client-v37d3.sh

## Main Launcher

Run this from the project root:

./ops/client-manager/client-manager-v37g.sh

## Staging

URL:

https://rally-staging.coachjohnpickleball.workers.dev

KV:

d4be478f609e4696aae597c6adf6c533

## Production

URL:

https://rally.coachjohnpickleball.workers.dev

KV:

faac1bcc30ef4711a9377e60ef70636d

## Rules

- Cloudflare Access controls login.
- clientId controls client separation.
- Every client link must include ?clientId=<clientId>.
- Deleted clients get a tombstone.
- Tombstoned clients cannot be reopened from old links.
- Tombstoned clients are hidden from admin lists.
- Do not copy staging KV to production.
- Do not delete tombstones unless building a separate revive process.

## Safe Workflow

Use the launcher:

./ops/client-manager/client-manager-v37g.sh

Recommended normal actions:

1. List staging clients.
2. List production clients.
3. Create staging client.
4. Test staging link.
5. Only create production client when ready.
6. Only delete production client with exact confirmation.

## Known Green Markers

PB_CLIENT_TOMBSTONE_ENFORCEMENT_V37D2
PB_CLIENT_TOMBSTONE_ROUTE_GATE_V37D3
PB_ADMIN_CLIENTS_TOMBSTONE_FILTER_V37D4
PB_SAFE_CLIENT_CREATE_V37E

## Recovery Tags

Latest important tags include:

green-client-manager-launcher-v37g
green-client-list-tool-v37f
green-production-admin-tombstone-filter-v37d4
green-production-client-tombstone-v37d3
green-staging-client-create-delete-lifecycle-v37e
