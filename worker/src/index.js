/**
 * Pickleball Pro — App + Relay Worker
 *
 * Serves the tournament app itself (the static HTML/JS, imported from
 * app.html) AND the backend API on this one Worker/origin. This consolidated
 * shape replaced an earlier two-piece design (Cloudflare Pages for the app +
 * a separate Worker for the API) after hitting a real Cloudflare Access
 * limitation: Access's human-login redirect can't be completed by a
 * cross-origin fetch(), and Access can't be scoped to a specific path under
 * pages.dev (a shared domain Cloudflare controls, not this account). Serving
 * everything from one Worker on this account's own workers.dev subdomain
 * sidesteps both problems — one origin, one Access application, no
 * cross-origin request ever happens.
 *
 * This Worker:
 *  - Serves the app's HTML at any GET that isn't /api/*
 *  - Sends SMS via Twilio using YOUR Twilio secrets (never the browser's)
 *  - Sends email via Brevo's HTTPS API using YOUR Brevo secret
 *  - Identifies the caller via Cloudflare Access's verified header (replaces
 *    the hardcoded shared-password gate from an earlier version entirely)
 *  - Enforces per-customer daily send caps in KV so no one account can run
 *    up your Twilio/Brevo bill
 *
 * Security model:
 *  - Twilio + Brevo credentials live ONLY as Worker secrets, set via
 *    `wrangler secret put` — never present in any file, never sent to or
 *    read from a browser.
 *  - Cloudflare Access sits in front of this Worker (see
 *    CLOUDFLARE_ACCESS_SETUP.md). POST requests to /api/* require either a
 *    real person's verified Access login (Cf-Access-Authenticated-User-Email
 *    header, which a client cannot forge — Cloudflare strips any
 *    client-supplied copy before this Worker ever sees the request) or a
 *    valid Access Service Token (Cf-Access-Client-Id header, verified by
 *    Access itself before the request arrives here). If neither is present,
 *    the request is rejected outright, regardless of what else is in the
 *    payload.
 */

import { computeStandings } from './standings.js';
import APP_HTML from './app.html';

const JSON_HEADERS = { 'Content-Type': 'application/json' };
const TOS_VERSION = '2026-06-24';
const TERMS_EFFECTIVE_DATE = 'June 24, 2026';
const APP_VERSION = 'v2.0.0';
const BUILD_DATE = '2026-06-23';
const ENFORCE_TOS_ACCEPTANCE = true;
// App-level user blocks. Use this for emergency/revoked access inside the app.
// Preferred day-to-day control is env.BLOCKED_USERS in wrangler.toml or a KV block added from /admin/users.
const STATIC_BLOCKED_USERS = [];

function getAdminEmails(env) {
  const envEmails = String((env && env.ADMIN_EMAILS) || '').split(',').map(e => e.trim().toLowerCase()).filter(Boolean);
  const staticEmails = ADMIN_EMAILS.map(e => String(e).trim().toLowerCase()).filter(Boolean);
  return Array.from(new Set([...staticEmails, ...envEmails]));
}

function isAdminUser(env, email) {
  return !!email && getAdminEmails(env).includes(String(email).trim().toLowerCase());
}

