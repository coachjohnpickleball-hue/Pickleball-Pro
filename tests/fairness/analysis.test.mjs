import assert from 'node:assert/strict';
import {
  playerRating,
  fairnessPairKey,
  fairnessPlayerName,
  buildFairnessAnalysis
} from '../../services/fairness/analysis.mjs';

const players = [
  { name: 'John', clubRating: '4.0' },
  { name: 'Maria', dupr: '3.5' },
  { name: 'Alex', rating: '3.0' },
  { name: 'Sam', clubRating: '2.5' },
  { name: 'Taylor', clubRating: '3.0' }
];

assert.equal(playerRating(players[0]), 4.0);
assert.equal(playerRating(players[1]), 3.5);
assert.equal(playerRating(players[2]), 3.0);
assert.equal(playerRating({ name: 'No Rating' }), 0);

assert.equal(fairnessPairKey(2, 1), '1|2');
assert.equal(fairnessPlayerName(players, 0), 'John');
assert.equal(fairnessPlayerName(players, 99), '?');

const schedule = [
  [
    {
      court: 1,
      teamA: [0, 1],
      teamB: [2, 3],
      complete: true
    }
  ],
  [
    {
      court: 1,
      teamA: [0, 1],
      teamB: [2, 3],
      complete: true
    }
  ]
];

const byeRounds = [
  [4],
  []
];

const analysis = buildFairnessAnalysis({
  players,
  schedule,
  byeRounds
});

assert.equal(analysis.games, 2);
assert.equal(analysis.partner['0|1'], 2);
assert.equal(analysis.partner['2|3'], 2);
assert.equal(analysis.repeatsP.length, 2);

assert.equal(analysis.opponent['0|2'], 2);
assert.equal(analysis.opponent['0|3'], 2);
assert.equal(analysis.repeatsO.length, 4);

assert.equal(analysis.sits[4], 1);
assert.equal(analysis.maxSit, 1);
assert.equal(analysis.minSit, 0);
assert.equal(analysis.sitGap, 1);

assert.equal(analysis.courtEntries.length, 1);
assert.equal(analysis.courtEntries[0].court, '1');
assert.equal(analysis.courtEntries[0].count, 2);

assert.ok(analysis.avgSpread > 0);
assert.ok(analysis.score < 100);
assert.ok(Array.isArray(analysis.recommendations));
assert.ok(analysis.recommendations.length > 0);

console.log('Fairness analysis tests passed');
