# Deploy Guide — Pickleball Pro on Cloudflare (Free Tier)

This uses one Cloudflare Worker (`pickleball-relay`) to serve **both** the
tournament app itself and its backend API (SMS, email, standings), on one
free `*.workers.dev` URL.

**Why one Worker instead of separate Pages + Worker pieces**: an earlier
version of this project split the app (Cloudflare Pages) from the API (a
separate Worker). That hit a real Cloudflare Access limitation —
Access's human-login redirect can't be completed by a cross-origin
`fetch()`, and Access can't be scoped to a specific path under `pages.dev`
(a domain Cloudflare shares across all customers' Pages projects, not one
your account controls). Serving everything from one Worker on your own
`workers.dev` subdomain sidesteps both problems entirely: one origin, one
Access application, no cross-origin request ever happens.

Two pieces remain:
1. **`worker/`** — the relay Worker; serves the app AND `/api/sms`,
   `/api/email`, `/api/standings`.
2. **`mobile-sync-worker/`** — separate, optional, for the scorekeeper
   phone-entry feature (Durable Objects; different enough to stay its own
   deployment — see §11).

## 0. Install Wrangler (one-time)
```bash
npm install -g wrangler
wrangler login
```

## 1. Worker: create the KV namespace
```bash
cd worker
wrangler kv namespace create USAGE
```
Copy the `id` it prints into `wrangler.toml` under `[[kv_namespaces]]`,
replacing `REPLACE_WITH_YOUR_KV_NAMESPACE_ID`.

## 2. Worker: set your secrets
Never put these in a file that gets committed. Each command prompts you to
paste the value:
```bash
wrangler secret put TWILIO_ACCOUNT_SID
wrangler secret put TWILIO_AUTH_TOKEN
wrangler secret put TWILIO_FROM        # your Twilio number, e.g. +16475551234

wrangler secret put BREVO_API_KEY      # from brevo.com — Settings > SMTP & API > API Keys (use the API key, not the SMTP key)
wrangler secret put SMTP_FROM          # e.g. tournaments@yourdomain.com — must be a verified sender in Brevo
wrangler secret put SMTP_FROM_NAME     # e.g. "Pickleball Pro"
```

## 3. Worker: adjust daily caps (optional)
Edit the `[vars]` section in `wrangler.toml`:
```toml
MAX_SMS_PER_DAY   = "200"
MAX_EMAIL_PER_DAY = "500"
```
Note: these caps now apply across ALL customers combined (the app
authenticates to the API via one shared Access Service Token — see §6 —
not per-customer logins), not per individual customer.

## 4. Build the app and sync it into the Worker
From the project root (not `/worker`):
```bash
cd ..
npm install --no-save html-minifier-terser terser
node build.js
```
This does two things: minifies `public/index.html` → `dist/index.html`,
AND automatically copies the result into `worker/src/app.html` (which
`worker/src/index.js` imports and serves). Re-run this any time you edit
`public/index.html` — the sync into the Worker is automatic, you don't
need a separate copy step.

## 5. Deploy the Worker
```bash
cd worker
wrangler deploy
```
**Copy the URL it prints** — looks like:
```
https://pickleball-relay.yoursubdomain.workers.dev
```
This is now your **entire app's URL** — open it directly to see the
tournament app itself, not just an API health check.

## 6. Set up a Service Token (so the app's own API calls authenticate)
Even though the app and API are now same-origin, the API still requires a
verified Cloudflare Access identity on every `/api/*` POST. The app
authenticates its own calls using an Access Service Token rather than
requiring you to log in twice.

### Create the Service Token (one-time, dashboard)
1. Zero Trust → Access → **Service Auth** → Create Service Token
2. Name it something like `pickleball-app-relay-access`
3. **Copy the Client ID and Client Secret immediately** — the secret is
   only ever shown once

You don't need to add these to the app's code or any config file — the
frontend's own JavaScript doesn't send them directly (see §7c below for
exactly how this is wired).

## 7. Lock it down with Cloudflare Access

### 7a. Create the Access application
1. Zero Trust → Access → Applications → **Add an application** → Self-hosted
2. Name: `Pickleball Pro v2`
3. Subdomain: `pickleball-relay`, Domain: select `yoursubdomain.workers.dev`
   from the dropdown (your account's own subdomain — this is the only
   option that will appear, which is expected and fine)
4. Session duration: 24h is reasonable

