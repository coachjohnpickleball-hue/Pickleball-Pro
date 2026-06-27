import assert from 'node:assert/strict';
import { computeStandings } from '../../worker/src/standings.js';

const players = [
  { name: 'John' },
  { name: 'Maria' },
  { name: 'Alex' },
  { name: 'Sam' },
  { name: 'Taylor' }
];

const schedule = [
  [
    {
      teamA: [0, 1],
      teamB: [2, 3],
      scoreA: 11,
      scoreB: 7,
      complete: true
    },
    {
      teamA: [0, 2],
      teamB: [1, 3],
      scoreA: 8,
      scoreB: 8,
      complete: true
    }
  ],
  [
    {
      teamA: [0, 3],
      teamB: [1, 2],
      scoreA: 4,
      scoreB: 11,
      complete: true
    },
    {
      teamA: [0, 1],
      teamB: [2, 3],
      scoreA: 0,
      scoreB: 0,
      complete: false
    }
  ]
];

const stats = computeStandings(players, schedule);

// John: win, tie, loss = 3 played, 1 win, 1 loss, 3 pts
assert.equal(stats[0].played, 3);
assert.equal(stats[0].wins, 1);
assert.equal(stats[0].losses, 1);
assert.equal(stats[0].pts, 3);
assert.equal(stats[0].pct, 1 / 3);

// Maria: win, tie, win = 3 played, 2 wins, 0 losses, 5 pts
assert.equal(stats[1].played, 3);
assert.equal(stats[1].wins, 2);
assert.equal(stats[1].losses, 0);
assert.equal(stats[1].pts, 5);
assert.equal(stats[1].pct, 2 / 3);

// Alex: loss, tie, win = 3 played, 1 win, 1 loss, 3 pts
assert.equal(stats[2].played, 3);
assert.equal(stats[2].wins, 1);
assert.equal(stats[2].losses, 1);
assert.equal(stats[2].pts, 3);

// Sam: loss, tie, loss = 3 played, 0 wins, 2 losses, 1 pt
assert.equal(stats[3].played, 3);
assert.equal(stats[3].wins, 0);
assert.equal(stats[3].losses, 2);
assert.equal(stats[3].pts, 1);

// Taylor: never played
assert.equal(stats[4].played, 0);
assert.equal(stats[4].wins, 0);
assert.equal(stats[4].losses, 0);
assert.equal(stats[4].pts, 0);
assert.equal(stats[4].pct, 0);

console.log('Standings tests passed');
