# PickleBall Pro Client Manager

Safe command-line tools for managing PickleBall Pro clients, private links, license levels, audits, and cleanup.

## Location

Project root:

/Users/jmerg/Desktop/! ! Pickleball Pro/Cloudflare Hosting/Rally/ChatGPT/rally.PickleballPro/Pickelball-Pro

Client Manager menu:

ops/client-manager/client-manager-v37g.sh

Easy launchers:

./client-manager.sh

Or double-click:

Open Client Manager.command

## Launch

From Terminal:

setopt NO_BANG_HIST
cd "/Users/jmerg/Desktop/! ! Pickleball Pro/Cloudflare Hosting/Rally/ChatGPT/rally.PickleballPro/Pickelball-Pro"
./client-manager.sh

## Menu

Read-only:
1)  List STAGING clients
2)  List PRODUCTION clients
3)  Audit STAGING clients
4)  Audit PRODUCTION clients
5)  License usage audit STAGING
6)  License usage audit PRODUCTION
7)  Inspect STAGING client
8)  Inspect PRODUCTION client

Staging operations:
9)  Create STAGING client
10) Delete STAGING client
11) Update STAGING license

Production operations:
12) Create PRODUCTION client
13) Delete PRODUCTION client
14) Update PRODUCTION license

Other:
15) Show installed tools
16) Quit

## Environments

Staging app:
https://rally-staging.coachjohnpickleball.workers.dev

Production app:
https://rally.coachjohnpickleball.workers.dev

Staging KV:
d4be478f609e4696aae597c6adf6c533

Production KV:
faac1bcc30ef4711a9377e60ef70636d

## License levels

trial       16 players   mobile scoring off   official results off
club        40 players   mobile scoring on    official results on
pro         96 players   mobile scoring on    official results on
enterprise 250 players   mobile scoring on    official results on

## Safety rules

Production actions require stronger confirmation.

Create production client:
CREATE PRODUCTION <clientId>

Delete production client:
DELETE PRODUCTION <clientId>

Update production license:
UPDATE PRODUCTION <clientId> <level>

The license update tools include downgrade protection. If a client has more active players than the requested new plan allows, the tool stops before making a change.

Avoid emergency override unless you understand the risk. A client over the license limit may be blocked from saving new state by server-side enforcement.

## Current license enforcement

V37O:
Browser-side license action enforcement. Blocks over-license actions in the UI.

V37P:
Server-side client-state license enforcement. Blocks direct API bypass attempts when active players exceed the license limit.

V37Q:
License usage audit. Reports each client’s license level, player limit, active players, total players, and health.

V37T:
Downgrade guard. Prevents accidental license updates that would put a client over limit.

## Recommended workflow

Before any production change:
1) List PRODUCTION clients
2) License usage audit PRODUCTION
3) Inspect PRODUCTION client
4) Make the change
5) License usage audit PRODUCTION again
6) Open the private production link and verify the app

For new clients:
1) Create STAGING client first
2) Test private staging link
3) Create PRODUCTION client
4) Send the private production link to the client
5) Run production license audit

For deleting clients:
1) Delete via Client Manager
2) Confirm license and state are gone
3) Confirm tombstone exists
4) Confirm old private link returns deleted/blocked
5) Run audit

## Important markers

Good markers:
PB_CLIENT_TOMBSTONE_ENFORCEMENT_V37D2
PB_ADMIN_CLIENTS_TOMBSTONE_FILTER_V37D4
PB_SAFE_CLIENT_CREATE_V37E
PB_SAFE_LICENSE_UPDATE_V37M
PB_LICENSE_ACTION_ENFORCEMENT_V37O
PB_SERVER_LICENSE_STATE_ENFORCEMENT_V37P
PB_LICENSE_DOWNGRADE_GUARD_V37T

Rejected markers that should not return:
PB_CLIENT_ACCESS_KEY_GATE_CLIENT_V36E
PB_ROLE_BASED_CLIENT_ACCESS_V36F
PB_CLIENTKEY_RELAY_V36F2
PB_DISABLE_CLIENTKEY_GATE_CLIENT_V36G
PB_CLIENT_MANAGER_V37A_ROUTE
PB_CLIENT_MANAGER_UI_V37A

## Quick production health check

./ops/client-manager/list-clients-v37f.sh production
./ops/client-manager/license-usage-audit-v37q.sh production

Expected real clients should be visible, tombstoned clients should be hidden, and no active client should be over limit.