### 7b. Add the human-login policy
1. Policy name: `Approved customers`
2. Action: `Allow`
3. Include → Emails → your email first, add real customers as you onboard them
4. Under Zero Trust → Settings → Authentication, make sure **One-time PIN**
   is available (it's Cloudflare's default — usually nothing to configure)

### 7c. Add the service-token policy (separate policy, same application)
1. Still on this application → Policies → **Add a policy** (a second one)
2. Policy name: `Service token for app relay calls`
3. Action: `Service Auth`
4. Include → Service Token → select `pickleball-app-relay-access`
5. Save — you should now see 2 policies on this one application

With both policies in place: a real person visiting the URL in a browser
gets the email/one-time-PIN login flow; the app's own JavaScript `fetch()`
calls to `/api/*` are recognized by Access via the same browser session
(no separate token-sending code needed in the frontend, since everything
is same-origin and the human session already covers it) — Access just
needs *a* valid policy match, and the human-login one already satisfies
that once you're logged in.

(The service-token policy mainly matters if you ever call the API from
something that isn't a logged-in browser — a script, a cron job, etc. It's
included here as the more robust long-term setup, but for normal
in-browser use, §7b's email login alone is sufficient day to day.)

## 8. Smoke test
1. Visit `https://pickleball-relay.yoursubdomain.workers.dev` directly —
   should prompt for Access login first
2. Log in with an approved email (one-time code)
3. You should land on the actual tournament app (not JSON) — this Worker
   now serves the app directly
4. Open the SMS tab → click "Check relay status" → should report connected
5. Send yourself a test text and test email
6. Generate a schedule, save a score, open the Standings tab → confirm it
   populates correctly
7. Confirm a non-approved email is blocked entirely (try in an incognito
   window with a different email)

## Ongoing: adding/removing customers
No deploy needed — just edit the email allowlist in the Cloudflare Access
policy (Zero Trust dashboard → Access → Applications → Pickleball Pro v2 →
the `Approved customers` policy → edit the Include rule).

## Ongoing: redeploying after edits
```bash
node build.js
cd worker
wrangler deploy
```

## Adding a custom domain later
1. Buy a domain, add it to Cloudflare (Cloudflare dashboard → Add a site)
2. Workers & Pages → your Worker → Settings → Triggers → add a custom domain
3. Update the Access application's domain to match

## 9. Mobile Sync (scorekeeper phone entry) — separate Worker
This is a separate Cloudflare Worker from the relay, using Durable Objects
to hold live per-tournament state. It's optional — only deploy it if you
want the "scorekeepers enter scores from their phones" feature.

**Why it's separate from the relay Worker**: Durable Objects give each
tournament code its own stateful, persistent instance (claims, pending
scores, live court data) — a different Cloudflare primitive than the
relay's KV-based usage tracking, and a different security model (see
below), so keeping them as separate deployments is intentional.

### 9a. Deploy
```bash
cd mobile-sync-worker
wrangler deploy
```
First deploy creates the Durable Object class automatically (the
`migrations` section in `wrangler.toml` handles this — don't edit that
section after the first successful deploy). **Copy the URL it prints**.

### 9b. Point the desktop app at it
In the running app: **Mobile Sync tab → Worker URL** field → paste the URL
from 9a. This is stored in the browser (localStorage), not hardcoded in
the build.

### 9c. Security model — different from the relay Worker, and that's correct
This Worker is **not** behind Cloudflare Access, deliberately. Access
protects the relay because the relay spends your money and only your
paying customers (organizers) should reach it. Mobile Sync's actual users
are tournament *players* tapping a link mid-match — requiring an email
login to submit a score would defeat the feature. Instead, protection here
is: a short tournament code (a shared secret per event), an optional
per-court PIN the organizer sets, a random token issued to a phone once it
claims a court, and roster name-matching on claim.

This is appropriate for the threat model (a player overwriting their own
match's score by mistake or mischief) but is **not** equivalent to the
relay's protection. Don't post tournament codes somewhere public if you'd
rather keep that link to players only.

### 9d. Smoke test
1. Visit the Mobile Sync Worker's URL directly — should show the
   scorekeeper entry page
2. In the desktop app's Mobile Sync tab, generate a code and push the
   current round
3. On a phone (or another browser tab), visit the Worker URL, enter the
   code, claim a court, submit a score
4. Back in the desktop app, confirm the score syncs in
