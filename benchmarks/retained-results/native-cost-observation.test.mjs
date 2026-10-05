import assert from 'node:assert/strict';
import test from 'node:test';
import {admitNativePhysicalPhases} from './native-physical-phases.mjs';
import {nativeCostObservation} from './native-cost-observation.mjs';

function observation(resident = true) {
  const boundaries = [
    ['task', 1, null, 0, 20],
    ...(resident ? [['environment', 1, null, 1, 6], ['import', 1, 0, 7, 10],
      ['compute', 1, null, 11, 18], ['environment-close', 0, 0, 21, 25]] : []),
    ['task-release', 1, null, 26, 28],
    ...(resident ? [['environment-release', 0, 0, 29, 30]] : []),
  ];
  const events = boundaries.flatMap(([phase, task, producer, begin, end]) =>
    ['begin', 'end'].map((boundary, index) => ({phase, task, producer, boundary,
      success: index === 0 ? null : true, elapsedMicroseconds: index === 0 ? begin : end,
      observerMicroseconds: 0}))).sort((a, b) => a.elapsedMicroseconds - b.elapsedMicroseconds);
  const ownerCorrespondence = {observations: {choices: [{task: 1, name: 'local', resident}]},
    attempts: [{task: 1, environments: resident ? 1 : 0, imports: resident ? 1 : 0}]};
  const taskIntervals = [{task: 1, elapsedMicroseconds: 25}];
  const result = {cleanup_us: 10};
  return {status: 'verified-diagnostic', host: 'native', selectionInput: {phaseObserver: true},
    ownerCorrespondence, taskIntervals, result, physicalPhaseEvents: events,
    physicalPhases: admitNativePhysicalPhases({events, ownerCorrespondence, taskIntervals,
      cleanupMicroseconds: result.cleanup_us})};
}

test('subtract nested shared work once and retain task-owned release and unmodeled cleanup', () => {
  const cost = nativeCostObservation(observation());
  assert.deepEqual(cost.tasks, [{task: 1, realization: 'resident', executionMicroseconds: 12,
    releaseMicroseconds: 2, estimatedMicroseconds: 14}]);
  assert.equal(cost.preparationMicroseconds, 5);
  assert.deepEqual(cost.imports, [{producer: 0, microseconds: 3}]);
  assert.equal(cost.sharedCleanupMicroseconds, 5);
  assert.equal(cost.otherCleanupMicroseconds, 3);
});
test('use identical task/release boundaries for Local without invented shared work', () => {
  const cost = nativeCostObservation(observation(false));
  assert.equal(cost.tasks[0].estimatedMicroseconds, 22);
  assert.equal(cost.tasks[0].realization, 'local');
  assert.equal(cost.sharedCleanupMicroseconds, 0);
  assert.equal(cost.otherCleanupMicroseconds, 8);
});
test('reject a rate projection changed without changing actual boundary events', () => {
  const value = observation(); value.physicalPhases.taskReleaseIntervals[0].elapsedMicroseconds = 1;
  assert.throws(() => nativeCostObservation(value), /NativeCostPhaseProjectionMismatch/);
});
test('reject missing underlying events rather than trusting cost labels', () => {
  const value = observation(); delete value.physicalPhaseEvents;
  assert.throws(() => nativeCostObservation(value), /MissingNativePhysicalPhaseEvents/);
});
test('reject an observer-disabled observation', () => {
  const value = observation(); value.selectionInput.phaseObserver = false;
  assert.throws(() => nativeCostObservation(value), /NativeCostRequiresActualPhaseObserver/);
});
