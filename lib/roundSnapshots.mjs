export function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

export function hasScoreValue(value) {
  return value !== undefined && value !== null && String(value).trim() !== "";
}

export function matchHasScore(match) {
  if (!match) return false;

  return match.complete === true ||
    match.completed === true ||
    hasScoreValue(match.scoreA) ||
    hasScoreValue(match.scoreB) ||
    hasScoreValue(match.aScore) ||
    hasScoreValue(match.bScore) ||
    hasScoreValue(match.teamAScore) ||
    hasScoreValue(match.teamBScore) ||
    hasScoreValue(match.pointsA) ||
    hasScoreValue(match.pointsB);
}

export function roundHasScore(round) {
  return Array.isArray(round) && round.some(matchHasScore);
}

export function createRoundSnapshot(state, roundIndex, reason = "manual snapshot") {
  if (!state || !Array.isArray(state.schedule)) {
    throw new Error("Invalid tournament state");
  }

  const round = state.schedule[roundIndex];

  if (!Array.isArray(round)) {
    throw new Error(`Round ${roundIndex + 1} does not exist`);
  }

  if (!roundHasScore(round)) {
    return null;
  }

  const startedRounds = state.startedRounds instanceof Set
    ? Array.from(state.startedRounds)
    : Array.isArray(state.startedRounds)
      ? state.startedRounds.slice()
      : [];

  return {
    id: `round_${roundIndex + 1}_${Date.now()}`,
    createdAt: new Date().toISOString(),
    reason,
    roundIndex,
    roundNumber: roundIndex + 1,
    scoreCount: round.filter(matchHasScore).length,
    matchCount: round.length,
    round: deepClone(round),
    roundTeams: deepClone((state.roundTeams || [])[roundIndex] || []),
    byeRound: deepClone((state.byeRounds || [])[roundIndex] || []),
    startedRounds
  };
}

export function restoreRoundSnapshot(state, snapshot) {
  if (!state || !snapshot) {
    throw new Error("State and snapshot are required");
  }

  if (!Array.isArray(state.schedule)) state.schedule = [];
  if (!Array.isArray(state.roundTeams)) state.roundTeams = [];
  if (!Array.isArray(state.byeRounds)) state.byeRounds = [];

  state.schedule[snapshot.roundIndex] = deepClone(snapshot.round);
  state.roundTeams[snapshot.roundIndex] = deepClone(snapshot.roundTeams || []);
  state.byeRounds[snapshot.roundIndex] = deepClone(snapshot.byeRound || []);
  state.startedRounds = new Set(snapshot.startedRounds || []);

  return state;
}
