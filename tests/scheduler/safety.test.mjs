import assert from 'node:assert/strict';
import {
  roundHasScore,
  isRoundStarted,
  isRoundProtected,
  protectedRoundCount,
  splitProtectedAndDraftRounds
} from '../../services/scheduler/safety.mjs';

const schedule = [
  [
    { id: 1, complete: true },
    { id: 2, complete: false }
  ],
  [
    { id: 3, complete: false }
  ],
  [
    { id: 4, complete: false }
  ]
];

assert.equal(roundHasScore(schedule[0]), true);
assert.equal(roundHasScore(schedule[1]), false);

assert.equal(isRoundStarted(1, new Set([1])), true);
assert.equal(isRoundStarted(2, new Set([1])), false);

assert.equal(isRoundProtected(schedule[0], 0, new Set()), true);
assert.equal(isRoundProtected(schedule[1], 1, new Set([1])), true);
assert.equal(isRoundProtected(schedule[2], 2, new Set([1])), false);

assert.equal(protectedRoundCount(schedule, new Set([1])), 2);

const split = splitProtectedAndDraftRounds(schedule, new Set([1]));

assert.equal(split.keepCount, 2);
assert.equal(split.protectedRounds.length, 2);
assert.equal(split.draftRounds.length, 1);

console.log('Scheduler safety tests passed');
