export function roundHasScore(round) {
  return Array.isArray(round) && round.some(match => match && match.complete === true);
}

export function isRoundStarted(roundIndex, startedRounds = new Set()) {
  if (!startedRounds) return false;

  if (startedRounds instanceof Set) {
    return startedRounds.has(roundIndex);
  }

  if (Array.isArray(startedRounds)) {
    return startedRounds.includes(roundIndex);
  }

  return false;
}

export function isRoundProtected(round, roundIndex, startedRounds = new Set()) {
  return roundHasScore(round) || isRoundStarted(roundIndex, startedRounds);
}

export function protectedRoundCount(schedule = [], startedRounds = new Set()) {
  let lastProtected = -1;

  schedule.forEach((round, index) => {
    if (isRoundProtected(round, index, startedRounds)) {
      lastProtected = index;
    }
  });

  return lastProtected + 1;
}

export function splitProtectedAndDraftRounds(schedule = [], startedRounds = new Set()) {
  const keepCount = protectedRoundCount(schedule, startedRounds);

  return {
    keepCount,
    protectedRounds: schedule.slice(0, keepCount),
    draftRounds: schedule.slice(keepCount)
  };
}
