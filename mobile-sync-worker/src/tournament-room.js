/**
 * TournamentRoom — one Durable Object instance per tournament code.
 * Holds the live "current round" snapshot and any score submissions
 * that haven't yet been pulled back into the desktop app.
 *
 * Storage shape (in this.state):
 *   tournamentName: string
 *   round:          number
 *   updatedAt:      number (ms epoch)
 *   courts: [
 *     { court: 1, matchId: 12, teamA: ["Alice Turner","Bob Martin"],
 *       teamB: ["Carol Singh","David Chen"], scoreA: '', scoreB: '', complete: false }
 *     ...
 *   ]
 *   courtPins: { [court]: "4471" }   — organizer-set PIN required to claim that court.
 *                                       A court with no PIN set (or '') can be claimed freely.
 *   claims:  { [court]: { name: "Mike", token: "x7f...", claimedAt: ms } }
 *                                     — token is a random secret handed back to the phone
 *                                       on a successful claim; required on every /score call
 *                                       for that court so only the claiming phone can submit.
 *   pending: [ { court, matchId, scoreA, scoreB, submittedBy, submittedAt, consumed } ]
 *   announcements: [ { id, text, postedAt } ]  — organizer's one-way messages to all phones,
 *                                                 newest first. Read-only on the phone side.
 */
