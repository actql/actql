// Duration estimates from the same execution/release boundaries for each
// realization. Nested resident preparation/import is subtracted once, never
// added to the enclosing task. This is not a physical memory or work bound.
import assert from 'node:assert/strict';
import {admitNativePhysicalPhases} from './native-physical-phases.mjs';

export function nativeCostObservation(observation) {
  assert.equal(observation.status, 'verified-diagnostic');
  assert.equal(observation.host, 'native');
  assert.equal(observation.selectionInput?.phaseObserver, true,
    'NativeCostRequiresActualPhaseObserver');
  const phases = admitNativePhysicalPhases({events: observation.physicalPhaseEvents,
    ownerCorrespondence: observation.ownerCorrespondence,
    taskIntervals: observation.taskIntervals,
    cleanupMicroseconds: observation.result.cleanup_us});
  assert.deepEqual(observation.physicalPhases, phases,
    'NativeCostPhaseProjectionMismatch');
  const sum = intervals => intervals.reduce((total, item) => total + item.elapsedMicroseconds, 0);
  const tasks = phases.taskExecutionIntervals.map(outer => {
    const choice = observation.ownerCorrespondence.observations.choices.find(item => item.task === outer.task);
    const shared = phases.intervals.filter(item => item.task === outer.task &&
      ['environment', 'import'].includes(item.phase));
    const release = phases.taskReleaseIntervals.find(item => item.task === outer.task);
    const execution = outer.elapsedMicroseconds - sum(shared);
    const total = execution + release.elapsedMicroseconds;
    assert(Number.isSafeInteger(total) && total >= 0, 'InvalidNativeTaskCost');
    return {task: outer.task, realization: choice.resident ? 'resident' : choice.name,
      executionMicroseconds: execution, releaseMicroseconds: release.elapsedMicroseconds,
      estimatedMicroseconds: total};
  });
  const preparationMicroseconds = sum(phases.intervals.filter(item => item.phase === 'environment'));
  const imports = phases.intervals.filter(item => item.phase === 'import').map(item => ({
    producer: item.producer, microseconds: item.elapsedMicroseconds}));
  const sharedCleanupMicroseconds = sum(phases.environmentCleanupIntervals);
  const otherCleanupMicroseconds = observation.result.cleanup_us - sharedCleanupMicroseconds -
    sum(phases.taskReleaseIntervals);
  // Retain whole-cycle/acquisition/planner/identity observations separately;
  // these task rates must never be presented as total process latency.
  return {tasks, preparationMicroseconds, imports, sharedCleanupMicroseconds,
    otherCleanupMicroseconds,
    scope: 'selected task execution plus its final owner release; resident preparation/import/shared environment cleanup charged separately'};
}
