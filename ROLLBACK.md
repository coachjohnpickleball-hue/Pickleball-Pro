# Rollback Guide — How to Undo This Setup If Something Breaks

Cloudflare doesn't have one single "undo" button. Workers don't keep
automatic deployment history the way some platforms do — your locally
saved project files ARE the rollback mechanism for most of this. This
guide covers **before you deploy** (so a revert is actually possible) and
**after something's broken** (how to actually revert each piece).

The single most important thing: **do the "before you deploy" section
first.** Every safety net below depends on it.

---

## You already have something live — read this first

If you previously deployed `password-gate-worker.js` and/or the earlier
`sms-worker.js` and they're currently running and reachable by real
customers, **do not deploy the new setup using those same names.** This is
the single biggest risk: overwriting a working deployment with an
untested one, with no easy way back.

### Find out exactly what's currently live
1. Dashboard → **Workers & Pages** → note every Worker name listed (the
   deployed name may not match the local filename)
2. For each one, check **Settings → Triggers/Domains** to see what
   URL/route it's actually reachable at
3. Write these down (name → live URL) before doing anything else

### Deploy the new setup under different names
This project's Workers are named `pickleball-relay` and
`pickleball-mobile-sync-v2` in their `wrangler.toml` files. **Before
deploying, double-check these names against what you wrote down in step
1** — if either matches something already live, change the `name = "..."`
line in the relevant `wrangler.toml` before running `wrangler deploy`.
This is exactly the mistake that happened once already in this project's
setup: a `wrangler.toml` rename made in one place didn't make it onto the
locally unzipped copy, and a deploy briefly overwrote a live Worker before
being caught and rolled back. Always re-verify the name in the actual file
on your machine, in your terminal, immediately before deploying — don't
trust that an edit "should" be there.

### Only retire the old one once the new one is fully tested
Don't delete or stop `password-gate-worker.js` (or any prior setup) until
the new Worker is fully deployed, smoke-tested (see `DEPLOY.md`'s smoke
test section), and you've personally logged in and sent a real test
SMS/email through it. Until that point, keep both running side by side —
there's no cost to this on Cloudflare's free tier.

---

## How to revert each piece

### The Worker (app + API, or mobile-sync)
Workers do **not** keep automatic deployment history the way some
platforms do — this is the one place you genuinely need your own saved
local copies.
- **If you have a previous working version of `worker/src/index.js` (and
  `worker/src/app.html`) saved locally**: just `wrangler deploy` that
  older version again. It overwrites the live Worker instantly.
- **If you don't have an older copy saved**: Cloudflare dashboard →
  Workers & Pages → your Worker → **Deployments** tab. Workers do show a
  deploy history here — you can view past versions' source and copy it
  out, though there's no one-click rollback button. Copy the old code
  locally and redeploy.
- **Fastest emergency option**: if a Worker is actively causing harm
  (e.g. burning through Twilio credits unexpectedly), disable it
  immediately without reverting code: dashboard → your Worker → Settings
  → Disable (or delete it outright, which immediately stops all traffic).

### Worker secrets (Twilio/Brevo credentials)
Secrets aren't versioned — there's no history to roll back to. Write down
current values somewhere safe (a password manager) *before* changing one,
since `wrangler secret put NAME` always overwrites silently with no way to
retrieve the previous value afterward.

### KV namespace (usage counters)
If the daily-cap counters get into a bad state, clear a specific key
without affecting anything else:
```bash
wrangler kv key delete --binding=USAGE "sms:service-token:abc123...:2026-06-20"
```
Deleting the whole namespace loses all usage history — only do this if
abandoning the setup entirely.

### Cloudflare Access (the login wall)
1. Dashboard → Zero Trust → Access → Applications
2. Each application can be **edited** or **deleted**
3. **Deleting an Access application immediately removes the login wall** —
   the Worker becomes publicly reachable with no login required. Fastest
   way to "turn off" Access if it's misconfigured and blocking you out,
   but be aware anyone can reach the app until you fix and re-add it.
4. Dashboard access doesn't go through Access itself, so you can always
   fix a broken policy from the Cloudflare dashboard regardless of what
   Access is currently blocking on the app's own URL.

### DNS / custom domain (only relevant once you add one)
Removing a custom domain from a Worker (Workers & Pages → your Worker →
Settings → Triggers/Domains → remove) instantly falls back to the free
`*.workers.dev` URL, which keeps working the whole time regardless of what
you do with the custom domain.

---

## The practical "everything is broken, start over" path
1. Dashboard → Workers & Pages → delete the Worker(s) for this project by name
2. Zero Trust → Access → delete the Access applications you created for it
3. `wrangler kv namespace delete` the USAGE namespace if you created one
4. Your old setup (if you kept it separate per the section above) was
   never touched and is still running exactly as before
5. Re-deploy fresh from your saved local project folder whenever ready,
   following `DEPLOY.md` again from step 0

---

## TL;DR — the one habit that makes all of this easy
**Keep this project's files saved locally, outside Cloudflare, and
re-verify the exact name in `wrangler.toml` immediately before every
deploy command** — don't trust that an edit you made elsewhere actually
made it into the copy on your machine.
