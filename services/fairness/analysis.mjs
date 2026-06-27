export function playerRating(player) {
  if (!player) return 0;

  if (player.clubRating) {
    const n = parseFloat(player.clubRating);
    if (!Number.isNaN(n) && n > 0) return n;
  }

  if (player.dupr != null) {
    const n = parseFloat(player.dupr);
    if (!Number.isNaN(n) && n > 0) return n;
  }

  if (player.rating != null) {
    const n = parseFloat(player.rating);
    if (!Number.isNaN(n) && n > 0) return n;
  }

  return 0;
}

export function fairnessPairKey(a, b) {
  return [a, b]
    .sort((x, y) => String(x).localeCompare(String(y)))
    .join('|');
}

export function fairnessPlayerName(players, index) {
  const player = players[parseInt(index, 10)];
  return player && player.name ? player.name : '?';
}

export function buildFairnessAnalysis({ players = [], schedule = [], byeRounds = [] } = {}) {
  const partner = {};
  const opponent = {};
  const sits = {};
  const playerCourtUse = {};
  const courtTotals = {};
  const spreads = [];
  const gameSpreads = [];

  players.forEach((player, index) => {
    sits[index] = 0;
    playerCourtUse[index] = {};
  });

  byeRounds.forEach((roundByes) => {
    (roundByes || []).forEach((index) => {
      sits[index] = (sits[index] || 0) + 1;
    });
  });

  schedule.forEach((round, roundIndex) => {
    (round || []).forEach((match, matchIndex) => {
      if (!match || !Array.isArray(match.teamA) || !Array.isArray(match.teamB)) return;

      const court = match.court || matchIndex + 1;
      courtTotals[court] = (courtTotals[court] || 0) + 1;

      const allPlayers = [].concat(match.teamA, match.teamB);

      allPlayers.forEach((index) => {
        if (sits[index] == null) sits[index] = 0;
        playerCourtUse[index] = playerCourtUse[index] || {};
        playerCourtUse[index][court] = (playerCourtUse[index][court] || 0) + 1;
      });

      if (match.teamA.length > 1) {
        const key = fairnessPairKey(match.teamA[0], match.teamA[1]);
        partner[key] = (partner[key] || 0) + 1;
      }

      if (match.teamB.length > 1) {
        const key = fairnessPairKey(match.teamB[0], match.teamB[1]);
        partner[key] = (partner[key] || 0) + 1;
      }

      match.teamA.forEach((a) => {
        match.teamB.forEach((b) => {
          const key = fairnessPairKey(a, b);
          opponent[key] = (opponent[key] || 0) + 1;
        });
      });

      const avgA = match.teamA.length
        ? match.teamA.reduce((sum, index) => sum + playerRating(players[index]), 0) / match.teamA.length
        : 0;

      const avgB = match.teamB.length
        ? match.teamB.reduce((sum, index) => sum + playerRating(players[index]), 0) / match.teamB.length
        : 0;

      const spread = Math.abs(avgA - avgB);
      spreads.push(spread);

      gameSpreads.push({
        round: roundIndex + 1,
        court,
        spread,
        teamA: match.teamA,
        teamB: match.teamB
      });
    });
  });

  const repeatsP = Object.entries(partner)
    .filter(([, count]) => count > 1)
    .sort((a, b) => b[1] - a[1]);

  const repeatsO = Object.entries(opponent)
    .filter(([, count]) => count > 1)
    .sort((a, b) => b[1] - a[1]);

  const sitEntries = Object.entries(sits)
    .map(([index, count]) => ({
      idx: parseInt(index, 10),
      name: fairnessPlayerName(players, index),
      c: Number(count) || 0
    }))
    .sort((a, b) => b.c - a.c || a.name.localeCompare(b.name));

  const sitVals = sitEntries.map((entry) => entry.c);
  const maxSit = sitVals.length ? Math.max(...sitVals) : 0;
  const minSit = sitVals.length ? Math.min(...sitVals) : 0;
  const sitGap = maxSit - minSit;

  const sitDistribution = sitEntries.reduce((acc, entry) => {
    acc[entry.c] = (acc[entry.c] || 0) + 1;
    return acc;
  }, {});

  const mostSat = sitEntries.filter((entry) => entry.c === maxSit && maxSit > 0);
  const leastSat = sitEntries.filter((entry) => entry.c === minSit);

  const avgSpread = spreads.length ? spreads.reduce((a, b) => a + b, 0) / spreads.length : 0;
  const bestSpread = spreads.length ? Math.min(...spreads) : 0;
  const worstSpread = spreads.length ? Math.max(...spreads) : 0;

  const worstGames = gameSpreads
    .slice()
    .sort((a, b) => b.spread - a.spread)
    .slice(0, 5);

  const courtEntries = Object.entries(courtTotals)
    .map(([court, count]) => ({ court, count }))
    .sort((a, b) => String(a.court).localeCompare(String(b.court), undefined, { numeric: true }));

  const courtVals = courtEntries.map((entry) => entry.count);
  const courtGap = courtVals.length ? Math.max(...courtVals) - Math.min(...courtVals) : 0;

  let score = 100;
  score -= Math.min(30, repeatsP.length * 8);
  score -= Math.min(25, repeatsO.length * 5);
  score -= Math.min(25, Math.max(0, sitGap - 1) * 12);
  score -= Math.min(10, Math.max(0, courtGap - 1) * 4);
  score -= Math.min(20, Math.max(0, avgSpread - 0.75) * 10);
  score = Math.max(0, Math.round(score));

  const grade =
    score >= 90 ? 'Excellent'
      : score >= 75 ? 'Good'
        : score >= 60 ? 'Needs attention'
          : 'Poor';

  const recommendations = [];

  if (repeatsP.length) recommendations.push('Avoid the repeated partner pairings shown below in the next round.');
  if (repeatsO.length) recommendations.push('Reduce repeated opponent matchups where possible.');
  if (sitGap > 1) recommendations.push('Prioritize players with the most sit-outs next round: ' + mostSat.slice(0, 6).map((x) => x.name).join(', ') + '.');
  if (courtGap > 1) recommendations.push('Court usage is uneven; rotate assignments across courts more evenly.');
  if (avgSpread > 1.25) recommendations.push('Rating spread is high; use balanced/DUPR mode or swap players between games.');
  if (!recommendations.length) recommendations.push('Schedule looks balanced based on current data.');

  return {
    partner,
    opponent,
    repeatsP,
    repeatsO,
    sits,
    sitEntries,
    sitDistribution,
    mostSat,
    leastSat,
    playerCourtUse,
    courtEntries,
    courtGap,
    maxSit,
    minSit,
    sitGap,
    avgSpread,
    bestSpread,
    worstSpread,
    worstGames,
    games: spreads.length,
    score,
    grade,
    recommendations
  };
}