function appHtmlForUser(html, env, userEmail, termsConfig) {
  const admin = isAdminUser(env, userEmail);
  const access = {
    email: userEmail || '',
    isAdmin: admin,
    adminEmails: getAdminEmails(env),
    tosVersion: termsConfig.version,
    termsEffectiveDate: termsConfig.effectiveDate,
    appVersion: APP_VERSION,
    buildDate: BUILD_DATE,
    environment: (env && env.ENVIRONMENT) || 'production',
  };
  const script = `<script>window.__ACCESS__=${JSON.stringify(access)};</script>`;
  const css = admin ? '' : `<style id="admin-hide-css">#sec-admin,[data-admin-only],button[onclick*="showTab('admin'"],button[onclick*="showTab(\"admin\""],button[onclick*="/admin/"],a[href^="/admin/"]{display:none!important;visibility:hidden!important}</style>`;
  let out = html.includes('</head>') ? html.replace('</head>', `${script}${css}
</head>`) : `${script}${css}
${html}`;
  if (!admin) {
    out = out.replace(/<html([^>]*)>/i, function(match, attrs) {
      if (/class\s*=/.test(attrs)) {
        return '<html' + attrs.replace(/class\s*=\s*(["\'])(.*?)(\1)/i, function(_, q, cls, endq){ return 'class=' + q + cls + ' pb-non-admin-root' + endq; }) + '>';
      }
      return '<html' + attrs + ' class="pb-non-admin-root">';
    });
    out = out.replace(/<body([^>]*)>/i, function(match, attrs) {
      if (/class\s*=/.test(attrs)) {
        return '<body' + attrs.replace(/class\s*=\s*(["\'])(.*?)(\1)/i, function(_, q, cls, endq){ return 'class=' + q + cls + ' pb-non-admin' + endq; }) + '>';
      }
      return '<body' + attrs + ' class="pb-non-admin">';
    });
    // Server-side hardening: strip obvious admin-only controls from non-admin HTML.
    out = out.replace(/<button\b(?=[^>]*\bdata-admin-only\b)[\s\S]*?<\/button>/gi, '');
    out = out.replace(/<a\b(?=[^>]*\bdata-admin-only\b)[\s\S]*?<\/a>/gi, '');
    out = out.replace(/<button\b(?=[^>]*showTab\(['"]admin['"])[\s\S]*?<\/button>/gi, '');
    out = out.replace(/<button\b(?=[^>]*\/admin\/)[\s\S]*?<\/button>/gi, '');
    out = out.replace(/<a\b(?=[^>]*href=["']\/admin\/)[\s\S]*?<\/a>/gi, '');
    out = out.replace(/<div\s+id=["']sec-admin["'][\s\S]*?(?=<div\s+id=["']sec-|<script|<\/main>)/i, '');
  }
  return out;
}

async function getTermsConfig(env) {
  const base = {
    version: String((env && env.CURRENT_TERMS_VERSION) || TOS_VERSION).trim() || TOS_VERSION,
    effectiveDate: String((env && env.CURRENT_TERMS_EFFECTIVE_DATE) || TERMS_EFFECTIVE_DATE).trim() || TERMS_EFFECTIVE_DATE,
  };
  if (!env || !env.USAGE) return base;
  try {
    const raw = await env.USAGE.get('config:terms');
    if (!raw) return base;
    const parsed = JSON.parse(raw);
    return {
      version: String(parsed.version || base.version).trim() || base.version,
      effectiveDate: String(parsed.effectiveDate || base.effectiveDate).trim() || base.effectiveDate,
    };
  } catch (_) {
    return base;
  }
}

// ── Force re-login on every visit — on/off switch ───────────────────────
// When true: every genuinely new visit (new tab, reopened tab, browser
// restart) forces a fresh Cloudflare Access login, regardless of how much
// time is left on the Access session. See the logic further below for
// how this works (a short-lived marker cookie + Access's own logout
// endpoint). Set to false during active development/testing to skip the
// extra login step on every reload — remember to set it back to true
// before real customers use the app, since that's the actual point of
// this feature.
const FORCE_RELOGIN_EVERY_VISIT = false;

// Plain-text Terms of Service, served at GET /terms and linked from the
// in-app acceptance modal. Keep this in sync with TOS_VERSION in the
// frontend (public/index.html) — when this text changes materially, bump
// that constant too so previously-accepted users are re-prompted.
//
const TERMS_OF_SERVICE_TEXT = `TERMS OF SERVICE
Pickleball Pro
Version: v2026-06-24
Effective Date: June 24, 2026

These Terms of Service ("Terms") govern access to and use of the
tournament management software and related services (the "Service")
provided by 1000221843 ONTARIO INC., a company organized under
the laws of Ontario, Canada ("we," "us," or
"the Company").

By creating an account, logging in, or otherwise accessing or using the
Service, you ("Customer," "you," or "your") agree to be bound by these
Terms. If you are using the Service on behalf of an organization, you
represent that you have authority to bind that organization.

If you do not agree to these Terms, do not access or use the Service.

1. THE SERVICE
The Service is a hosted, login-gated tournament management application,
including scheduling, score tracking, standings, SMS and email
notifications, and related tools, made available to approved Customers
via web browser. Access is granted individually, by invitation, at our
sole discretion, and may be added, suspended, or revoked at any time.

2. OWNERSHIP AND INTELLECTUAL PROPERTY
2.1 The Service — including its software, source code, user interface,
design, scheduling algorithms, and documentation — is and remains the
exclusive property of the Company and its licensors.
2.2 You are granted a limited, non-exclusive, non-transferable, revocable
license to use the Service for your own internal tournament management
purposes.
2.3 You agree not to: copy, redistribute, sell, or sublicense the
Service; reverse engineer or decompile the Service; build a competing
product based on the Service's design or scheduling logic; use automated
means to scrape or extract data from the Service; remove proprietary
notices; use the Service to train a competing AI/ML model; circumvent
login or security controls; or share your login credentials with anyone
not separately approved.
2.4 You retain ownership of your tournament and player data. You grant
the Company a limited license to host and process that data solely to
provide the Service to you.

3. ACCOUNT ACCESS AND SECURITY
You are responsible for the confidentiality of your login access and all
activity under your account. We may suspend or terminate access
immediately, without notice, for any violation of these Terms.

We record basic login activity for security and account-management
purposes, including your email address, login date/time, IP address,
approximate country derived from that IP address, and general
browser/device information (such as "Chrome on macOS"). This information
is retained for up to 90 days and is not shared with third parties except
as required to operate the Service or comply with law.

4. FEES AND PAYMENT
Access to the Service may be offered free of charge, on a subscription
basis, on a per-event basis, or under another pricing structure as
determined by the Company from time to time. Current pricing, if any,
will be communicated to you before any charge is made. Fees are
non-refundable except as required
by law or as the Company may agree in writing.

5. SMS AND EMAIL COMMUNICATIONS
You are solely responsible for obtaining recipient consent and complying
with applicable anti-spam/telemarketing laws before sending messages
through the Service. The Company is not responsible for deliverability.

6. DISCLAIMERS
THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTIES OF
ANY KIND, EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

7. LIMITATION OF LIABILITY
TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE COMPANY IS NOT LIABLE FOR ANY
INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES. THE
COMPANY'S TOTAL LIABILITY SHALL NOT EXCEED THE AMOUNT YOU PAID IN THE
TWELVE (12) MONTHS PRECEDING THE CLAIM.

8. TERMINATION
Either party may terminate access at any time. Sections 2, 6, 7, and 9
survive termination.

9. GOVERNING LAW
These Terms are governed by the laws of Ontario, Canada.
Disputes shall be resolved in the courts of Oakville, Ontario.

10. CHANGES TO THESE TERMS
We may update these Terms; material changes will be communicated to
active Customers. Continued use after changes take effect constitutes
acceptance.

11. CONTACT
Questions or notices: coachjohnpickleball@gmail.com
`;

// Kept as defense-in-depth even though the app and API now share one
// origin (so there's no cross-origin request to actually restrict) — set
// to '*' since there is no longer a separate origin to scope this to.
function cors(resp, env) {
  const origin = (env && env.ALLOWED_ORIGIN) || '*';
  resp.headers.set('Access-Control-Allow-Origin', origin);
  resp.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  resp.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  resp.headers.set('Vary', 'Origin');
  return resp;
}

function json(obj, status, env) {
  return cors(new Response(JSON.stringify(obj), { status, headers: JSON_HEADERS }), env);
}

function todayKey(prefix, userEmail) {
  const d = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
  return `${prefix}:${userEmail}:${d}`;
}

async function checkAndIncrement(env, key, max) {
  const current = parseInt((await env.USAGE.get(key)) || '0', 10);
  if (current >= max) return { ok: false, current };
  await env.USAGE.put(key, String(current + 1), { expirationTtl: 60 * 60 * 26 });
  return { ok: true, current: current + 1 };
}



function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function configuredBlockedUsers(env) {
  const fromEnv = String((env && env.BLOCKED_USERS) || '')
    .split(',')
    .map(normalizeEmail)
    .filter(Boolean);
  return new Set([...STATIC_BLOCKED_USERS.map(normalizeEmail), ...fromEnv]);
}

async function getKvBlockedUsers(env) {
  const blocked = [];
  if (!env.USAGE) return blocked;
  let cursor;
  do {
    const page = await env.USAGE.list({ prefix: 'blocked-user:', cursor });
    for (const k of page.keys) {
      const email = k.name.slice('blocked-user:'.length);
      if (email) blocked.push(email);
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return blocked.sort();
}

async function isBlockedUser(env, userEmail) {
  const email = normalizeEmail(userEmail);
  if (!email || email.startsWith('service-token:')) return false;
  if (configuredBlockedUsers(env).has(email)) return true;
  if (!env.USAGE) return false;
  const existing = await env.USAGE.get(`blocked-user:${email}`);
  return !!existing;
}

function blockedUserHtml(userEmail) {
  const safeEmail = escapeHtml(userEmail || 'your account');
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Access Blocked</title>
<style>body{margin:0;min-height:100vh;background:#071007;color:#e8f5e9;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:flex;align-items:center;justify-content:center;padding:24px}.card{max-width:620px;width:100%;background:#101b10;border:1px solid #5c1f1f;border-radius:20px;box-shadow:0 20px 80px rgba(0,0,0,.45);padding:28px}h1{margin:0 0 10px;color:#ff8a80;font-size:1.7rem}.sub{color:#d8ead8;line-height:1.5}.email{font-weight:800;color:#fff}.small{font-size:.82rem;color:#8fa38f;margin-top:18px}</style></head>
<body><main class="card"><h1>🔒 Access Blocked</h1><div class="sub">The account <span class="email">${safeEmail}</span> is currently blocked from accessing Pickleball Pro.</div><div class="small">Contact your administrator if you believe this is a mistake.</div></main></body></html>`;
}

async function hasAcceptedLatestTos(env, userEmail) {
  if (!ENFORCE_TOS_ACCEPTANCE) return true;
  if (!userEmail) return false;
  const terms = await getTermsConfig(env);
  const key = `tos-accept:${userEmail}:${terms.version}`;
  const existing = await env.USAGE.get(key);
  if (!existing) return false;
  try {
    const parsed = JSON.parse(existing);
    return parsed && parsed.version === terms.version && !!parsed.acceptedAt;
  } catch {
    return true;
  }
}

function termsGateHtml(userEmail, termsConfig) {
  const safeEmail = escapeHtml(userEmail || 'your account');
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Terms Required</title>
<style>
  body{margin:0;min-height:100vh;background:#071007;color:#e8f5e9;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:flex;align-items:center;justify-content:center;padding:24px}
  .card{max-width:720px;width:100%;background:#101b10;border:1px solid #284028;border-radius:20px;box-shadow:0 20px 80px rgba(0,0,0,.45);padding:28px}
  h1{margin:0 0 8px;color:#c6ff00;font-size:1.7rem}.sub{color:#b6c8b6;margin-bottom:18px;line-height:1.45}.terms{background:#071007;border:1px solid #263926;border-radius:14px;padding:16px;max-height:260px;overflow:auto;white-space:pre-wrap;font-size:.9rem;line-height:1.45;color:#dcebdc}
  label{display:flex;gap:10px;align-items:flex-start;margin:18px 0;color:#f1fff1;font-weight:650}input{margin-top:3px;transform:scale(1.15)}button{width:100%;border:0;border-radius:14px;padding:14px 18px;font-weight:800;font-size:1rem;background:#c6ff00;color:#102000;cursor:pointer}button:disabled{opacity:.45;cursor:not-allowed}.msg{margin-top:12px;min-height:20px;color:#ffcc80}.email{font-weight:800;color:#fff}.small{font-size:.82rem;color:#8fa38f;margin-top:14px;text-align:center}
</style></head><body><main class="card">
<h1>📋 Terms & Conditions</h1>
<div class="sub">Signed in as <span class="email">${safeEmail}</span>. You must accept the current Terms version <b>v${termsConfig.version}</b> before accessing Pickleball Pro.</div>
<div class="terms">${escapeHtml(TERMS_OF_SERVICE_TEXT)}</div>
<label><input id="acceptCheck" type="checkbox" onchange="document.getElementById('acceptBtn').disabled=!this.checked"> <span>I have read and agree to the Terms & Conditions.</span></label>
<button id="acceptBtn" disabled onclick="acceptTerms()">I Accept & Continue</button>
<div id="msg" class="msg"></div><div class="small">Access to the app remains blocked until acceptance is recorded on the server.</div>
<script>
async function acceptTerms(){
  const btn=document.getElementById('acceptBtn'), msg=document.getElementById('msg');
  btn.disabled=true; msg.textContent='Recording acceptance...';
  try{
    const r=await fetch('/api/tos-accept',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({version:'${termsConfig.version}',acceptedAt:new Date().toISOString()})});
    const data=await r.json().catch(()=>({}));
    if(!r.ok||data.ok!==true) throw new Error(data.error||'Acceptance could not be recorded.');
    msg.textContent='Accepted. Opening app...';
    location.href='/';
  }catch(e){
    msg.textContent=e.message||'Could not record acceptance. Please try again.';
    btn.disabled=false;
  }
}
</script></main></body></html>`;
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return cors(new Response(null, { status: 204 }), env);
    }

    const url = new URL(request.url);
    // Normalize away accidental double slashes (some older code paths in
    // the frontend call '//email' etc.) so routing is forgiving.
    const path = url.pathname.replace(/\/{2,}/g, '/');

    // ── Identify the caller via Cloudflare Access ───────────────────────
    // Moved above the GET/POST split so identity is available for BOTH —
    // GET needs it to record a "this approved person visited" marker (used
    // by /admin/tos-status to show who hasn't accepted yet, not just who
    // has); POST already needed it for SMS/email/standings/tos-accept.
    //
    // Two valid identity sources, matching the two policies on this
    // application in the Cloudflare dashboard:
    //   1. A real person logged in via email (one-time-PIN flow) — Access
    //      sets Cf-Access-Authenticated-User-Email for these.
    //   2. The app's own service token, sent as CF-Access-Client-Id /
    //      CF-Access-Client-Secret headers — used for the app's own /api/*
    //      fetch() calls, set as Worker environment variables, server-side
    //      only, never sent to a browser.
    // Either is sufficient; if neither is present, Access either blocked
    // the request before it got here, or something is misconfigured.
    const userEmail = request.headers.get('Cf-Access-Authenticated-User-Email');
    const serviceClientId = request.headers.get('Cf-Access-Client-Id');
    const callerIdentity = userEmail || (serviceClientId ? `service-token:${serviceClientId}` : null);

    // ── Serve the app itself for any GET that isn't an /api/* or /admin/* call ──
    // This Worker now serves both the static app AND the API, on one
    // origin — see project notes on why (Cloudflare Access can't be scoped
    // to a path under the shared pages.dev domain, so a separate Pages
    // deployment + proxy Function couldn't avoid a cross-origin/redirect
    // problem; serving everything from one Worker on coachjohnpickleball.
    // workers.dev sidesteps the issue entirely — one origin, one Access
    // application, no cross-origin fetch() ever happens).
    if (request.method === 'GET' && !path.startsWith('/api/') && !path.startsWith('/admin/')) {
      // Lightweight machine-readable health check some tooling/older code
      // may still ping — kept distinct from serving the full HTML page.
      if (path === '/whoami') {
        const termsConfig = await getTermsConfig(env);
        return json({
          ok: true,
          email: userEmail || '',
          isAdmin: isAdminUser(env, userEmail),
          adminEmails: getAdminEmails(env),
          currentTermsVersion: termsConfig.version,
          termsEffectiveDate: termsConfig.effectiveDate,
          environment: env.ENVIRONMENT || 'production',
        }, 200, env);
      }

      if (path === '/health') {
        return json({
          ok: true,
          service: 'pickleball-pro',
          worker: 'pickleball-relay',
          environment: env.ENVIRONMENT || 'production',
          tosVersion: (await getTermsConfig(env)).version,
          appVersion: APP_VERSION,
          buildDate: BUILD_DATE,
          termsEffectiveDate: (await getTermsConfig(env)).effectiveDate,
          tosEnforced: ENFORCE_TOS_ACCEPTANCE,
          timestamp: new Date().toISOString(),
          checks: {
            appHtmlLoaded: Boolean(APP_HTML),
            usageKvBound: Boolean(env.USAGE),
            smsLimitConfigured: Boolean(env.MAX_SMS_PER_DAY),
            emailLimitConfigured: Boolean(env.MAX_EMAIL_PER_DAY),
          }
        }, 200, env);
      }
      // Full Terms of Service text, linked from the in-app acceptance gate.
      // Plain text rather than the app's styling — this needs to be
      // readable/quotable on its own, independent of the app shell.
      if (path === '/terms') {
        return new Response(TERMS_OF_SERVICE_TEXT, {
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      // ── Force a fresh Access login on every genuine new visit ─────────
      // Cloudflare Access's own session is server-side and time-based
      // (shortest is 15 minutes) — it has no concept of "the browser tab
      // was closed", so on its own it cannot guarantee re-login every
      // single time someone reopens the app. This adds that guarantee
      // directly: a short-lived "fresh-visit" cookie, scoped to this exact
      // page load, distinguishes "the SAME page is still open and just
      // re-rendering" from "this is a genuinely new visit" (new tab,
      // reopened tab, browser restart, link from elsewhere, etc).
      //
      //   - Cookie present  → same continuous visit, not a real new one →
      //     serve the app normally, no redirect loop.
      //   - Cookie absent   → genuine new visit → redirect through
      //     Access's own /cdn-cgi/access/logout, which clears its session
      //     cookie and forces the login challenge on the very next request
      //     for this app, regardless of how much time is left on the
      //     15-minute Access session.
      //
      // freshVisit=1 on the redirect target tells the NEXT request (the
      // one Access sends the browser to after logout+relogin) to skip
      // this check and set the marker cookie instead of looping again.
      const freshVisitCookiePresent = (request.headers.get('Cookie') || '')
        .split(';').some(c => c.trim().startsWith('pb_fresh_visit='));
      const skipForceLogin = url.searchParams.get('freshVisit') === '1';

      if (FORCE_RELOGIN_EVERY_VISIT && !freshVisitCookiePresent && !skipForceLogin) {
        const returnTo = new URL(request.url);
        returnTo.searchParams.set('freshVisit', '1');
        return Response.redirect(
          `https://${url.hostname}/cdn-cgi/access/logout?returnTo=${encodeURIComponent(returnTo.toString())}`,
          302
        );
      }

      // Record that this verified, approved person visited the app — not
      // tied to whether they've accepted the Terms yet. This is what lets
      // /admin/tos-status show "approved but never even reached the
      // gate" as distinct from "reached it but hasn't clicked Accept",
      // versus "accepted". Best-effort: never blocks serving the page.
      //
      // Separately, record a per-day login entry for /admin/login-log.
      // Keyed by {email}:{date}, so repeat visits the same day land on
      // the same key — this is what gives "first login of the day"
      // granularity. We check-then-write rather than writing unconditionally
      // on every page load, so a person refreshing the app fifty times in
      // an afternoon costs one KV write for the day, not fifty.
      // expirationTtl rolls each day's entry off automatically after 90
      // days, so the log doesn't grow forever either.
      if (userEmail) {
        const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD, UTC
        const nowIso = new Date().toISOString();
        // CF-Connecting-IP is set by Cloudflare's own edge, not something a
        // client can spoof — request.cf.country is similarly derived from
        // Cloudflare's own geolocation of that IP, not a client-supplied
        // header. Both can legitimately be absent in local/dev requests
        // that don't go through Cloudflare's network at all.
        const ip = request.headers.get('CF-Connecting-IP') || null;
        const country = (request.cf && request.cf.country) || null;
        // User-Agent IS client-supplied (unlike the two above) — a browser
        // sends whatever string it wants here, so treat this as informative
        // rather than as a verified fact the way IP/country are.
        const userAgent = request.headers.get('User-Agent') || null;
        // This code path only runs for a verified Cf-Access-Authenticated-
        // User-Email — the app's own service-token calls (used for its
        // internal /api/* fetches) never reach this branch at all, so
        // "accessMethod" isn't really ambiguous here; recorded as a fixed
        // label rather than inferred, since there's nothing to infer.
        const accessMethod = 'email-login';
        ctx.waitUntil(
          env.USAGE.put(`tos-seen:${userEmail}`, JSON.stringify({ lastSeenAt: nowIso })).catch(() => {})
        );
        const loginKey = `login:${userEmail}:${today}`;
        ctx.waitUntil(
          env.USAGE.get(loginKey).then((existing) => {
            if (existing) return; // already logged today — don't overwrite the original first-login timestamp
            return env.USAGE.put(
              loginKey,
              JSON.stringify({
                email: userEmail,
                date: today,
                firstLoginAt: nowIso,
                ip,
                country,
                userAgent,
                path,
                accessMethod,
                eventType: 'first-login-of-day',
              }),
              { expirationTtl: 60 * 60 * 24 * 90 } // 90 days
            );
          }).catch(() => {})
        );
        // Detailed access event: record every verified app visit, not just
        // the first login of the day. This is what makes the Access Log show
        // activity from today immediately, instead of only one daily summary.
        const eventId = (crypto && crypto.randomUUID) ? crypto.randomUUID() : String(Math.random()).slice(2);
        ctx.waitUntil(
          env.USAGE.put(
            `access-event:${nowIso}:${eventId}`,
            JSON.stringify({
              email: userEmail,
              at: nowIso,
              date: today,
              ip,
              country,
              userAgent,
              path,
              accessMethod,
              eventType: 'app-visit',
              ray: request.headers.get('CF-Ray') || null,
            }),
            { expirationTtl: 60 * 60 * 24 * 90 }
          ).catch(() => {})
        );
        // Email alert on every login — see LOGIN_ALERT_EMAIL and
        // sendLoginAlertEmail() below for what this actually sends and why
        // it's a SEPARATE path from the customer-facing /api/email handler
        // (different purpose: a fixed admin notification, not a
        // user-initiated send, so it shouldn't count against anyone's
        // daily email quota or require the to/subject/html fields that
        // handler expects).
        ctx.waitUntil(
          sendLoginAlertEmail(env, { email: userEmail, date: today, firstLoginAt: nowIso, ip, country, userAgent })
            .catch(() => {}) // never let an alert-email failure affect the actual page load
        );
      }
      // The marker cookie itself: short-lived (60s is generous for a page
      // to finish loading, short enough that walking away and coming back
      // still counts as a fresh visit), HttpOnly (not readable/forgeable
      // from page JS), and scoped to this path. Only set while the
      // feature is actually on — no point setting a cookie nothing checks.
      const headers = new Headers({ 'Content-Type': 'text/html; charset=utf-8' });
      if (FORCE_RELOGIN_EVERY_VISIT) {
        headers.append('Set-Cookie', 'pb_fresh_visit=1; Max-Age=60; Path=/; HttpOnly; Secure; SameSite=Lax');
      }
      const termsConfig = await getTermsConfig(env);
      if (userEmail && await isBlockedUser(env, userEmail)) {
        return new Response(blockedUserHtml(userEmail), { status: 403, headers });
      }
      if (ENFORCE_TOS_ACCEPTANCE && userEmail && !(await hasAcceptedLatestTos(env, userEmail))) {
        return new Response(termsGateHtml(userEmail, termsConfig), { headers });
      }
      return new Response(appHtmlForUser(APP_HTML, env, userEmail, termsConfig), { headers });
    }

    // ── Admin: Terms of Service acceptance status ───────────────────────
    // Read-only HTML report, restricted to the admin email(s) configured
    // below. Reachable at GET /admin/tos-status while logged in through
    // the same Cloudflare Access gate as the rest of the app — there's no
    // separate password, the restriction is purely "is this the approved
    // admin's verified email".
    if (request.method === 'GET' && path === '/admin/tos-status') {
      return handleAdminTosStatus(env, userEmail);
    }

    if ((request.method === 'GET' || request.method === 'POST') && path === '/admin/users') {
      return handleAdminUsers(request, env, userEmail);
    }

    if ((request.method === 'GET' || request.method === 'POST') && path === '/admin/terms-settings') {
      return handleAdminTermsSettings(request, env, userEmail);
    }

    // ── Admin: login history ─────────────────────────────────────────
    // Same admin-only restriction as above. Shows who logged in, and
    // when, going back up to 90 days (records auto-expire after that —
    // see the write site above for why).
    
    // PB_ACCESS_LOG_DELETE_MATCHING_POST_V1
    if (request.method === 'POST' && path === '/admin/access-log/delete-matching') {
      // PB_ACCESS_LOG_DELETE_AUTH_FIX_V2
      const deleteAdminEmail = String(
        userEmail ||
        request.headers.get('cf-access-authenticated-user-email') ||
        request.headers.get('cf-access-jwt-assertion-email') ||
        ''
      ).trim().toLowerCase();

      const envAdminEmails = String(env.ADMIN_EMAILS || '')
        .split(',')
        .map(e => e.trim().toLowerCase())
        .filter(Boolean);

      const adminOk =
        (typeof isAdminUser === 'function' && isAdminUser(env, deleteAdminEmail)) ||
        (typeof isAdminEmail === 'function' && isAdminEmail(deleteAdminEmail, env)) ||
        envAdminEmails.includes(deleteAdminEmail);

      if (!adminOk) {
        return new Response(
          'Forbidden: admin only. Detected email: ' + (deleteAdminEmail || 'none') + '. ADMIN_EMAILS: ' + envAdminEmails.join(', '),
          {
            status: 403,
            headers: { 'Content-Type': 'text/plain; charset=utf-8' }
          }
        );
      }

      const form = await request.formData().catch(() => null);

      if (!form) {
        return new Response('Invalid form submission.', {
          status: 400,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' }
        });
      }

      const q = String(form.get('q') || '').trim().toLowerCase();
      const daysRaw = parseInt(String(form.get('days') || '90'), 10);
      const days = Number.isFinite(daysRaw) ? Math.max(1, Math.min(90, daysRaw)) : 90;
      const country = String(form.get('country') || '').trim().toLowerCase();
      const device = String(form.get('device') || '').trim().toLowerCase();
      const confirmText = String(form.get('confirm') || '').trim();

      const hasFilter = !!q || days < 90 || !!country || !!device;

      const backParams = new URLSearchParams();
      if (q) backParams.set('q', q);
      if (days) backParams.set('days', String(days));
      if (country) backParams.set('country', country.toUpperCase());
      if (device) backParams.set('device', device);

      const backHref = '/admin/access-log' + (backParams.toString() ? '?' + backParams.toString() : '');

      function htmlPage(title, body, status) {
        return new Response(
          '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
          '<title>' + escapeHtml(title) + '</title>' +
          '<style>body{font-family:system-ui;background:#0f172a;color:#fff;padding:24px}.card{max-width:860px;margin:auto;background:#111827;border:1px solid #334155;border-radius:18px;padding:22px}.ok{color:#C6FF00;font-weight:900}.warn{color:#FFD54F}.muted{color:#cbd5e1}.btn{display:inline-block;margin-top:14px;padding:10px 14px;border-radius:12px;background:#C6FF00;color:#111;text-decoration:none;font-weight:900}code{background:#020617;border:1px solid #334155;border-radius:8px;padding:2px 6px}</style>' +
          '</head><body><main class="card">' + body +
          '<a class="btn" href="' + escapeHtml(backHref) + '">Back to Access Log</a>' +
          '</main></body></html>',
          {
            status: status || 200,
            headers: { 'Content-Type': 'text/html; charset=utf-8' }
          }
        );
      }

      if (confirmText !== 'DELETE') {
        return htmlPage(
          'Delete cancelled',
          '<h1>Delete cancelled</h1><p>You must type <code>DELETE</code> exactly.</p>',
          400
        );
      }

      if (!hasFilter) {
        return htmlPage(
          'Delete cancelled',
          '<h1>Delete cancelled</h1><p class="warn">Apply at least one filter before deleting logs.</p><p>Use Search, Days less than 90, Country, or Device contains.</p>',
          400
        );
      }

      const cutoffMs = Date.now() - days * 24 * 60 * 60 * 1000;

      function parseRecord(raw) {
        try {
          return raw ? JSON.parse(raw) : {};
        } catch (err) {
          return {};
        }
      }

      function getRecordTimeMs(keyName, obj) {
        const values = [
          obj.at,
          obj.createdAt,
          obj.timestamp,
          obj.time,
          obj.date,
          obj.day,
          keyName
        ];

        for (const value of values) {
          const text = String(value || '');
          const match = text.match(/\d{4}-\d{2}-\d{2}(?:T[0-9:.+\-Z]*)?/);

          if (match) {
            const d = new Date(match[0]);
            if (!Number.isNaN(d.getTime())) return d.getTime();
          }

          const d = new Date(text);
          if (!Number.isNaN(d.getTime())) return d.getTime();
        }

        return 0;
      }

      function searchableText(keyName, raw, obj) {
        return [
          keyName,
          raw,
          obj.email,
          obj.user,
          obj.userEmail,
          obj.ip,
          obj.country,
          obj.countryCode,
          obj.userAgent,
          obj.device,
          obj.path,
          obj.url,
          obj.event,
          obj.type,
          obj.status
        ].map(v => String(v || '')).join(' ').toLowerCase();
      }

      function matchesFilters(keyName, raw) {
        const obj = parseRecord(raw);
        const timeMs = getRecordTimeMs(keyName, obj);

        if (!timeMs || timeMs < cutoffMs) return false;

        const text = searchableText(keyName, raw, obj);

        if (q && !text.includes(q)) return false;
        if (country && !text.includes(country)) return false;
        if (device && !text.includes(device)) return false;

        return true;
      }

      const matches = [];
      let cursor = undefined;

      do {
        const listed = await env.USAGE.list({ prefix: 'access-event:', cursor });
        cursor = listed.cursor;

        for (const key of listed.keys || []) {
          const raw = await env.USAGE.get(key.name);

          if (matchesFilters(key.name, raw || '')) {
            matches.push({
              key: key.name,
              raw: raw || ''
            });
          }
        }
      } while (cursor);

      if (!matches.length) {
        return htmlPage(
          'No matching logs',
          '<h1>No matching logs found</h1><p>No access-event logs matched the current filters.</p>',
          200
        );
      }

      const now = new Date().toISOString();

      try {
        await env.USAGE.put('access-log-delete-backup:' + now, JSON.stringify({
          createdAt: now,
          deletedBy: userEmail,
          filters: { q, days, country, device },
          count: matches.length,
          records: matches.slice(0, 5000)
        }));
      } catch (err) {}

      const deleted = [];
      const failed = [];

      for (const item of matches) {
        try {
          await env.USAGE.delete(item.key);
          deleted.push(item.key);
        } catch (err) {
          failed.push(item.key);
        }
      }

      try {
        await env.USAGE.put('access-log-delete-audit:' + now, JSON.stringify({
          deletedAt: now,
          deletedBy: userEmail,
          filters: { q, days, country, device },
          matchedCount: matches.length,
          deletedCount: deleted.length,
          failedCount: failed.length
        }));
      } catch (err) {}

      return htmlPage(
        'Matching logs deleted',
        '<h1>Matching Access Log records deleted</h1>' +
        '<p class="ok">Deleted ' + deleted.length + ' matching access-event log(s).</p>' +
        (failed.length ? '<p class="warn">Failed to delete ' + failed.length + ' log(s).</p>' : '') +
        '<p class="muted">Filters used:<br>' +
        'Search: <code>' + escapeHtml(q || 'none') + '</code><br>' +
        'Days: <code>' + escapeHtml(String(days)) + '</code><br>' +
        'Country: <code>' + escapeHtml(country || 'all') + '</code><br>' +
        'Device: <code>' + escapeHtml(device || 'any') + '</code></p>' +
        '<p class="muted">A backup and audit record were saved in KV.</p>',
        200
      );
    }

    if (request.method === 'GET' && (path === '/admin/login-log' || path === '/admin/access-log')) {
      return handleAdminLoginLog(env, userEmail, url);
    }

    // ── DUPR ID map: GET (read) is open to any verified Access login, same
    // as everything else in this app — no admin restriction, since this is
    // ordinary tournament-running data, not an admin report.
    if (request.method === 'GET' && path === '/api/dupr-ids') {
      if (!callerIdentity) {
        return json({ ok: false, error: 'Unauthorized — no verified Access identity on request' }, 401, env);
      }
      if (userEmail && await isBlockedUser(env, userEmail)) {
        return json({ ok: false, error: 'Access blocked for this user' }, 403, env);
      }
      const tournament = url.searchParams.get('tournament') || '(untitled)';
      return handleGetDuprIds(env, tournament);
    }

    if (request.method !== 'POST') {
      return json({ ok: false, error: 'Method not allowed' }, 405, env);
    }

    if (!callerIdentity) {
      return json({ ok: false, error: 'Unauthorized — no verified Access identity on request' }, 401, env);
    }
    if (userEmail && await isBlockedUser(env, userEmail)) {
      return json({ ok: false, error: 'Access blocked for this user' }, 403, env);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ ok: false, error: 'Invalid JSON' }, 400, env);
    }

    if (path === '/api/sms') {
      return handleSms(body, env, callerIdentity);
    }
    if (path === '/api/email') {
      return handleEmail(body, env, callerIdentity);
    }
    if (path === '/api/standings') {
      return handleStandings(body, env, callerIdentity);
    }
    if (path === '/api/tos-accept') {
      return handleTosAccept(body, env, callerIdentity);
    }
    if (path === '/api/dupr-ids') {
      return handleSaveDuprIds(body, env, callerIdentity);
    }
    return json({ ok: false, error: 'Not found' }, 404, env);
  },
};

// ── Admin: who has / hasn't accepted the Terms ──────────────────────────
// Restricted to the email(s) listed in ADMIN_EMAILS below — edit this list
// to add yourself or any co-admin. This check is independent of Cloudflare
// Access's own login (Access still verifies the person is who they claim
// to be); this is an additional "and are they specifically an admin"
// check on top of that, since every approved Customer can reach Access,
// but not every Customer should see everyone else's acceptance status.
const ADMIN_EMAILS = ['coachjohnpickleball@gmail.com'];

// ── Login alert email — on/off switch + destination ─────────────────────
// When LOGIN_ALERT_ENABLED is true, every login (not just the first of the
// day — every single one) sends a short notification email here. This is
// deliberately verbose by request — be aware it can mean several emails
// in quick succession during an active tournament if scorekeepers are
// opening/closing the app on their phones. Set to false to pause without
// removing the feature; see sendLoginAlertEmail() below for what's sent.
const LOGIN_ALERT_ENABLED = true;
const LOGIN_ALERT_EMAIL = 'coachjohnpickleball@gmail.com';

async function handleAdminTosStatus(env, userEmail) {
  const terms = await getTermsConfig(env);
  if (!isAdminUser(env, userEmail)) {
    return new Response('Not authorized.', { status: 403, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }

  // KV's list() returns keys page by page (1000 max per call) — loop until
  // there's no cursor left. A real tournament app's customer count is
  // small (dozens, not millions), so this stays well within Workers'
  // per-request time/subrequest limits even unpaginated by the caller.
  async function listAll(prefix) {
    const out = [];
    let cursor;
    do {
      const page = await env.USAGE.list({ prefix, cursor });
      out.push(...page.keys);
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    return out;
  }

  const [seenKeys, acceptKeys] = await Promise.all([
    listAll('tos-seen:'),
    listAll('tos-accept:'),
  ]);

  // tos-seen:{email} → last visit. tos-accept:{email}:{version} → one
  // entry per (person, version) ever accepted — collapse to each person's
  // most recent acceptance for the report.
  const seenByEmail = {};
  for (const k of seenKeys) {
    const email = k.name.slice('tos-seen:'.length);
    seenByEmail[email] = true;
  }

  const acceptByEmail = {};
  for (const k of acceptKeys) {
    const rest = k.name.slice('tos-accept:'.length);
    const lastColon = rest.lastIndexOf(':');
    const email = rest.slice(0, lastColon);
    const value = await env.USAGE.get(k.name);
    let parsed = null;
    try { parsed = JSON.parse(value); } catch (e) {}
    if (!parsed) continue;
    const existing = acceptByEmail[email];
    if (!existing || parsed.acceptedAt > existing.acceptedAt) {
      acceptByEmail[email] = parsed;
    }
  }

  const blockedUsers = new Set([...(await getKvBlockedUsers(env)), ...configuredBlockedUsers(env)]);
  const allEmails = [...new Set([...Object.keys(seenByEmail), ...Object.keys(acceptByEmail), ...blockedUsers])].sort();

  const rows = allEmails.map((email) => {
    const accepted = acceptByEmail[email];
    const everSeen = !!seenByEmail[email];
    const status = blockedUsers.has(normalizeEmail(email))
      ? { label: '⛔ Blocked by admin', color: '#FF8A80', detail: 'App-level access is blocked. Cloudflare Access may also need a matching Block policy.' }
      : accepted && accepted.version === terms.version
        ? { label: '✓ Accepted current terms', color: '#2E7D32', detail: `Accepted v${accepted.version} — ${accepted.acceptedAt}` }
        : accepted
          ? { label: '🔒 Needs reacceptance', color: '#F9A825', detail: `Accepted v${accepted.version}; current version is v${terms.version}. Access blocked until accepted.` }
          : everSeen
            ? { label: '🔒 Pending acceptance', color: '#C62828', detail: `Must accept v${terms.version} before app access is allowed` }
            : { label: '— Unknown', color: '#888', detail: '' };
    return { email, status };
  });

  const acceptedCount = rows.filter(r => r.status.label.startsWith('✓')).length;
  const pendingCount = rows.filter(r => !r.status.label.startsWith('✓')).length;

  const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Terms of Service — Acceptance Status</title>
<style>
  body { font-family: -apple-system, sans-serif; background: #0A0F0A; color: #E8F5E9; padding: 2rem; max-width: 900px; margin: 0 auto; }
  h1 { color: #C6FF00; font-size: 1.4rem; }
  .summary { display: flex; gap: 1.5rem; margin: 1rem 0 1.5rem; font-size: 0.9rem; }
  .summary span { background: #1E271E; border: 1px solid #2E3D2E; border-radius: 8px; padding: 0.5rem 1rem; }
  table { width: 100%; border-collapse: collapse; font-size: 0.88rem; }
  th { text-align: left; background: #1B5E20; color: #C6FF00; padding: 0.6rem 0.8rem; }
  td { padding: 0.55rem 0.8rem; border-bottom: 1px solid #2E3D2E; }
  .empty { color: #66BB6A; padding: 2rem 0; text-align: center; }
</style></head>
<body>
  <h1>📋 Terms & Conditions — Acceptance Status</h1><p><a style="color:#C6FF00" href="/admin/users">Manage blocked users</a> · <a style="color:#C6FF00" href="/admin/terms-settings">Terms settings</a> · <a style="color:#C6FF00" href="/admin/access-log">Access log</a></p>
  <div style="color:#b6c8b6;margin-bottom:1rem">Current terms version: <b style="color:#c6ff00">v${terms.version}</b> · Effective: ${terms.effectiveDate} · App ${APP_VERSION} · Build ${BUILD_DATE}</div>
  <div class="summary">
    <span>✓ ${acceptedCount} accepted</span>
    <span>🔒 ${pendingCount} blocked / needs acceptance</span>
    <span>${allEmails.length} total known</span>
  </div>
  ${pendingCount ? `<div style="background:#3a1515;border:1px solid #c62828;color:#ffebee;border-radius:10px;padding:0.75rem 1rem;margin-bottom:1rem;font-weight:700">⚠️ ${pendingCount} user(s) are blocked until they accept v${terms.version}.</div>` : ''}
  ${allEmails.length === 0 ? '<div class="empty">No one has visited the app yet under this tracking.</div>' : `
  <table>
    <thead><tr><th>Email</th><th>Status</th><th>Detail</th></tr></thead>
    <tbody>
      ${rows.map(r => `<tr><td>${escapeHtml(r.email)}</td><td style="color:${r.status.color};font-weight:700">${r.status.label}</td><td style="color:#888;font-size:0.82rem">${escapeHtml(r.status.detail)}</td></tr>`).join('')}
    </tbody>
  </table>`}
  <p style="color:#555;font-size:0.78rem;margin-top:2rem">
    Users with old or missing acceptance are blocked by the Worker before the application loads. Cloudflare Access still controls the front door; this Terms gate controls in-app authorization.
  </p>
</body></html>`;

  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}


async function handleAdminUsers(request, env, userEmail) {
  const terms = await getTermsConfig(env);
  if (!isAdminUser(env, userEmail)) {
    return new Response('Not authorized.', { status: 403, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }

  let message = '';
  if (request.method === 'POST') {
    const form = await request.formData();
    const action = String(form.get('action') || '');
    const email = normalizeEmail(form.get('email'));
    if (!email) {
      message = 'Email is required.';
    } else if (action === 'block') {
      await env.USAGE.put(`blocked-user:${email}`, JSON.stringify({ email, blockedAt: new Date().toISOString(), blockedBy: userEmail }));
      message = `${email} is now blocked.`;
    } else if (action === 'unblock') {
      await env.USAGE.delete(`blocked-user:${email}`);
      message = `${email} was removed from the app-level block list.`;
    } else if (action === 'reset-terms') {
      await deleteUserTermsAcceptances(env, email);
      message = `${email} must accept the current Terms again.`;
    } else {
      message = 'Unknown action.';
    }
  }

  const kvBlocked = await getKvBlockedUsers(env);
  const configured = Array.from(configuredBlockedUsers(env)).sort();
  const blockedRows = [...new Set([...configured, ...kvBlocked])].sort().map((email) => {
    const source = configured.includes(email) && kvBlocked.includes(email) ? 'wrangler/env + admin' : configured.includes(email) ? 'wrangler/env' : 'admin';
    const canUnblockHere = kvBlocked.includes(email);
    return `<tr><td>${escapeHtml(email)}</td><td>${escapeHtml(source)}</td><td>${canUnblockHere ? `<form method="POST" style="margin:0"><input type="hidden" name="email" value="${escapeHtml(email)}"><button name="action" value="unblock">Unblock</button></form>` : '<span class="muted">Edit wrangler.toml / env var</span>'}</td></tr>`;
  }).join('');

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>User Access Control</title>
<style>body{font-family:-apple-system,sans-serif;background:#0A0F0A;color:#E8F5E9;padding:2rem;max-width:950px;margin:0 auto}h1{color:#C6FF00}.card{background:#111b11;border:1px solid #2E3D2E;border-radius:14px;padding:1rem;margin:1rem 0}.msg{background:#102310;border:1px solid #2E7D32;color:#C8E6C9;border-radius:10px;padding:.75rem;margin:.75rem 0}label{display:block;color:#b6c8b6;font-size:.8rem;margin-bottom:.25rem}input{background:#071007;color:#fff;border:1px solid #2E3D2E;border-radius:9px;padding:.6rem;min-width:290px}button{background:#1B5E20;color:white;border:1px solid #2E7D32;border-radius:9px;padding:.55rem .8rem;font-weight:700;cursor:pointer}.danger{background:#8B1E1E;border-color:#C62828}.secondary{background:#263238;border-color:#455A64}table{width:100%;border-collapse:collapse;font-size:.9rem}th{text-align:left;background:#1B5E20;color:#C6FF00;padding:.65rem}td{border-bottom:1px solid #2E3D2E;padding:.6rem}.muted{color:#8fa38f;font-size:.82rem}.hint{color:#b6c8b6;line-height:1.45}.row{display:flex;gap:.5rem;align-items:end;flex-wrap:wrap}</style></head><body>
<h1>🔐 User Access Control</h1>
<div class="hint">Use this page for app-level access control. For front-door blocking, still use Cloudflare Zero Trust Access policies. To block everyone until they reaccept, change <b>CURRENT_TERMS_VERSION / TOS_VERSION</b> and redeploy.</div>
${message ? `<div class="msg">${escapeHtml(message)}</div>` : ''}
<div class="card"><h2>Block one user</h2><form method="POST" class="row"><div><label>Email</label><input name="email" type="email" required placeholder="user@example.com"></div><button class="danger" name="action" value="block">Block User</button><button class="secondary" name="action" value="reset-terms">Force Terms Reacceptance</button></form></div>
<div class="card"><h2>Currently blocked users</h2>${blockedRows ? `<table><thead><tr><th>Email</th><th>Source</th><th>Action</th></tr></thead><tbody>${blockedRows}</tbody></table>` : '<div class="muted">No app-level blocked users.</div>'}</div>
<div class="card"><h2>Block all users</h2><div class="hint">Current terms version: <b>v${terms.version}</b>. Use <a style="color:#C6FF00" href="/admin/terms-settings">Terms Settings</a> to change it; every user will be blocked until they accept the new version.</div></div>
<p class="muted"><a style="color:#C6FF00" href="/admin/tos-status">Terms status</a> · <a style="color:#C6FF00" href="/admin/terms-settings">Terms settings</a> · <a style="color:#C6FF00" href="/admin/access-log">Access log</a></p>
</body></html>`;
  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}

async function deleteUserTermsAcceptances(env, email) {
  let cursor;
  do {
    const page = await env.USAGE.list({ prefix: `tos-accept:${email}:`, cursor });
    await Promise.all(page.keys.map(k => env.USAGE.delete(k.name)));
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
}

// Lightweight, best-effort summary of a User-Agent string into something
// readable like "Chrome on macOS" or "Safari on iPhone" — deliberately NOT
// a full device-detection library (those need constant maintenance as new
// browsers/OSes ship); good enough for "does this look like the device
// this person normally uses" at a glance, not meant to be authoritative.
function summarizeUserAgent(ua) {
  if (!ua) return '—';
  let browser = 'Unknown browser';
  if (/Edg\//.test(ua)) browser = 'Edge';
  else if (/OPR\//.test(ua)) browser = 'Opera';
  else if (/Chrome\//.test(ua) && !/Chromium/.test(ua)) browser = 'Chrome';
  else if (/CriOS\//.test(ua)) browser = 'Chrome (iOS)';
  else if (/FxiOS\//.test(ua)) browser = 'Firefox (iOS)';
  else if (/Firefox\//.test(ua)) browser = 'Firefox';
  else if (/Safari\//.test(ua) && /Version\//.test(ua)) browser = 'Safari';

  let os = '';
  if (/iPhone/.test(ua)) os = 'iPhone';
  else if (/iPad/.test(ua)) os = 'iPad';
  else if (/Android/.test(ua)) os = 'Android';
  else if (/Macintosh|Mac OS X/.test(ua)) os = 'macOS';
  else if (/Windows/.test(ua)) os = 'Windows';
  else if (/Linux/.test(ua)) os = 'Linux';

  return os ? `${browser} on ${os}` : browser;
}

// ── Login alert email ────────────────────────────────────────────────
// Sends a short notification to LOGIN_ALERT_EMAIL via the same Brevo path
// as the customer-facing /api/email handler, but as its own dedicated
// function rather than calling that handler — this is a fixed, internal
// admin notification (not a user-initiated send), so it deliberately does
// NOT go through that handler's daily usage quota or its to/subject/html
// request-body validation, which are meant for a different use case.
//
// Best-effort and silent on failure by design: a login alert email
// failing to send must never block, slow down, or error out the actual
// page load for the person logging in. The caller wraps this in
// ctx.waitUntil(...).catch(() => {}) for exactly that reason.
async function sendLoginAlertEmail(env, info) {
  if (!LOGIN_ALERT_ENABLED) return;
  if (!env.BREVO_API_KEY || !env.SMTP_FROM) return; // misconfigured — fail silently, don't break login

  const deviceSummary = summarizeUserAgent(info.userAgent);
  const subject = `🔑 Login: ${info.email}`;
  const html = `
    <div style="font-family:-apple-system,sans-serif;padding:1.5rem;color:#222">
      <h2 style="color:#1B5E20;margin:0 0 1rem">🔑 New login to Pickleball Pro</h2>
      <table style="border-collapse:collapse;font-size:0.92rem">
        <tr><td style="padding:4px 12px 4px 0;color:#666">Email</td><td style="padding:4px 0;font-weight:600">${escapeHtml(info.email)}</td></tr>
        <tr><td style="padding:4px 12px 4px 0;color:#666">Time (UTC)</td><td style="padding:4px 0">${escapeHtml(info.firstLoginAt)}</td></tr>
        <tr><td style="padding:4px 12px 4px 0;color:#666">IP</td><td style="padding:4px 0;font-family:monospace">${escapeHtml(info.ip || '—')}</td></tr>
        <tr><td style="padding:4px 12px 4px 0;color:#666">Country</td><td style="padding:4px 0">${escapeHtml(info.country || '—')}</td></tr>
        <tr><td style="padding:4px 12px 4px 0;color:#666">Device</td><td style="padding:4px 0">${escapeHtml(deviceSummary)}</td></tr>
      </table>
      <p style="font-size:0.78rem;color:#999;margin-top:1.5rem">Sent automatically on every login. Full history: /admin/login-log</p>
    </div>`;

  try {
    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': env.BREVO_API_KEY,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        sender: { email: env.SMTP_FROM, name: env.SMTP_FROM_NAME || 'Pickleball Pro' },
        to: [{ email: LOGIN_ALERT_EMAIL }],
        subject,
        htmlContent: html,
      }),
    });
  } catch (e) {
    // Swallow — see function comment above. The caller also catches, this
    // is belt-and-suspenders so a network error here is truly never visible
    // to the person logging in.
  }
}


async function handleAdminTermsSettings(request, env, userEmail) {
  if (!isAdminUser(env, userEmail)) {
    return new Response('Forbidden: admin only', { status: 403, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }
  let terms = await getTermsConfig(env);
  let message = '';
  if (request.method === 'POST') {
    const form = await request.formData();
    const version = normalizeVersion(form.get('version'));
    const effectiveDate = String(form.get('effectiveDate') || '').trim() || terms.effectiveDate;
    if (!version) {
      message = '<div class="alert bad">Version is required.</div>';
    } else {
      terms = { version, effectiveDate };
      await env.USAGE.put('config:terms', JSON.stringify({ ...terms, updatedAt: new Date().toISOString(), updatedBy: userEmail }));
      message = '<div class="alert good">Terms version updated. Users who have not accepted <b>v' + escapeHtml(version) + '</b> are now blocked until they accept.</div>';
    }
  }
  const nextSuggestion = suggestNextTermsVersion(terms.version);
  return new Response(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Terms Settings</title>
<style>body{margin:0;background:#071007;color:#e8f5e9;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;padding:24px}.wrap{max-width:860px;margin:auto}.card{background:#101b10;border:1px solid #263926;border-radius:16px;padding:18px;margin:14px 0}h1{color:#c6ff00;margin:0 0 8px}.hint{color:#b6c8b6;line-height:1.5}.row{display:flex;gap:12px;flex-wrap:wrap;align-items:end}label{display:block;color:#b6c8b6;font-size:.85rem;margin-bottom:6px}input{background:#071007;border:1px solid #355035;border-radius:10px;color:#fff;padding:10px;min-width:220px}button,.btn{background:#c6ff00;color:#102010;border:0;border-radius:10px;padding:11px 14px;font-weight:800;text-decoration:none;display:inline-block}.secondary{background:#263926;color:#e8f5e9}.alert{padding:12px 14px;border-radius:12px;margin:12px 0}.good{background:#143d1b;border:1px solid #2e7d32}.bad{background:#3d1414;border:1px solid #c62828}.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}</style></head><body><main class="wrap">
<h1>📄 Terms Settings</h1><div class="hint">Changing the current Terms version blocks everyone who has not accepted that exact version. This is the cleanest way to force all users to reaccept.</div>
${message}
<div class="card"><h2>Current agreement</h2><p>Current Terms Version: <b style="color:#c6ff00">v${escapeHtml(terms.version)}</b></p><p>Effective Date: <b>${escapeHtml(terms.effectiveDate)}</b></p></div>
<div class="card"><h2>Change Terms version</h2><form method="POST" class="row"><div><label>New Terms Version</label><input name="version" required value="${escapeHtml(nextSuggestion)}"></div><div><label>Effective Date</label><input name="effectiveDate" value="${escapeHtml(terms.effectiveDate)}"></div><button type="submit">Update & Force Reacceptance</button></form><p class="hint">Example: change <span class="mono">${escapeHtml(terms.version)}</span> to <span class="mono">${escapeHtml(nextSuggestion)}</span>. Do not include the leading “v” in the stored version; the app displays it automatically.</p></div>
<p><a class="btn secondary" href="/admin/tos-status">Terms status</a> <a class="btn secondary" href="/admin/users">User access</a> <a class="btn secondary" href="/admin/access-log">Access log</a></p>
</main></body></html>`, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}

function normalizeVersion(v) {
  return String(v || '').trim().replace(/^v/i, '').replace(/[^0-9A-Za-z._-]/g, '');
}

function suggestNextTermsVersion(version) {
  const v = normalizeVersion(version);
  const m = v.match(/^(\d{4}-\d{2}-\d{2})(?:\.(\d+))?$/);
  if (m) return m[1] + '.' + String((Number(m[2] || '0') + 1));
  return v ? v + '.1' : '2026-06-24.1';
}

// ── Admin: login history ─────────────────────────────────────────────
// Reads every login:{email}:{date} key (see the write site in the GET
// handler above) and renders a simple table, most recent first. Each
// entry is one person's FIRST login of a given day — not every page
// load — by design, so a person actively using the app all afternoon
// shows up once for that day, not dozens of times.
async function handleAdminLoginLog(env, userEmail, url) {
  if (!isAdminUser(env, userEmail)) {
    return new Response('Not authorized.', { status: 403, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }

  async function listAll(prefix) {
    const out = [];
    let cursor;
    do {
      const page = await env.USAGE.list({ prefix, cursor });
      out.push(...page.keys);
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    return out;
  }

  // Read BOTH detailed access events and older daily login summaries.
  // Previous builds used daily summaries first, then switched to detailed
  // access-event records. If we only read one prefix, the admin page appears
  // to lose history. Merge both, then de-duplicate daily summaries when a
  // detailed event for the same person/day already exists.
  const eventKeys = await listAll('access-event:');
  const dailyKeys = await listAll('login:');
  const eventRecords = (await Promise.all(eventKeys.map(async function(k) {
    const value = await env.USAGE.get(k.name);
    try { return normalizeAccessRecord(JSON.parse(value), 'event'); }
    catch (e) { return null; }
  }))).filter(Boolean);
  const dailyRecords = (await Promise.all(dailyKeys.map(async function(k) {
    const value = await env.USAGE.get(k.name);
    try { return normalizeAccessRecord(JSON.parse(value), 'daily'); }
    catch (e) { return null; }
  }))).filter(Boolean);
  const eventDaySet = new Set(eventRecords.map(function(r) {
    return String(r.email || '').toLowerCase() + '|' + localDateKey(r.at || r.date || '', 'America/Toronto');
  }));
  let records = eventRecords.concat(dailyRecords.filter(function(r) {
    const key = String(r.email || '').toLowerCase() + '|' + localDateKey(r.at || r.date || '', 'America/Toronto');
    return !eventDaySet.has(key);
  }));

  records.sort(function(a, b) { return String(b.at || '').localeCompare(String(a.at || '')); });

  const days = Math.max(1, Math.min(90, parseInt(url.searchParams.get('days') || '90', 10) || 90));
  const q = (url.searchParams.get('q') || '').trim().toLowerCase();
  const countryFilter = (url.searchParams.get('country') || '').trim().toUpperCase();
  const deviceFilter = (url.searchParams.get('device') || '').trim().toLowerCase();
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;

  records = records.filter(function(r) {
    const t = Date.parse(r.at || r.date || '');
    if (!Number.isNaN(t) && t < cutoff) return false;
    if (countryFilter && String(r.country || '').toUpperCase() !== countryFilter) return false;
    if (deviceFilter && summarizeUserAgent(r.userAgent).toLowerCase().indexOf(deviceFilter) === -1) return false;
    if (q) {
      const haystack = [r.email, r.ip, r.country, r.path, summarizeUserAgent(r.userAgent), r.userAgent].join(' ').toLowerCase();
      if (haystack.indexOf(q) === -1) return false;
    }
    return true;
  });

  if ((url.searchParams.get('format') || '').toLowerCase() === 'csv') {
    return new Response(accessLogCsv(records), { headers: { 'Content-Type': 'text/csv; charset=utf-8', 'Content-Disposition': 'attachment; filename="pickleball-access-log.csv"' } });
  }

  const uniquePeople = new Set(records.map(function(r) { return r.email; })).size;
  const uniqueIps = new Set(records.map(function(r) { return r.ip; }).filter(Boolean)).size;
  const countries = Array.from(new Set(records.map(function(r) { return r.country; }).filter(Boolean))).sort();
  const today = localDateKey(new Date().toISOString(), 'America/Toronto');
  const todayRecords = records.filter(function(r) { return localDateKey(r.at || r.date || '', 'America/Toronto') === today; });
  const olderRecords = records.filter(function(r) { return localDateKey(r.at || r.date || '', 'America/Toronto') !== today; });
  const todayCount = todayRecords.length;
  const totalBeforeFilter = eventRecords.length + dailyRecords.length;
  const warnings = detectAccessWarnings(records);

  const countryOptions = countries.map(function(c) {
    return '<option value="' + escapeHtml(c) + '"' + (countryFilter === c ? ' selected' : '') + '>' + escapeHtml(c) + '</option>';
  }).join('');
  const csvParams = new URLSearchParams(url.searchParams);
  csvParams.set('format', 'csv');
  const csvHref = '/admin/login-log?' + csvParams.toString();

  const rows = records.slice(0, 500).map(function(r) {
    const device = summarizeUserAgent(r.userAgent);
    const warning = accessRowWarning(r, records);
    return '<tr>' +
      '<td><strong>' + escapeHtml(formatAccessTime(r.at)) + '</strong><div class="muted">' + escapeHtml(r.date || '') + '</div></td>' +
      '<td>' + escapeHtml(r.email) + '</td>' +
      '<td><span class="pill">' + escapeHtml(device) + '</span></td>' +
      '<td>' + escapeHtml(r.country || '—') + '</td>' +
      '<td class="mono" title="' + escapeHtml(r.ip || '') + '">' + escapeHtml(maskIp(r.ip)) + '</td>' +
      '<td class="mono">' + escapeHtml(r.path || '—') + '</td>' +
      '<td>' + (warning ? '<span class="warn">' + escapeHtml(warning) + '</span>' : '<span class="ok">OK</span>') + '</td>' +
      '</tr>';
  }).join('');

  const warningHtml = warnings.length
    ? warnings.map(function(w) { return '<div class="warning">⚠️ ' + escapeHtml(w) + '</div>'; }).join('')
    : '<div class="good">✅ No obvious access anomalies in the current filter.</div>';

  const html = [
    '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Access Log</title>',
    '<style>',
    ':root{--bg:#0A0F0A;--card:#121C12;--line:#284228;--lime:#C6FF00;--txt:#E8F5E9;--muted:#8FA28F;--warn:#FFB74D;--ok:#9CCC65}',
    '*{box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:var(--bg);color:var(--txt);padding:1.25rem;max-width:1180px;margin:0 auto}',
    'h1{color:var(--lime);font-size:1.55rem;margin:0 0 .35rem}.sub{color:var(--muted);font-size:.9rem;margin-bottom:1rem}',
    '.cards{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.75rem;margin:1rem 0}.card{background:linear-gradient(180deg,#152315,#0F180F);border:1px solid var(--line);border-radius:14px;padding:1rem}.num{font-size:1.45rem;font-weight:900;color:var(--lime)}.label{color:var(--muted);font-size:.78rem;margin-top:.15rem}',
    '.toolbar{display:grid;grid-template-columns:2fr .8fr .8fr .8fr auto auto auto auto;gap:.55rem;align-items:end;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:.75rem;margin:1rem 0}label{display:block;font-size:.72rem;color:var(--muted);margin-bottom:.2rem}input,select{width:100%;background:#071007;color:var(--txt);border:1px solid var(--line);border-radius:9px;padding:.55rem .6rem}button,.btn{display:inline-block;text-decoration:none;background:#1B5E20;color:white;border:1px solid #2E7D32;border-radius:9px;padding:.55rem .75rem;font-weight:700;cursor:pointer;white-space:nowrap}.btn.secondary{background:#263238;border-color:#455A64}',
    '.warnings{margin:1rem 0;display:grid;gap:.5rem}.warning{background:#2A1B08;border:1px solid #7A4B00;color:#FFE0B2;border-radius:12px;padding:.7rem .85rem;font-size:.9rem}.good{background:#102310;border:1px solid #2E7D32;color:#C8E6C9;border-radius:12px;padding:.7rem .85rem;font-size:.9rem}',
    'table{width:100%;border-collapse:collapse;font-size:.86rem;background:var(--card);border:1px solid var(--line);border-radius:14px;overflow:hidden}th{text-align:left;background:#1B5E20;color:var(--lime);padding:.65rem .75rem;position:sticky;top:0}td{padding:.62rem .75rem;border-bottom:1px solid var(--line);vertical-align:top}tr:hover td{background:#101D10}.muted{color:var(--muted);font-size:.76rem}.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.8rem;color:#B0BEC5}.pill{display:inline-block;background:#203020;border:1px solid #375037;border-radius:999px;padding:.18rem .5rem;font-size:.78rem}.ok{color:var(--ok);font-weight:800}.warn{color:var(--warn);font-weight:800}.empty{color:var(--ok);padding:2rem 0;text-align:center;background:var(--card);border:1px solid var(--line);border-radius:14px}.todayBox{background:#111E11;border:1px solid var(--line);border-radius:14px;padding:.85rem;margin:1rem 0}.todayTitle{font-weight:900;color:var(--lime);margin-bottom:.45rem}.todayRow{display:grid;grid-template-columns:110px 1.4fr 1.2fr 1fr;gap:.6rem;padding:.45rem 0;border-top:1px solid rgba(198,255,0,.12)}.todayRow:first-of-type{border-top:0}.eventBadge{color:#C6FF00;font-weight:800}.foot{color:#607060;font-size:.76rem;margin-top:1rem;line-height:1.45}',
    '@media(max-width:850px){.cards{grid-template-columns:repeat(2,1fr)}.toolbar{grid-template-columns:1fr 1fr}table{font-size:.78rem}th:nth-child(6),td:nth-child(6){display:none}}',
    '</style></head><body>',
    '<h1>🔐 Access Log</h1><div class="sub">Admin-only view of who accessed Pickleball Pro. Detailed events are retained for up to 90 days.</div>',
    '<div class="cards"><div class="card"><div class="num">' + records.length + '</div><div class="label">access events shown</div></div><div class="card"><div class="num">' + uniquePeople + '</div><div class="label">unique people</div></div><div class="card"><div class="num">' + uniqueIps + '</div><div class="label">unique IPs</div></div><div class="card"><div class="num">' + todayCount + '</div><div class="label">events today</div></div></div>',
    '<form class="toolbar" method="GET" action="/admin/login-log"><div><label>Search email, IP, device, path</label><input name="q" value="' + escapeHtml(q) + '" placeholder="example: john, iPhone, CA"></div><div><label>Days</label><select name="days"><option' + (days===7?' selected':'') + '>7</option><option' + (days===30?' selected':'') + '>30</option><option' + (days===60?' selected':'') + '>60</option><option' + (days===90?' selected':'') + '>90</option></select></div><div><label>Country</label><select name="country"><option value="">All</option>' + countryOptions + '</select></div><div><label>Device contains</label><input name="device" value="' + escapeHtml(deviceFilter) + '" placeholder="iPhone"></div><button type="submit">Filter</button><a class="btn secondary" href="/admin/access-log">Refresh</a><a class="btn secondary" href="/admin/access-log?days=90">Clear Filters</a><a class="btn secondary" href="' + escapeHtml(csvHref) + '">Export CSV</a></form>',
    // PB_ACCESS_LOG_DELETE_MATCHING_UI_V1
    '<form class="toolbar" method="POST" action="/admin/access-log/delete-matching" style="border-color:#7f1d1d;background:#1f1111">' +
      '<input type="hidden" name="q" value="' + escapeHtml(q) + '">' +
      '<input type="hidden" name="days" value="' + escapeHtml(String(days)) + '">' +
      '<input type="hidden" name="country" value="' + escapeHtml(countryFilter) + '">' +
      '<input type="hidden" name="device" value="' + escapeHtml(deviceFilter) + '">' +
      '<div><label>Delete matching logs</label><input name="confirm" placeholder="Type DELETE" autocomplete="off"></div>' +
      '<button type="submit" style="background:#ff4d4d;color:#fff">Delete matching logs</button>' +
      '<div class="muted" style="align-self:center">Deletes only logs matching the current Search / Days / Country / Device filters.</div>' +
    '</form>',
    '<div class="warnings">' + warningHtml + '</div>',
    '<div class="sub"><strong>Showing ' + records.length + ' matching records</strong> from ' + totalBeforeFilter + ' saved log records. Today is shown separately; older history remains below.</div>',
    todaySectionHtml(todayRecords),
    olderSectionHtml(olderRecords, records),
    '<p class="foot">Notes: IP addresses are partially masked on-screen for privacy; CSV export contains the recorded IP. User-Agent/device is browser-supplied and should be treated as a helpful clue, not proof. Older entries may be daily summaries if they were created before detailed access-event logging was enabled.</p>',
    '</body></html>'
  ].join('');

  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}

function normalizeAccessRecord(r, source) {
  const at = r.at || r.firstLoginAt || r.acceptedAt || new Date().toISOString();
  return { source: source, email: r.email || r.user || 'unknown', at: at, date: r.date || String(at).slice(0, 10), ip: r.ip || null, country: r.country || null, userAgent: r.userAgent || null, path: r.path || '—', accessMethod: r.accessMethod || 'email-login', ray: r.ray || null };
}

function maskIp(ip) {
  if (!ip) return '—';
  const s = String(ip);
  if (s.indexOf(':') !== -1) return s.split(':').slice(0, 3).join(':') + ':…';
  const parts = s.split('.');
  if (parts.length === 4) return parts[0] + '.' + parts[1] + '.' + parts[2] + '.xxx';
  return s;
}

function formatAccessTime(iso) {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Toronto', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: true }).format(new Date(iso));
  } catch (e) { return iso || '—'; }
}


function localDateKey(iso, timeZone) {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: timeZone || 'America/Toronto', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso));
  } catch (e) {
    return String(iso || '').slice(0, 10);
  }
}

function todaySectionHtml(todayRecords) {
  const items = (todayRecords || []).slice(0, 12);
  if (!items.length) {
    return '<div class="todayBox"><div class="todayTitle">📅 Today</div><div class="muted">No matching entries for today under the current filter. Try clearing Device/Search filters and click Refresh.</div></div>';
  }
  const rows = items.map(function(r) {
    return '<div class="todayRow"><div>' + escapeHtml(formatAccessTime(r.at)) + '</div><div>' + escapeHtml(r.email || 'unknown') + '</div><div><span class="eventBadge">' + escapeHtml(eventLabel(r)) + '</span></div><div class="muted">' + escapeHtml(summarizeUserAgent(r.userAgent)) + '</div></div>';
  }).join('');
  return '<div class="todayBox"><div class="todayTitle">📅 Today (' + todayRecords.length + ')</div>' + rows + (todayRecords.length > items.length ? '<div class="muted">+' + (todayRecords.length - items.length) + ' more today. Export CSV to view all.</div>' : '') + '</div>';
}

function olderSectionHtml(olderRecords, allRecords) {
  const items = (olderRecords || []).slice(0, 500);
  if (!items.length) {
    return '<div class="todayBox"><div class="todayTitle">📜 Previous History</div><div class="muted">No older logins match the current filter. Click Clear Filters to view the full 90-day history.</div></div>';
  }
  const rows = items.map(function(r) {
    const device = summarizeUserAgent(r.userAgent);
    const warning = accessRowWarning(r, allRecords || olderRecords);
    return '<tr>' +
      '<td><strong>' + escapeHtml(formatAccessTime(r.at)) + '</strong><div class="muted">' + escapeHtml(r.date || '') + '</div></td>' +
      '<td>' + escapeHtml(r.email) + '</td>' +
      '<td><span class="pill">' + escapeHtml(device) + '</span></td>' +
      '<td>' + escapeHtml(r.country || '—') + '</td>' +
      '<td class="mono" title="' + escapeHtml(r.ip || '') + '">' + escapeHtml(maskIp(r.ip)) + '</td>' +
      '<td class="mono">' + escapeHtml(r.path || '—') + '</td>' +
      '<td>' + (warning ? '<span class="warn">' + escapeHtml(warning) + '</span>' : '<span class="ok">OK</span>') + '</td>' +
      '</tr>';
  }).join('');
  return '<div class="todayBox"><div class="todayTitle">📜 Previous History (' + olderRecords.length + ')</div><div class="muted" style="margin-bottom:.6rem">Older logins and access events from the selected range.</div><table><thead><tr><th>Time</th><th>Email</th><th>Device</th><th>Country</th><th>IP</th><th>Page</th><th>Status</th></tr></thead><tbody>' + rows + '</tbody></table>' + (olderRecords.length > items.length ? '<div class="muted">+' + (olderRecords.length - items.length) + ' more older records. Export CSV to view all.</div>' : '') + '</div>';
}

function eventLabel(r) {
  const t = r.eventType || r.accessMethod || 'access';
  if (t === 'app-visit') return 'App visit';
  if (t === 'first-login-of-day') return 'First login today';
  if (t === 'terms-accepted') return 'Terms accepted';
  return String(t).replace(/-/g, ' ');
}

function accessLogCsv(records) {
  const rows = [['time_utc','email','device','country','ip','path','access_method','cf_ray']];
  for (const r of records) rows.push([r.at, r.email, summarizeUserAgent(r.userAgent), r.country || '', r.ip || '', r.path || '', r.accessMethod || '', r.ray || '']);
  return rows.map(function(row) { return row.map(function(v) { return '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"'; }).join(','); }).join('\n');
}

function detectAccessWarnings(records) {
  const warnings = [];
  const byEmail = new Map();
  for (const r of records) {
    if (!byEmail.has(r.email)) byEmail.set(r.email, []);
    byEmail.get(r.email).push(r);
  }
  for (const entry of byEmail.entries()) {
    const email = entry[0];
    const items = entry[1];
    const countries = new Set(items.map(function(x) { return x.country; }).filter(Boolean));
    const ips = new Set(items.map(function(x) { return x.ip; }).filter(Boolean));
    if (countries.size > 1) warnings.push(email + ' accessed from ' + countries.size + ' countries in this period.');
    if (ips.size >= 4) warnings.push(email + ' used ' + ips.size + ' different IP addresses in this period.');
  }
  return warnings.slice(0, 6);
}

function accessRowWarning(r, records) {
  const sameEmail = records.filter(function(x) { return x.email === r.email; });
  const countries = new Set(sameEmail.map(function(x) { return x.country; }).filter(Boolean));
  if (countries.size > 1) return 'Review country';
  const ips = new Set(sameEmail.map(function(x) { return x.ip; }).filter(Boolean));
  if (ips.size >= 4) return 'Many IPs';
  return '';
}

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// ── Terms of Service acceptance record ──────────────────────────────────
// Stores a durable, server-side record of who accepted which version of
// the Terms and when — the in-app modal also records this locally in the
// browser, but localStorage can be cleared; this KV record is what
// actually survives. Keyed by caller identity + version, so re-accepting
// the same version twice just overwrites with a fresh timestamp rather
// than creating duplicate records.
async function handleTosAccept(d, env, userEmail) {
  const terms = await getTermsConfig(env);
  const version = normalizeVersion(d.version || terms.version);
  if (!version) {
    return json({ ok: false, error: 'Missing version' }, 400, env);
  }
  if (version !== terms.version) {
    return json({ ok: false, error: 'Terms version is no longer current', currentVersion: terms.version }, 409, env);
  }
  const record = {
    user: userEmail,
    version,
    acceptedAt: d.acceptedAt || new Date().toISOString(),
  };
  try {
    // No expirationTtl here, deliberately — unlike the SMS/email daily
    // usage counters above, a ToS acceptance record should be kept
    // indefinitely, not rolled off after a day.
    await env.USAGE.put(`tos-accept:${userEmail}:${version}`, JSON.stringify(record));
    return json({ ok: true }, 200, env);
  } catch (e) {
    return json({ ok: false, error: 'Could not record acceptance' }, 500, env);
  }
}

// ── DUPR ID map: durable backup of player → DUPR ID, scoped per tournament ──
// The frontend's exportDuprCSV() flow keeps its own copy in localStorage
// for instant access with no network round-trip — this is the durable
// twin of that, so the map survives a cleared browser, a new device, or
// a different organizer logging in.
//
// SCOPED BY TOURNAMENT NAME, not one single global map. Two directors
// running two DIFFERENTLY-NAMED tournaments get fully separate maps, so a
// "John Smith" in one event never collides with an unrelated "John Smith"
// in another. Within ONE tournament name, the map is still shared across
// everyone who logs in (not per-caller-identity) — DUPR IDs belong to a
// player, not to whichever organizer happened to type them in, same as
// the player roster itself isn't siloed per login.
//
// Stored as one KV value per tournament name (not one key per player) —
// this app's player counts are small (dozens, not thousands) per event,
// so reading/writing the whole map in one KV operation is simpler and
// avoids the list()-pagination pattern the admin reports need for
// genuinely unbounded data.
const DUPR_ID_MAP_KV_PREFIX = 'dupr-id-map:';

// Builds the actual KV key from a tournament name. Caps length and strips
// characters KV keys shouldn't carry raw from user input — this only
// needs to be stable and collision-resistant for reasonable tournament
// names, not cryptographically perfect; two tournaments that differ only
// in stripped punctuation sharing a scope is an acceptable, rare edge case.
function duprIdMapKvKey(tournamentName) {
  const safe = String(tournamentName || '(untitled)').trim().slice(0, 200) || '(untitled)';
  return DUPR_ID_MAP_KV_PREFIX + safe;
}

async function handleGetDuprIds(env, tournamentName) {
  try {
    const raw = await env.USAGE.get(duprIdMapKvKey(tournamentName));
    const map = raw ? JSON.parse(raw) : {};
    return json({ ok: true, map }, 200, env);
  } catch (e) {
    return json({ ok: false, error: 'Could not read DUPR ID map' }, 500, env);
  }
}

// Merges incoming entries into the existing map (for this tournament name)
// rather than overwriting it outright — two organizers exporting from two
// different devices around the same time, working on the SAME-NAMED
// tournament, should both end up contributing their IDs, not have the
// second save wipe out the first's. Last-write-wins per individual player
// (not per whole map), which matches how rare and low-stakes a conflict
// on one specific player's ID actually is.
async function handleSaveDuprIds(d, env, userEmail) {
  const incoming = d.map;
  if (!incoming || typeof incoming !== 'object' || Array.isArray(incoming)) {
    return json({ ok: false, error: 'map object required' }, 400, env);
  }
  // Basic sanity cap, same spirit as the standings payload-size check —
  // this should only ever be a few dozen-to-hundred entries for a real
  // tournament roster.
  const keys = Object.keys(incoming);
  if (keys.length > 5000) {
    return json({ ok: false, error: 'Payload too large' }, 413, env);
  }
  for (const k of keys) {
    if (typeof incoming[k] !== 'string' || incoming[k].length > 64) {
      return json({ ok: false, error: `Invalid DUPR ID value for "${k}"` }, 400, env);
    }
  }

  // Optional list of name-keys to delete, applied AFTER the merge below —
  // lets one save call both add/update some players and remove others in
  // a single round trip (the DUPR ID manager's delete button uses this).
  // Plain array of strings only; same shape/size sanity check as the map.
  const remove = Array.isArray(d.remove) ? d.remove : [];
  if (remove.length > 5000 || remove.some(k => typeof k !== 'string')) {
    return json({ ok: false, error: 'Invalid remove list' }, 400, env);
  }

  const kvKey = duprIdMapKvKey(d.tournament);

  try {
    const raw = await env.USAGE.get(kvKey);
    const existing = raw ? JSON.parse(raw) : {};
    const merged = { ...existing, ...incoming };
    remove.forEach(k => { delete merged[k]; });
    await env.USAGE.put(kvKey, JSON.stringify(merged));
    return json({ ok: true, map: merged }, 200, env);
  } catch (e) {
    return json({ ok: false, error: 'Could not save DUPR ID map' }, 500, env);
  }
}

// ── SMS via Twilio (using YOUR account secrets, never the browser's) ──────
async function handleSms(d, env, userEmail) {
  const to = (d.to || '').trim();
  const messageBody = (d.body || d.message || '').trim();
  if (!to || !messageBody) {
    return json({ ok: false, error: 'Missing fields: to, body' }, 400, env);
  }

  const max = parseInt(env.MAX_SMS_PER_DAY || '200', 10);
  const usage = await checkAndIncrement(env, todayKey('sms', userEmail), max);
  if (!usage.ok) {
    return json({ ok: false, error: `Daily SMS limit reached (${max}/day). Contact support to raise your limit.` }, 429, env);
  }

  const sid = env.TWILIO_ACCOUNT_SID;
  const token = env.TWILIO_AUTH_TOKEN;
  const from = env.TWILIO_FROM;
  if (!sid || !token || !from) {
    return json({ ok: false, error: 'Relay misconfigured — missing Twilio secrets' }, 500, env);
  }

  const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`;
  const params = new URLSearchParams({ To: to, From: from, Body: messageBody });
  const creds = btoa(`${sid}:${token}`);

  try {
    const r = await fetch(twilioUrl, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${creds}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params.toString(),
    });
    const result = await r.json().catch(() => ({}));
    if (r.ok) {
      return json({ ok: true, sid: result.sid }, 200, env);
    }
    return json({ ok: false, error: result.message || `Twilio error ${r.status}`, twilioCode: result.code || null }, r.status, env);
  } catch (e) {
    return json({ ok: false, error: 'Could not reach Twilio' }, 502, env);
  }
}

// ── Email via Brevo's HTTPS API (using YOUR account secret) ────────────────
async function handleEmail(d, env, userEmail) {
  const to = (d.to || '').trim();
  const subject = (d.subject || '').trim();
  const html = d.html || '';
  if (!to || !subject || !html) {
    return json({ ok: false, error: 'Missing fields: to, subject, html' }, 400, env);
  }

  const max = parseInt(env.MAX_EMAIL_PER_DAY || '500', 10);
  const usage = await checkAndIncrement(env, todayKey('email', userEmail), max);
  if (!usage.ok) {
    return json({ ok: false, error: `Daily email limit reached (${max}/day). Contact support to raise your limit.` }, 429, env);
  }

  if (!env.BREVO_API_KEY) {
    return json({ ok: false, error: 'Relay misconfigured — missing BREVO_API_KEY' }, 500, env);
  }

  const fromEmail = env.SMTP_FROM;
  const fromName = env.SMTP_FROM_NAME || 'Pickleball Pro';
  if (!fromEmail) {
    return json({ ok: false, error: 'Relay misconfigured — missing SMTP_FROM' }, 500, env);
  }

  try {
    // Brevo's API differs from a typical Bearer-token API in two ways that
    // matter here: the key goes in a custom 'api-key' header (not
    // Authorization: Bearer), and the recipient/sender shapes are objects
    // with explicit email/name fields, not Resend-style plain strings.
    const r = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': env.BREVO_API_KEY,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        sender: { email: fromEmail, name: fromName },
        to: [{ email: to }],
        subject,
        htmlContent: html,
      }),
    });
    if (r.ok) {
      return json({ ok: true }, 200, env);
    }
    // Brevo's error responses are shaped { code, message }, not Resend's
    // { message } — message still works as the readable field either way.
    const errBody = await r.json().catch(() => ({}));
    return json({ ok: false, error: errBody.message || `Email provider error ${r.status}` }, 502, env);
  } catch (e) {
    return json({ ok: false, error: String(e) }, 502, env);
  }
}

// ── Standings: pure calculation, moved server-side ─────────────────────────
// This endpoint doesn't spend any of your money (unlike SMS/email), so it
// has no daily cap — but it's still behind the same Access check as
// everything else in this Worker (see the userEmail check above), since the
// scheduling/standings logic is exactly the kind of thing worth keeping out
// of the shipped frontend.
async function handleStandings(d, env, userEmail) {
  const players = d.players;
  const schedule = d.schedule;

  if (!Array.isArray(players) || !Array.isArray(schedule)) {
    return json({ ok: false, error: 'players and schedule arrays required' }, 400, env);
  }
  // Basic sanity caps — a real tournament app's payload is small (a few
  // hundred players/matches at most); reject anything wildly oversized
  // rather than spend compute on a malformed/abusive request.
  if (players.length > 2000 || schedule.length > 500) {
    return json({ ok: false, error: 'Payload too large' }, 413, env);
  }

  try {
    const stats = computeStandings(players, schedule);
    return json({ ok: true, stats }, 200, env);
  } catch (e) {
    return json({ ok: false, error: 'Could not compute standings: ' + String(e && e.message ? e.message : e) }, 400, env);
  }
}
