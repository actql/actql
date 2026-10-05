// Intervals emitted by the actual synchronous Native Host boundaries. Counts
// are cross-checked against the existing admitted Owner observations. These
// durations are estimates, not logical work or capacity bounds.
import assert from 'node:assert/strict';

const safe = value => Number.isSafeInteger(value) && value >= 0;
const sameBoundary = (left, right) => left.phase === right.phase &&
  left.task === right.task && left.producer === right.producer;

export function admitNativePhysicalPhases({events, ownerCorrespondence, taskIntervals}) {
  assert(Array.isArray(events), 'MissingNativePhysicalPhaseEvents');
  const choices = ownerCorrespondence.observations.choices;
  const attempts = ownerCorrespondence.attempts;
  const durations = new Map(taskIntervals.map(item => [item.task, item.elapsedMicroseconds]));
  const intervals = [];
  let previous = -1;
  let pending;
  for (const event of events) {
    assert(['environment', 'import', 'compute'].includes(event.phase) &&
      ['begin', 'end'].includes(event.boundary) && safe(event.task) && event.task > 0 &&
      safe(event.elapsedMicroseconds) && safe(event.observerMicroseconds),
    'InvalidNativePhysicalPhaseEvent');
    assert(event.elapsedMicroseconds >= previous, 'NativePhysicalPhaseClockRetreat');
    previous = event.elapsedMicroseconds;
    assert(choices.some(choice => choice.task === event.task && choice.resident),
      'NativePhysicalPhaseWithoutResidentChoice');
    assert(event.phase === 'import'
      ? safe(event.producer) && event.producer < event.task : event.producer === null,
    'InvalidNativePhysicalPhaseProducer');
    if (event.boundary === 'begin') {
      assert(!pending && event.success === null, 'OverlappingNativePhysicalPhase');
      pending = event;
    } else {
      assert(pending && sameBoundary(pending, event), 'UnmatchedNativePhysicalPhaseEnd');
      assert.equal(event.success, true, 'FailedNativePhysicalPhase');
      intervals.push({phase: event.phase, task: event.task, producer: event.producer,
        elapsedMicroseconds: event.elapsedMicroseconds - pending.elapsedMicroseconds,
        clockObservationMicroseconds: pending.observerMicroseconds + event.observerMicroseconds});
      pending = undefined;
    }
  }
  assert(!pending, 'UnclosedNativePhysicalPhase');
  for (const attempt of attempts) {
    const phases = intervals.filter(item => item.task === attempt.task);
    const ranks = phases.map(item => ['environment', 'import', 'compute'].indexOf(item.phase));
    assert(ranks.every((rank, index) => !index || rank >= ranks[index - 1]),
      'NativePhysicalPhaseOrderMismatch');
    assert.equal(phases.filter(item => item.phase === 'environment').length,
      attempt.environments, 'NativeEnvironmentPhaseCountMismatch');
    const imports = phases.filter(item => item.phase === 'import');
    assert.equal(imports.length, attempt.imports, 'NativeImportPhaseCountMismatch');
    assert.equal(new Set(imports.map(item => item.producer)).size, imports.length,
      'DuplicateNativePhysicalImport');
    assert.equal(phases.filter(item => item.phase === 'compute').length,
      choices.find(choice => choice.task === attempt.task).resident ? 1 : 0,
    'NativeComputePhaseCountMismatch');
    const span = phases.reduce((total, phase) => total + phase.elapsedMicroseconds, 0);
    assert(safe(span) && safe(durations.get(attempt.task)) &&
      span <= durations.get(attempt.task), 'NativePhysicalPhasesExceedTaskInterval');
  }
  return Object.freeze({intervals,
    scope: 'serial physical preparation/import/resident-task intervals; excludes planner and final Run cleanup',
    observerCostScope: 'clock observation only; buffering/callback overhead remains in process time and requires off/on measurement'});
}
