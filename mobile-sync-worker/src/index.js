/**
 * Pickleball Tournament — Mobile Sync Worker
 * ───────────────────────────────────────────
 * Routes:
 *   GET  /api/:code/state              → current round/courts/scores (mobile polls this)
 *   POST /api/:code/push               → desktop app pushes the current round's courts
 *   POST /api/:code/claim              → scorekeeper claims a court (name, optional PIN)
 *   POST /api/:code/score              → scorekeeper submits a score for their court
 *   GET  /api/:code/updates            → desktop app polls this for new score submissions
 *   POST /api/:code/ack                → desktop app acks that it has consumed submissions
 *
 * :code is a short tournament code (e.g. "BURL25") chosen by the organizer.
 * Each unique code maps to its own Durable Object instance — fully isolated per event.
 *
 * Static assets (mobile.html, the scorekeeper UI) are served directly from this Worker too,
 * so the whole thing is a single Cloudflare deployment.
 */

import { TournamentRoom } from './tournament-room.js';
import MOBILE_HTML from './mobile.html';

export { TournamentRoom };

function withCORS(resp) {
  const r = new Response(resp.body, resp);
  r.headers.set('Access-Control-Allow-Origin', '*');
  r.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  r.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  return r;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return withCORS(new Response(null, { status: 204 }));
    }

    // ── Serve the mobile scorekeeper page ──────────────────────────────
    // No-cache headers: this page changes whenever we redeploy, and phones
    // (especially mobile Safari/Chrome) can otherwise hang onto a stale
    // cached copy for a long time after a redeploy, even past a normal
    // pull-to-refresh.
    if (url.pathname === '/' || url.pathname === '/mobile' || url.pathname === '/mobile.html') {
      return new Response(MOBILE_HTML, {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      });
    }

    // ── API routes: /api/:code/:action ─────────────────────────────────
    const m = url.pathname.match(/^\/api\/([A-Za-z0-9_-]{1,32})\/([a-z-]+)$/);
    if (!m) {
      return withCORS(new Response(JSON.stringify({ ok: false, error: 'Not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      }));
    }

    const [, code, action] = m;
    const id = env.TOURNAMENT_ROOM.idFromName(code.toUpperCase());
    const stub = env.TOURNAMENT_ROOM.get(id);

    // Forward to the Durable Object, which handles all the actions above
    const doUrl = new URL(request.url);
    doUrl.pathname = '/' + action;
    const doRequest = new Request(doUrl.toString(), request);
    const resp = await stub.fetch(doRequest);
    return withCORS(resp);
  },
};
