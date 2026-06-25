#!/usr/bin/env node
/**
 * Build script for production deploy.
 *
 * Usage:
 *   node build.js                    # builds without client config (default)
 *   node build.js --client coachjohn # builds with clients/coachjohn.json baked in
 *
 * With a --client flag, the client config is injected into the HTML so the
 * app knows its branding, admin email, and feature flags at runtime. This
 * is how the same codebase serves multiple clients in isolation.
 *
 * Minifies inline <script> JS blocks using Terser, leaving HTML/CSS untouched.
 */
const fs   = require('fs');
const path = require('path');
const { minify } = require('terser');

// ── Parse --client flag ────────────────────────────────────────────────────
const clientArg = process.argv.indexOf('--client');
const clientId  = clientArg !== -1 ? process.argv[clientArg + 1] : null;
let clientCfg   = null;

if (clientId) {
  const cfgPath = path.join(__dirname, 'clients', `${clientId}.json`);
  if (!fs.existsSync(cfgPath)) {
    console.error(`✗ Client config not found: ${cfgPath}`);
    console.error(`  Create it by copying clients/template.json and filling in the fields.`);
    process.exit(1);
  }
  clientCfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  console.log(`Building for client: ${clientCfg.client.name} (${clientId})`);
} else {
  console.log('Building without client config (default).');
}

const SRC = path.join(__dirname, 'public', 'index.html');
const OUT = path.join(__dirname, 'dist', 'index.html');

// ── Inject client config into HTML ─────────────────────────────────────────
// Inserts a <script> block right after <head> that sets window.__CLIENT__
// so the app can read branding, features, and admin email at startup.
// This is baked in at build time — no runtime fetch, no network request.
function injectClientConfig(html, cfg) {
  if (!cfg) return html;
  const injection = `<script>window.__CLIENT__=${JSON.stringify(cfg)};</script>`;
  return html.replace('<head>', '<head>\n  ' + injection);
}

// ── Generate wrangler.toml environment section for this client ─────────────
function writeWranglerEnv(cfg) {
  const tomlPath = path.join(__dirname, 'worker', 'wrangler.toml');
  let toml = fs.readFileSync(tomlPath, 'utf8');

  const envMarker = `[env.${cfg.client.id}]`;

  // If this client's env block already exists, skip — don't risk corrupting it.
  // The block was either written correctly before or the user edited it manually.
  if (toml.includes(envMarker)) {
    console.log(`wrangler.toml already has [env.${cfg.client.id}] — skipping update.`);
    return;
  }

  // Append a new clean env block for this client
  const envSection = `
[env.${cfg.client.id}]
name = "${cfg.worker.name}"

[[env.${cfg.client.id}.kv_namespaces]]
binding = "USAGE"
id = "${cfg.worker.kvNamespaceId}"

[env.${cfg.client.id}.vars]
MAX_SMS_PER_DAY   = "${cfg.limits.maxSmsPerDay}"
MAX_EMAIL_PER_DAY = "${cfg.limits.maxEmailPerDay}"
`;

  fs.writeFileSync(tomlPath, toml.trimEnd() + '\n' + envSection, 'utf8');
  console.log(`Added [env.${cfg.client.id}] to wrangler.toml`);
}

async function build() {
  let html = fs.readFileSync(SRC, 'utf8');

  // Inject client config before minification so it gets minified too
  if (clientCfg) {
    html = injectClientConfig(html, clientCfg);
    // Note: wrangler.toml is managed manually — see clients/README below.
    // Do NOT auto-write wrangler.toml here; it causes TOML corruption.
  }

  // ── Minify inline <script> blocks ────────────────────────────────────────
  const scriptRe = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
  let totalIn = 0, totalOut = 0;
  const matches = [...html.matchAll(scriptRe)];
  console.log(`Found ${matches.length} inline <script> block(s) to minify.`);

  let result = html;
  for (const m of matches) {
    const full = m[0], code = m[1];
    if (!code.trim()) continue;
    totalIn += code.length;
    let minified;
    try {
      const out = await minify(code, {
        compress: { drop_console: false },
        mangle: true,
        format: { comments: false },
      });
      if (out.error) throw out.error;
      minified = out.code;
    } catch (e) {
      console.error('  ✗ Minify failed for one block, leaving it unminified:', e.message);
      minified = code;
    }
    totalOut += minified.length;
    const tagOpen = full.slice(0, full.indexOf('>') + 1);
    result = result.split(full).join(`${tagOpen}${minified}</script>`);
  }

  fs.mkdirSync(path.dirname(OUT), { recursive: true });

  // ── Safety checks ─────────────────────────────────────────────────────────
  const outScriptCount = (result.match(/<script(?![^>]*\bsrc=)[^>]*>/gi) || []).length;
  if (outScriptCount !== matches.length) {
    throw new Error(`Sanity check failed: expected ${matches.length} <script> tag(s), found ${outScriptCount}.`);
  }
  if (result.length > html.length) {
    throw new Error(`Sanity check failed: output larger than input.`);
  }
  try {
    const outMatches = [...result.matchAll(scriptRe)];
    for (const om of outMatches) { if (om[1].trim()) new Function(om[1]); }
  } catch (e) {
    throw new Error(`Sanity check failed: output JS does not parse (${e.message}).`);
  }

  fs.writeFileSync(OUT, result, 'utf8');

  const pct = totalIn ? (100 * (1 - totalOut / totalIn)).toFixed(1) : 0;
  console.log(`JS: ${totalIn.toLocaleString()} → ${totalOut.toLocaleString()} bytes (${pct}% smaller)`);
  console.log(`Wrote ${OUT}`);

  // ── Sync into Worker ───────────────────────────────────────────────────────
  const WORKER_COPY = path.join(__dirname, 'worker', 'src', 'app.html');
  if (fs.existsSync(path.dirname(WORKER_COPY))) {
    fs.copyFileSync(OUT, WORKER_COPY);
    console.log(`Synced → ${WORKER_COPY}`);
  }
}

build().catch((e) => { console.error('Build failed:', e); process.exit(1); });
