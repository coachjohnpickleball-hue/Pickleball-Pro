import assert from "node:assert/strict";
import {
  matchHasScore,
  roundHasScore,
  createRoundSnapshot,
  restoreRoundSnapshot
} from "../../lib/roundSnapshots.mjs";

const state = {
  schedule: [
    [
      { id: "r1m1", court: 1, teamA: ["A", "B"], teamB: ["C", "D"], scoreA: 11, scoreB: 8, complete: true },
      { id: "r1m2", court: 2, teamA: ["E", "F"], teamB: ["G", "H"], scoreA: 9, scoreB: 11, complete: true }
    ],
    [
      { id: "r2m1", court: 1, teamA: ["A", "C"], teamB: ["B", "D"] }
    ]
  ],
  roundTeams: [
    [["A", "B"], ["C", "D"]],
    [["A", "C"], ["B", "D"]]
  ],
  byeRounds: [
    [],
    ["H"]
  ],
  startedRounds: new Set([0])
};

assert.equal(matchHasScore(state.schedule[0][0]), true);
assert.equal(matchHasScore(state.schedule[1][0]), false);
assert.equal(roundHasScore(state.schedule[0]), true);
assert.equal(roundHasScore(state.schedule[1]), false);

const snapshot = createRoundSnapshot(state, 0, "test snapshot");

assert.equal(snapshot.roundIndex, 0);
assert.equal(snapshot.roundNumber, 1);
assert.equal(snapshot.scoreCount, 2);
assert.equal(snapshot.matchCount, 2);
assert.deepEqual(snapshot.startedRounds, [0]);

state.schedule[0][0].scoreA = 0;
state.schedule[0][0].scoreB = 0;
state.schedule[0][0].complete = false;

restoreRoundSnapshot(state, snapshot);

assert.equal(state.schedule[0][0].scoreA, 11);
assert.equal(state.schedule[0][0].scoreB, 8);
assert.equal(state.schedule[0][0].complete, true);
assert.equal(state.startedRounds instanceof Set, true);
assert.equal(state.startedRounds.has(0), true);

console.log("Round snapshot tests passed");