export class TournamentRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.data = null; // lazy-loaded from durable storage
  }

  async load() {
    if (this.data) return this.data;
    const stored = await this.state.storage.get('room');
    this.data = stored || {
      tournamentName: '',
      round: 0,
      updatedAt: 0,
      courts: [],
      courtPins: {},
      claims: {},
      pending: [],
      announcements: [],
      byePlayers: [],
    };
    // Backfill for rooms created before these fields existed
    if (!this.data.courtPins) this.data.courtPins = {};
    if (!this.data.announcements) this.data.announcements = [];
    if (!this.data.byePlayers) this.data.byePlayers = [];
    return this.data;
  }

  async save() {
    await this.state.storage.put('room', this.data);
  }

  json(obj, status = 200) {
    return new Response(JSON.stringify(obj), {
      status,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  randomToken() {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  }

  // Normalizes a name for comparison: lowercase, trimmed, collapsed
  // whitespace, accents stripped (so "José" and "jose" both match).
  normalizeName(s) {
    return String(s || '')
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '') // strip accents
      .toLowerCase()
      .trim()
      .replace(/\s+/g, ' ');
  }

  // Plain Levenshtein edit distance — used to tolerate small typos
  // ("Mke" vs "Mike") without accepting genuinely different names.
  editDistance(a, b) {
    const m = a.length, n = b.length;
    if (m === 0) return n;
    if (n === 0) return m;
    const dp = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
    for (let j = 0; j <= n; j++) dp[0][j] = j;
    for (let i = 1; i <= m; i++) {
      for (let j = 1; j <= n; j++) {
        dp[i][j] = a[i - 1] === b[j - 1]
          ? dp[i - 1][j - 1]
          : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
      }
    }
    return dp[m][n];
  }

  // Checks whether `typedName` plausibly refers to one of the roster names
  // on a court, and resolves to the ROSTER name (the real "First Last" from
  // the schedule) rather than the typed text — this is what lets
  // "submitted by" always show a proper full name even if the scorekeeper
  // typed a nickname, first-name-only, or a minor typo.
  //
  // IMPORTANT: this checks ALL roster names and collects every plausible
  // match, rather than returning the first one found. Two players with the
  // same first name (e.g. "John Smith" and "John Davis" on the same court)
  // would otherwise silently resolve to whichever one happens to come
  // first in the array when someone types just "John" — wrong name
  // attributed with no warning. Instead: if exactly one roster name
  // matches, resolve to it. If more than one matches equally well, return
  // an ambiguous result listing the candidates so the caller can ask the
  // scorekeeper to type their full name instead of guessing.
  //
  // Matching tiers, checked in order of confidence — a typed name only
  // moves to a looser tier if NOTHING matched at a tighter one, so an exact
  // match always wins outright even if some other roster name would also
  // loosely typo-match:
  //   1. Exact match (full name or first name only)
  //   2. Word-prefix match ("Alice T" / "Alice" matching "Alice Turner")
  //   3. Typo tolerance (edit distance scaled to name length)
  //
  // Returns:
  //   { name: 'Alice Turner' }                      — unambiguous match
  //   { ambiguous: ['John Smith', 'John Davis'] }    — multiple plausible matches
  //   null                                            — no match at all
  matchRosterName(typedName, rosterNames) {
    const typed = this.normalizeName(typedName);
    if (!typed) return null;

    const exact = [];
    const prefix = [];
    const typo = [];

    for (const full of rosterNames) {
      const fullNorm = this.normalizeName(full);
      const firstNorm = fullNorm.split(' ')[0] || '';
      if (!fullNorm) continue;

      if (typed === fullNorm || typed === firstNorm) {
        exact.push(full);
        continue; // an exact match on this name is as good as it gets — no need to also check looser tiers for it
      }

      // Word-prefix match: handles "Alice T" matching "Alice Turner", or
      // "Alice" matching "Alice Turner" — each typed word must be either
      // equal to, or a meaningful prefix (3+ chars, or the whole word if
      // shorter) of, the corresponding roster word in order. This is
      // deliberately NOT a plain substring check — "bo" must not match
      // "bob" just because it's contained in it.
      const typedWords = typed.split(' ').filter(Boolean);
      const fullWords = fullNorm.split(' ').filter(Boolean);
      let prefixMatched = false;
      if (typedWords.length && typedWords.length <= fullWords.length) {
        const allWordsMatch = typedWords.every((tw, i) => {
          const fw = fullWords[i];
          if (!fw) return false;
          if (tw === fw) return true;
          // The first word needs a meaningful prefix (3+ chars) to count as
          // a loose match, so a bare single letter doesn't loosely match
          // any name starting with that letter. Later words (e.g. a middle
          // initial after the first name already matched exactly) can be
          // shorter — "Alice T" matching "Alice Turner" is a deliberate,
          // narrow case, not a general short-prefix allowance.
          const minLen = i === 0 ? 3 : 1;
          return tw.length >= minLen && fw.startsWith(tw);
        });
        if (allWordsMatch) { prefix.push(full); prefixMatched = true; }
      }
      if (prefixMatched) continue;

      // Typo tolerance: roughly 1 edit per 4 characters, but never more
      // than ~20% of the name's own length — without this cap, short names
      // like "Bo" would accept "Bob" as a 1-edit typo, which is wrong.
      const tolerance = (s) => s.length <= 3 ? 0 : Math.max(1, Math.floor(s.length / 4));
      if (this.editDistance(typed, fullNorm) <= tolerance(fullNorm) ||
          this.editDistance(typed, firstNorm) <= tolerance(firstNorm)) {
        typo.push(full);
      }
    }

    // Use the tightest tier that has any matches at all — an exact match
    // on one name beats a typo-tolerance match on another, even if both
    // technically matched something.
    const candidates = exact.length ? exact : (prefix.length ? prefix : typo);
    if (candidates.length === 0) return null;
    if (candidates.length === 1) return { name: candidates[0] };
    return { ambiguous: candidates };
  }

  async fetch(request) {
    const url = new URL(request.url);
    const data = await this.load();

    try {
      // ── GET /state — mobile polls this for the current round ────────
      if (url.pathname === '/state' && request.method === 'GET') {
        // Never send raw PINs to phones — only whether one is required.
        const courts = data.courts.map((c) => ({
          ...c,
          pinRequired: !!(data.courtPins[c.court] || data.courtPins[String(c.court)]),
        }));
        const claims = {};
        Object.keys(data.claims).forEach((court) => {
          // Never send claim tokens out — only the name + when claimed.
          const { name, claimedAt } = data.claims[court];
          claims[court] = { name, claimedAt };
        });
        return this.json({
          ok: true,
          tournamentName: data.tournamentName,
          round: data.round,
          updatedAt: data.updatedAt,
          courts,
          claims,
          announcements: data.announcements || [],
          byePlayers: data.byePlayers || [],
        });
      }

      // ── POST /push — desktop app pushes the current round's courts ──
      if (url.pathname === '/push' && request.method === 'POST') {
        const body = await request.json();
        if (!Array.isArray(body.courts)) {
          return this.json({ ok: false, error: 'courts array required' }, 400);
        }
        data.tournamentName = body.tournamentName || data.tournamentName || '';
        data.round = body.round || 0;
        // Defaults to [] both for a genuinely empty bye list AND for an
        // older desktop app version that doesn't send this field yet —
        // either way, "no byes to show" is the correct, safe fallback.
        data.byePlayers = Array.isArray(body.byePlayers) ? body.byePlayers : [];
        data.updatedAt = Date.now();

        const prevMatchIdByCourt = {};
        const prevCourtByCourt = {};
        data.courts.forEach((c) => { prevMatchIdByCourt[c.court] = c.matchId; prevCourtByCourt[c.court] = c; });

        // Replace court snapshot. If a court's match hasn't changed (same
        // round being re-pushed, e.g. after a different court's score saved)
        // and the server already has a completed score for it — possibly
        // submitted by a phone moments before this push arrived — keep that
        // server-side data rather than blindly overwriting with whatever the
        // desktop's own (possibly not-yet-pulled) state says.
        data.courts = body.courts.map((c) => {
          const prev = prevCourtByCourt[c.court];
          const sameMatch = prev && prev.matchId === c.matchId;
          if (sameMatch && prev.complete && !c.complete) {
            return prev; // server's completed score wins over a stale incoming "not complete"
          }
          return {
            court: c.court,
            matchId: c.matchId,
            teamA: c.teamA || [],
            teamB: c.teamB || [],
            scoreA: c.scoreA ?? '',
            scoreB: c.scoreB ?? '',
            complete: !!c.complete,
            submittedBy: c.submittedBy || (sameMatch ? prev?.submittedBy : '') || '',
            submittedAt: c.submittedAt || (sameMatch ? prev?.submittedAt : null) || null,
          };
        });

        // Only clear a court's claim when that court's match actually changed
        // (i.e. it's a new round for that court — different players will be
        // standing there). Re-pushing the SAME round (e.g. after a score save
        // elsewhere) must NOT clear claims, or scorekeepers get logged out
        // mid-round every time anyone else scores.
        const activeCourts = new Set();
        data.courts.forEach((c) => {
          activeCourts.add(c.court);
          if (prevMatchIdByCourt[c.court] !== c.matchId) {
            delete data.claims[c.court];
          }
        });
        // Also drop claims for courts that dropped out of the round entirely.
        Object.keys(data.claims).forEach((courtNum) => {
          if (!activeCourts.has(Number(courtNum))) delete data.claims[courtNum];
        });

        await this.save();
        return this.json({ ok: true });
      }

      // ── GET /pins — organizer's desktop app fetches raw PIN values ───
      // (never exposed via /state, which phones also poll)
      if (url.pathname === '/pins' && request.method === 'GET') {
        return this.json({ ok: true, pins: data.courtPins });
      }

      // ── POST /setpins — organizer sets/updates per-court PINs ────────
      if (url.pathname === '/setpins' && request.method === 'POST') {
        const body = await request.json();
        const pins = body.pins || {}; // { [court]: "1234" or "" to clear }
        if (typeof pins !== 'object') {
          return this.json({ ok: false, error: 'pins object required' }, 400);
        }
        Object.keys(pins).forEach((court) => {
          const val = String(pins[court] || '').trim();
          if (val) data.courtPins[court] = val;
          else delete data.courtPins[court];
        });
        await this.save();
        return this.json({ ok: true, courtPins: data.courtPins });
      }

      // ── POST /announce — organizer posts an announcement to all phones ──
      if (url.pathname === '/announce' && request.method === 'POST') {
        const body = await request.json();
        const text = (body.text || '').trim().slice(0, 280); // keep messages SMS-length, easy to read on a phone
        if (!text) {
          return this.json({ ok: false, error: 'Message text required' }, 400);
        }
        const announcement = { id: this.randomToken().slice(0, 8), text, postedAt: Date.now() };
        data.announcements.unshift(announcement); // newest first
        if (data.announcements.length > 30) data.announcements = data.announcements.slice(0, 30);
        await this.save();
        return this.json({ ok: true, announcement });
      }

      // ── POST /announce-delete — organizer removes one announcement ──────
      if (url.pathname === '/announce-delete' && request.method === 'POST') {
        const body = await request.json();
        const id = (body.id || '').trim();
        if (!id) {
          return this.json({ ok: false, error: 'id required' }, 400);
        }
        data.announcements = data.announcements.filter((a) => a.id !== id);
        await this.save();
        return this.json({ ok: true });
      }

      // ── POST /claim — scorekeeper claims a court ─────────────────────
      if (url.pathname === '/claim' && request.method === 'POST') {
        const body = await request.json();
        const court = Number(body.court);
        const name = (body.name || '').trim();
        const pin = (body.pin || '').trim();
        if (!court || !name) {
          return this.json({ ok: false, error: 'court and name required' }, 400);
        }

        // Enforce the organizer-set PIN for this court, if one exists.
        const requiredPin = data.courtPins[court] || data.courtPins[String(court)];
        if (requiredPin && requiredPin !== pin) {
          return this.json({ ok: false, error: 'Incorrect PIN for this court' }, 403);
        }

        // Verify the claiming name actually belongs to one of the four
        // players scheduled on this court — stops someone from claiming
        // (and scoring) a court they're not part of, by accident or
        // otherwise. Matching is deliberately a little forgiving (first
        // name, minor typos) so legitimate players aren't blocked over
        // small differences in how they typed their own name. When a match
        // is found, we use the ROSTER's name going forward (not whatever
        // was typed) so "submitted by" always shows a real "First Last"
        // name pulled from the schedule, regardless of nicknames/typos.
        //
        // If the typed name plausibly matches MORE THAN ONE roster name
        // (e.g. two players named "John" on the same court, scorekeeper
        // typed just "John"), we deliberately do NOT guess which one —
        // ask for the full name instead. Silently picking one would
        // attribute a score submission to the wrong player with no warning.
        const courtEntry = data.courts.find((c) => c.court === court);
        let resolvedName = name;
        if (courtEntry && courtEntry.teamA && courtEntry.teamA.length) {
          const rosterNames = [...courtEntry.teamA, ...courtEntry.teamB];
          const result = this.matchRosterName(name, rosterNames);
          if (!result) {
            return this.json({
              ok: false,
              error: `"${name}" isn't one of the players on Court ${court} (${rosterNames.join(', ')}). Please select the correct court.`,
              notOnRoster: true,
            }, 403);
          }
          if (result.ambiguous) {
            return this.json({
              ok: false,
              error: `More than one player on Court ${court} matches "${name}" (${result.ambiguous.join(', ')}). Please type your full first and last name.`,
              ambiguous: result.ambiguous,
            }, 409);
          }
          resolvedName = result.name;
        }

        const existing = data.claims[court];
        // Re-claiming with the right PIN (or no PIN required) always succeeds —
        // this lets a scorekeeper reload the page and resume. A *different* PIN
        // value never overrides someone else's claim; the PIN check above is
        // what actually gates entry.
        const token = existing && existing.name === resolvedName ? existing.token : this.randomToken();
        data.claims[court] = { name: resolvedName, token, claimedAt: Date.now() };
        await this.save();
        return this.json({ ok: true, claim: { name: resolvedName, claimedAt: data.claims[court].claimedAt }, token });
      }

      // ── POST /score — scorekeeper submits a score ────────────────────
      if (url.pathname === '/score' && request.method === 'POST') {
        const body = await request.json();
        const court = Number(body.court);
        const scoreA = Number(body.scoreA);
        const scoreB = Number(body.scoreB);
        const submittedBy = (body.submittedBy || '').trim();
        const token = (body.token || '').trim();
        if (!court || Number.isNaN(scoreA) || Number.isNaN(scoreB)) {
          return this.json({ ok: false, error: 'court, scoreA, scoreB required' }, 400);
        }

        // The claiming phone must present the token it was issued on /claim.
        // This stops anyone who didn't successfully claim (i.e. didn't have
        // the right PIN) from submitting a score for this court.
        const claim = data.claims[court];
        if (!claim || claim.token !== token) {
          return this.json({ ok: false, error: 'This court was not claimed by you — claim it again' }, 403);
        }

        const courtEntry = data.courts.find((c) => c.court === court);
        if (!courtEntry) {
          return this.json({ ok: false, error: 'No active match on that court' }, 404);
        }
        // Reject a second submission to an already-completed match outright
        // — this is the actual authoritative gate, not just a UI nicety.
        // Without it, two phones racing the same court (or one phone
        // double-tapping, or a screen that's gone a few seconds stale and
        // missed the redirect-to-waiting-screen that should have happened)
        // would silently overwrite an already-recorded, possibly
        // already-synced-to-desktop score with no warning at all. The
        // client is expected to redirect away from the score-entry screen
        // the moment it sees complete:true (see routeFromState() in
        // mobile.html), so a legitimate scorekeeper should essentially
        // never hit this — it exists for the race/staleness case, not as
        // the primary UX.
        if (courtEntry.complete) {
          return this.json({ ok: false, error: 'A score has already been submitted for this court.', alreadyComplete: true }, 409);
        }
        courtEntry.scoreA = scoreA;
        courtEntry.scoreB = scoreB;
        courtEntry.complete = true;
        courtEntry.submittedBy = submittedBy;
        courtEntry.submittedAt = Date.now();

        data.pending.push({
          court,
          matchId: courtEntry.matchId,
          scoreA,
          scoreB,
          submittedBy,
          submittedAt: Date.now(),
          consumed: false,
        });
        // Keep pending list from growing unbounded
        if (data.pending.length > 200) data.pending = data.pending.slice(-200);

        await this.save();
        return this.json({ ok: true });
      }

      // ── GET /updates — desktop polls this for new submissions ────────
      if (url.pathname === '/updates' && request.method === 'GET') {
        const unconsumed = data.pending.filter((p) => !p.consumed);
        return this.json({ ok: true, updates: unconsumed });
      }

      // ── POST /ack — desktop acks it has consumed submissions ─────────
      if (url.pathname === '/ack' && request.method === 'POST') {
        const body = await request.json();
        const matchIds = new Set((body.matchIds || []).map(String));
        data.pending.forEach((p) => {
          if (matchIds.has(String(p.matchId))) p.consumed = true;
        });
        // Drop old consumed entries to keep storage small
        data.pending = data.pending.filter((p) => !p.consumed).concat(
          data.pending.filter((p) => p.consumed).slice(-20)
        );
        await this.save();
        return this.json({ ok: true });
      }

      return this.json({ ok: false, error: 'Unknown action' }, 404);
    } catch (err) {
      return this.json({ ok: false, error: String(err && err.message ? err.message : err) }, 500);
    }
  }
}
