# Pickleball Pro — Hosted Edition

Your tournament app, restructured to run as a hosted, login-gated,
multi-customer web app on Cloudflare's free tier instead of a file you
double-click locally or a Worker behind a single shared password.

## What changed from the uploaded files

| Before (uploaded) | Now |
|---|---|
| `sms-worker.js`: SMS via Twilio (Worker secrets) ✓ already good | Kept — same approach, consolidated into one Worker |
| `sms-worker.js`: Email via raw SMTP-over-socket, credentials sent from browser on every send | Email via Brevo's HTTPS API, using *your* Brevo secret — no credentials ever leave your Worker |
| `password-gate-worker.js`: one hardcoded password (`PickleBall26!`) shared by everyone, no revoke-per-person | Cloudflare Access — each customer gets their own login (one-time email code), individually revocable |
| Frontend: SMTP host/port/user/password form fields | Removed — nothing left to configure, the relay handles it |
| Full-size, readable JS | Minified build step (`build.js`) for production |
| Standings win/loss/points calculation ran entirely in the shipped JS | Moved to the relay Worker (`/api/standings`) — the calculation itself is no longer visible in the page source. Falls back to local calculation automatically if the relay is unreachable, so the tab never breaks. |

## Project layout
```
pickleball-app/
├── public/index.html          ← source app (edit this)
├── dist/index.html            ← built/minified output (generated, don't edit)
├── build.js                   ← minifies public/ → dist/, auto-syncs into worker/src/app.html
├── worker/                    ← serves BOTH the app and the API (one deployment)
│   ├── src/index.js           ← routes: GET / (the app), POST /api/sms, /api/email, /api/standings
│   ├── src/app.html           ← generated copy of dist/index.html — don't edit directly
│   ├── src/standings.js
│   └── wrangler.toml
├── mobile-sync-worker/        ← scorekeeper phone-entry Worker (Durable Objects)
│   ├── src/index.js
│   ├── src/tournament-room.js
│   ├── src/mobile.html
│   └── wrangler.toml
├── DEPLOY.md                  ← step-by-step deploy instructions (all pieces)
├── CLOUDFLARE_ACCESS_SETUP.md ← step-by-step login-wall setup
├── ROLLBACK.md                ← how to undo / protect existing deployments
└── README.md                  ← this file
```

**Why one Worker serves both the app and the API**: an earlier version of
this project split them — Cloudflare Pages for the app, a separate Worker
for the API — which hit a real Cloudflare Access limitation. Access
protects requests with a human-login redirect flow that a cross-origin
`fetch()` can't complete (shows up as a CORS error regardless of CORS
configuration), and Access can't be scoped to a specific path under
`pages.dev` (a domain Cloudflare shares across every customer's Pages
project, not one this account controls) the way it can for your own
`workers.dev` subdomain. Serving everything from one Worker sidesteps both
problems: one origin, one Access application, no cross-origin request ever
happens.

This is now two independent Cloudflare deployments: `pickleball-relay`
(the app + SMS/email/standings API, behind Access) and
`pickleball-mobile-sync-v2` (scorekeeper score entry, deliberately *not*
behind Access — see `DEPLOY.md` §9c for why that's the correct call, not
an oversight).

## Mobile Sync tab
Fully wired up — `mobile-sync-worker/` contains the Durable-Object-backed
Worker (state sync, court claims, PINs, announcements) and the
scorekeeper-facing phone UI. See `DEPLOY.md` §9 for deploying it and
pointing the desktop app's Mobile Sync tab at it.

## Quick start
0. **If you already have something deployed on Cloudflare** (e.g. an
   earlier version using `password-gate-worker.js`), read `ROLLBACK.md`
   first — it covers keeping your existing live deployment safe and
   untouched while you test this one.
1. Read `DEPLOY.md` top to bottom — it's the actual runbook.
2. To make future edits: change `public/index.html`, run `node build.js`
   (this auto-syncs into the Worker too), then `cd worker && wrangler deploy`.

## On the password that was in password-gate-worker.js
That file is not included in this rebuild and should not be deployed as
extracted — the password was hardcoded in plain text in the source, shared
by every customer, and unrevokable per-person. If you ever pasted that file
anywhere (a chat, a repo, a screenshot), treat `PickleBall26!` as
compromised regardless of what you do here. Cloudflare Access replaces it
entirely with no password to leak in the first place.

## On "protecting the IP"
Worth restating plainly: this setup makes the app **access-gated and
backend-secured** — nobody gets in without an approved login, and your
Twilio/Brevo credentials and sending logic never reach a browser. What it
does *not* do is make the frontend code unreadable to someone who *is*
logged in and opens devtools — no web app can fully prevent that, including
this one. If you want stronger legal footing on top of the technical
measures, add a visible copyright notice and Terms of Service the customer
agrees to on login; that's what gives you standing if someone does copy it
wholesale.
