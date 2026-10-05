import assert from 'node:assert/strict';
import test from 'node:test';
import {admitNativePhysicalPhases} from './native-physical-phases.mjs';

function example(resident = true) {
  const events = [];
  let clock = 10;
  const boundary = (phase, task, producer, kind) => events.push({phase, task, producer,
    boundary: kind, success: kind === 'begin' ? null : true,
    elapsedMicroseconds: clock++, observerMicroseconds: 1});
  const interval = (phase, task, producer) => {
    boundary(phase, task, producer, 'begin'); clock += 4;
    boundary(phase, task, producer, 'end');
  };
  for (const task of [1, 2]) {
    boundary('task', task, null, 'begin');
    if (resident) {
      if (task === 1) {
        interval('environment', task, null); interval('import', task, 0);
      }
      interval('compute', task, null);
    } else clock += 5;
    boundary('task', task, null, 'end');
  }
  if (resident) interval('environment-close', 0, 0);
  interval('task-release', 2, null); interval('task-release', 1, null);
  if (resident) interval('environment-release', 0, 0);
  return {events, cleanupMicroseconds: 30,
    taskIntervals: [{task: 1, elapsedMicroseconds: 25}, {task: 2, elapsedMicroseconds: 10}],
    ownerCorrespondence: {
      observations: {choices: [{task: 1, resident}, {task: 2, resident}]},
      attempts: [{task: 1, environments: resident ? 1 : 0, imports: resident ? 1 : 0},
        {task: 2, environments: 0, imports: 0}],
    }};
}
const removePhase = (input, phase, task) => {
  input.events = input.events.filter(event => !(event.phase === phase &&
    (task === undefined || event.task === task)));
};
const at = (input, phase, kind) => input.events.find(event =>
  event.phase === phase && event.boundary === kind);

test('measure matched outer tasks, nested resident work and owned cleanup separately', () => {
  const result = admitNativePhysicalPhases(example());
  assert.deepEqual(result.intervals.map(item => [item.task, item.phase, item.elapsedMicroseconds]),
    [[1, 'environment', 5], [1, 'import', 5], [1, 'compute', 5], [2, 'compute', 5]]);
  assert.deepEqual(result.taskExecutionIntervals.map(item => item.elapsedMicroseconds), [19, 7]);
  assert.deepEqual(result.taskReleaseIntervals.map(item => item.task), [2, 1]);
  assert.deepEqual(result.environmentCleanupIntervals.map(item => item.phase),
    ['environment-close', 'environment-release']);
});

for (const [name, change, issue] of [
  ['missing import', input => removePhase(input, 'import'), /NativeImportPhaseCountMismatch/],
  ['missing environment', input => removePhase(input, 'environment'), /NativeEnvironmentPhaseCountMismatch/],
  ['missing resident Compute', input => removePhase(input, 'compute', 2), /NativeComputePhaseCountMismatch/],
  ['unfinished interval', input => input.events.pop(), /UnclosedNativePhysicalPhase/],
  ['wrong producer at end', input => {at(input, 'import', 'end').producer = 2;}, /InvalidNativePhysicalPhaseProducer/],
  ['future producer', input => {at(input, 'import', 'begin').producer = 1;}, /InvalidNativePhysicalPhaseProducer/],
  ['physical failure', input => {at(input, 'import', 'end').success = false;}, /FailedNativePhysicalPhase/],
  ['overlapping child', input => {
    const event = at(input, 'environment', 'end'); event.boundary = 'begin'; event.success = null;
  }, /NativePhysicalChildOutsideTask/],
  ['clock retreat', input => {at(input, 'import', 'end').elapsedMicroseconds = 1;}, /NativePhysicalPhaseClockRetreat/],
  ['excess task time', input => {input.taskIntervals[0].elapsedMicroseconds = 10;}, /NativePhysicalPhasesExceedTaskInterval/],
  ['unbound resident choice', input => {input.ownerCorrespondence.observations.choices[0].resident = false;}, /NativePhysicalPhaseWithoutResidentChoice/],
  ['child outside task', input => removePhase(input, 'task', 1), /NativePhysicalChildOutsideTask/],
  ['missing task release', input => removePhase(input, 'task-release', 1), /NativeTaskReleasePhaseCountMismatch/],
  ['duplicate task release', input => {
    for (const event of input.events.filter(item => item.phase === 'task-release' && item.task === 2)) event.task = 1;
  }, /NativeTaskReleasePhaseCountMismatch/],
  ['missing environment close', input => removePhase(input, 'environment-close'), /NativeEnvironmentCleanupCountMismatch/],
  ['wrong environment release', input => {
    for (const event of input.events.filter(item => item.phase === 'environment-release')) event.producer = 1;
  }, /NativeEnvironmentCleanupCountMismatch/],
  ['cleanup before environment stop', input => {
    for (const event of input.events.filter(item => item.phase === 'environment-close')) {
      event.phase = 'task-release'; event.task = 1; event.producer = null;
    }
    for (const event of input.events.filter(item => item.phase === 'task-release' && item.task === 2)) {
      event.phase = 'environment-close'; event.task = 0; event.producer = 0;
    }
  }, /NativeCleanupPhaseOrderMismatch/],
  ['excess cleanup time', input => {input.cleanupMicroseconds = 19;}, /NativePhysicalPhasesExceedCleanupInterval/],
]) test(`refuse ${name}`, () => {
  const input = example(); change(input);
  assert.throws(() => admitNativePhysicalPhases(input), issue);
});

test('fresh-only choices have matched task/release intervals and no invented resident work', () => {
  const result = admitNativePhysicalPhases(example(false));
  assert.deepEqual(result.intervals, []);
  assert.equal(result.taskExecutionIntervals.length, 2);
  assert.equal(result.taskReleaseIntervals.length, 2);
  assert.deepEqual(result.environmentCleanupIntervals, []);
});
