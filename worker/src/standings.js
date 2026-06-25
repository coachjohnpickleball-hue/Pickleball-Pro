/**
 * computeStandings — pure win/loss/points tally.
 *
 * Extracted from renderStandings() in public/index.html. This is
 * deliberately ONLY the calculation: filtering (search/gender/pod/min-played),
 * sorting, and HTML rendering all stay client-side in renderStandings(),
 * which now calls this Worker for the numbers and does the rest itself —
 * those are normal UI concerns, not logic worth hiding server-side.
 *
 * Input shape:
 *   players: [{ name, gender, dupr, clubRating, ... }, ...]   (index = player id)
 *   schedule: [ [match, match, ...], [match, ...], ... ]       (array of rounds)
 *     match: { teamA: [playerIdx, ...], teamB: [playerIdx, ...],
 *               scoreA, scoreB, complete, podLabel? }
 *
 * Output shape:
 *   { [playerIdx]: { idx, played, wins, losses, pts, pct } }
 *
 * Scoring (matches the original exactly): win = 2 pts, tie = 1 pt, loss = 0.
 */
export function computeStandings(players, schedule) {
  const stats = {};
  players.forEach((p, i) => {
    stats[i] = { idx: i, played: 0, wins: 0, losses: 0, pts: 0, pct: 0 };
  });

  schedule
    .flat()
    .filter((m) => m.complete)
    .forEach((m) => {
      m.teamA.forEach((pi) => {
        if (!stats[pi]) return; // defensive: ignore unknown player indices
        stats[pi].played++;
        if (m.scoreA > m.scoreB) { stats[pi].wins++; stats[pi].pts += 2; }
        else if (m.scoreA < m.scoreB) { stats[pi].losses++; }
        else { stats[pi].pts += 1; }
      });
      m.teamB.forEach((pi) => {
        if (!stats[pi]) return;
        stats[pi].played++;
        if (m.scoreB > m.scoreA) { stats[pi].wins++; stats[pi].pts += 2; }
        else if (m.scoreB < m.scoreA) { stats[pi].losses++; }
        else { stats[pi].pts += 1; }
      });
    });

  Object.values(stats).forEach((s) => { s.pct = s.played ? s.wins / s.played : 0; });

  return stats;
}
