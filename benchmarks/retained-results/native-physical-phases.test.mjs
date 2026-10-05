import assert from 'node:assert/strict';
import test from 'node:test';
import {admitNativePhysicalPhases} from './native-physical-phases.mjs';

function example() {
  const events = [];
  let clock = 10;
  for (const [phase, task, producer] of [
    ['environment', 1, null], ['import', 1, 0], ['compute', 1, null],
    ['compute', 2, null],
  ]) {
    events.push({phase, task, producer, boundary: 'begin', success: null,
      elapsedMicroseconds: clock, observerMicroseconds: 1});
    clock += 5;
    events.push({phase, task, producer, boundary: 'end', success: true,
      elapsedMicroseconds: clock, observerMicroseconds: 1});
    clock++;
  }
  return {events, taskIntervals: [{task: 1, elapsedMicroseconds: 25},
    {task: 2, elapsedMicroseconds: 10}], ownerCorrespondence: {
    observations: {choices: [{task: 1, resident: true}, {task: 2, resident: true}]},
    attempts: [{task: 1, environments: 1, imports: 1},
      {task: 2, environments: 0, imports: 0}],
  }};
}

test('environment and import occur once; reused input incurs only actual Compute', () => {
  const result = admitNativePhysicalPhases(example());
  assert.deepEqual(result.intervals.map(item =>
    [item.task, item.phase, item.elapsedMicroseconds]),
  [[1, 'environment', 5], [1, 'import', 5], [1, 'compute', 5], [2, 'compute', 5]]);
});

for (const [name, change, issue] of [
  ['missing import', input => {input.events.splice(2, 2);}, /NativeImportPhaseCountMismatch/],
  ['missing environment', input => {input.events.splice(0, 2);}, /NativeEnvironmentPhaseCountMismatch/],
  ['missing resident Compute', input => {input.events.splice(6, 2);}, /NativeComputePhaseCountMismatch/],
  ['unfinished interval', input => {input.events.pop();}, /UnclosedNativePhysicalPhase/],
  ['wrong producer at end', input => {input.events[3].producer = -1;}, /InvalidNativePhysicalPhaseProducer/],
  ['future producer', input => {input.events[2].producer = 1;}, /InvalidNativePhysicalPhaseProducer/],
  ['physical failure', input => {input.events[3].success = false;}, /FailedNativePhysicalPhase/],
  ['overlapping interval', input => {input.events[1].boundary = 'begin';}, /OverlappingNativePhysicalPhase/],
  ['clock retreat', input => {input.events[3].elapsedMicroseconds = 1;}, /NativePhysicalPhaseClockRetreat/],
  ['excess time', input => {input.taskIntervals[0].elapsedMicroseconds = 10;}, /NativePhysicalPhasesExceedTaskInterval/],
  ['fresh choice', input => {input.ownerCorrespondence.observations.choices[0].resident = false;}, /NativePhysicalPhaseWithoutResidentChoice/],
]) test(`refuse ${name}`, () => {
  const input = example(); change(input);
  assert.throws(() => admitNativePhysicalPhases(input), issue);
});

test('fresh-only choices have no invented preparation/import observations', () => {
  const input = example();
  input.events = [];
  for (const choice of input.ownerCorrespondence.observations.choices) choice.resident = false;
  for (const attempt of input.ownerCorrespondence.attempts) {
    attempt.environments = 0; attempt.imports = 0;
  }
  assert.deepEqual(admitNativePhysicalPhases(input).intervals, []);
});
