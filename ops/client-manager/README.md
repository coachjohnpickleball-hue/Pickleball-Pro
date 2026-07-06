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

## Health Check ALL

V37W adds a one-click read-only health check:

./ops/client-manager/health-check-all-v37w.sh

It runs:
1) Production client list
2) Production client audit
3) Production license usage audit
4) Staging client list
5) Staging client audit
6) Staging license usage audit

The same check is available in the Client Manager menu as:

15) Health Check ALL

## Client Backup / Export

V37X adds local read-only backups:

./ops/client-manager/backup-clients-v37x.sh staging
./ops/client-manager/backup-clients-v37x.sh production

The backups include:
1) client-license keys
2) client-state keys
3) client-deleted tombstone keys
4) manifest.json
5) summary.txt

Backup files are written under:

ops/client-manager/backups/

The backup folder is ignored by Git so private client data is not pushed to GitHub.

The same backup options are available in the Client Manager menu:

15) Backup STAGING clients
16) Backup PRODUCTION clients

## Restore Client From Backup

V37Z adds a guarded restore tool:

./ops/client-manager/restore-client-from-backup-v37z.sh <staging|production> <backupFolder> <clientId> [license|state|license-state]

Examples:

./ops/client-manager/restore-client-from-backup-v37z.sh production ops/client-manager/backups/production-YYYYMMDD-HHMMSS blue-zone-pickleball license-state

Modes:
- license
- state
- license-state

Production restore automatically creates a fresh production backup before writing anything.

Production confirmation phrase:

RESTORE PRODUCTION <clientId> FROM BACKUP

Staging confirmation phrase:

RESTORE STAGING <clientId> FROM BACKUP

## Restore From Backup Menu

V38A adds restore options to the Client Manager menu:

17) Restore STAGING client from backup
18) Restore PRODUCTION client from backup

The menu wrapper asks for:
1) backup folder
2) client ID
3) restore mode

Restore modes:
- license-state
- state only
- license only

Production restores still use the guarded V37Z restore tool and create a fresh production backup before writing anything.

## Backup Inventory

V38B adds a read-only backup inventory tool:

./ops/client-manager/backup-inventory-v38b.sh

It lists local backup folders, environment, license count, state count, tombstone count, and latest production/staging backup.

The same tool is available in the Client Manager menu:

17) Backup inventory

## Suspend / Reactivate Client

V38C adds license status update tools:

./ops/client-manager/update-staging-status-v38c.sh <clientId> <active|suspended|trial>
./ops/client-manager/update-production-status-v38c.sh <clientId> <active|suspended|trial>

Production confirmation phrase:
STATUS PRODUCTION <clientId> <active|suspended|trial>

Staging confirmation phrase:
STATUS <clientId> <active|suspended|trial>

Production status changes automatically create a backup before writing.

V37P server-side enforcement blocks client-state saves when licenseStatus is not active or trial.

## License Usage Audit Status Display

V38H improves the existing license usage audit:

./ops/client-manager/license-usage-audit-v37q.sh staging
./ops/client-manager/license-usage-audit-v37q.sh production

It now clearly reports:
- OK
- TRIAL
- SUSPENDED
- INACTIVE
- OVER_LIMIT
- NO_STATE_YET
- TOMBSTONED

This is read-only and makes suspended/non-paying clients easier to review.

## Renewal / Expiry Audit

V38I adds a read-only renewal / expiry audit:

./ops/client-manager/renewal-expiry-audit-v38i.sh staging
./ops/client-manager/renewal-expiry-audit-v38i.sh production

It checks license fields:
- renewalDate
- expiresAt
- subscriptionEndsAt
- trialEndsAt

It reports:
- OK
- TRIAL
- EXPIRING_SOON
- EXPIRED
- SUSPENDED
- NO_RENEWAL_DATE
- TOMBSTONED

## Set Renewal / Expiry Date

V38J adds guarded renewal / expiry date tools:

./ops/client-manager/update-staging-renewal-v38j.sh <clientId> <YYYY-MM-DD|clear> [renewalDate|expiresAt|subscriptionEndsAt|trialEndsAt]
./ops/client-manager/update-production-renewal-v38j.sh <clientId> <YYYY-MM-DD|clear> [renewalDate|expiresAt|subscriptionEndsAt|trialEndsAt]

Default field is renewalDate.

Production confirmation phrase:
RENEWAL PRODUCTION <clientId> <field> <YYYY-MM-DD|clear>

Staging confirmation phrase:
RENEWAL <clientId> <field> <YYYY-MM-DD|clear>

Production renewal date changes automatically create a backup before writing.

## Billing Summary Export

V38L adds read-only billing summary exports:

./ops/client-manager/billing-summary-export-v38l.sh staging
./ops/client-manager/billing-summary-export-v38l.sh production

Reports are written locally under:

ops/client-manager/reports/

The CSV/JSON include:
- clientId
- clientName
- status
- level
- activePlayers
- totalPlayers
- playerLimit
- renewalDate
- daysLeft
- billingHealth
- privateLink

Report files are ignored by Git.

## Billing Contact Fields

V38M adds guarded billing contact tools:

./ops/client-manager/update-staging-billing-contact-v38m.sh <clientId>
./ops/client-manager/update-production-billing-contact-v38m.sh <clientId>

Fields:
- billingName
- billingEmail
- billingPhone
- billingNotes

Production confirmation phrase:
BILLING PRODUCTION <clientId>

Staging confirmation phrase:
BILLING <clientId>

Production billing contact changes automatically create a backup before writing.

V38M also adds billing contact columns to the V38L billing summary CSV/JSON export.

## Billing Follow-Up Report

V38O adds a read-only billing follow-up report:

./ops/client-manager/billing-followup-report-v38o.sh staging
./ops/client-manager/billing-followup-report-v38o.sh production

It creates focused TXT/CSV reports under:

ops/client-manager/reports/

It only lists clients needing attention:
- EXPIRED
- EXPIRING_SOON
- SUSPENDED
- INACTIVE
- OVER_LIMIT
- NO_RENEWAL_DATE

Each row includes a suggested action.

## Billing Email Drafts

V38P adds read-only billing email draft generation:

./ops/client-manager/billing-email-drafts-v38p.sh staging
./ops/client-manager/billing-email-drafts-v38p.sh production

It uses the V38O billing follow-up report and creates local TXT drafts under:

ops/client-manager/reports/

No emails are sent automatically.

Drafts are generated for clients needing follow-up:
- EXPIRED
- EXPIRING_SOON
- SUSPENDED
- INACTIVE
- OVER_LIMIT
- NO_RENEWAL_DATE

## Client Onboarding Packet

V38Q adds a read-only onboarding packet generator:

./ops/client-manager/client-onboarding-packet-v38q.sh staging <clientId>
./ops/client-manager/client-onboarding-packet-v38q.sh production <clientId>

It creates local files under:

ops/client-manager/reports/

Files created:
- welcome-email.txt
- client-summary.txt
- private-link.txt
- license.json

No KV changes are made.

