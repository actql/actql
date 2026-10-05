// Intervals emitted by the actual synchronous Native Host boundaries. Counts
// are cross-checked against the existing admitted Owner observations. These
// durations are estimates, not logical work or capacity bounds.
import assert from 'node:assert/strict';

const safe = value => Number.isSafeInteger(value) && value >= 0;
const sameBoundary = (left, right) => left.phase === right.phase &&
  left.task === right.task && left.producer === right.producer;

// These labels mark the start of the named operation. Keep the enclosing
// intervals separate from nested physical phases and parent process time.
export function nativePreparationObservations(stdout, expectedReadOnly) {
  assert(typeof expectedReadOnly === 'boolean', 'MissingNativeSourceOpenExpectation');
  const modes = stdout.split('\n').filter(line => line.startsWith('source-open-mode:'));
  assert.deepEqual(modes, ['source-open-mode:' + (expectedReadOnly ? 'read-only' : 'read-write')],
    'NativeSourceOpenModeMismatch');
  const names = ['application', 'library', 'database', 'acquisition-start',
    'acquisition-execute', 'acquisition-output', 'source', 'capture', 'dispatch',
    'strategy-open', 'strategy-execute', 'output-cid', 'execution-end', 'cleanup-end'];
  const boundaries = stdout.split('\n').filter(line => line.startsWith('phase-time-us:'))
    .map(line => {
      const match = /^phase-time-us:([a-z-]+):(0|[1-9][0-9]*)$/.exec(line);
      assert(match, 'InvalidNativePreparationBoundary');
      const microseconds = Number(match[2]);
      assert(safe(microseconds), 'InvalidNativePreparationClock');
      return {name: match[1], microseconds};
    });
  assert.deepEqual(boundaries.map(item => item.name), names, 'NativePreparationBoundaryMismatch');
  assert(boundaries.every((item, index) => !index ||
    item.microseconds >= boundaries[index - 1].microseconds), 'NativePreparationClockRetreat');
  const at = Object.fromEntries(boundaries.map(item => [item.name, item.microseconds]));
  const elapsed = (start, end) => (at[end] - at[start]) / 1000;
  return Object.freeze({sourceReadOnly: expectedReadOnly, boundaries,
    applicationMs: elapsed('application', 'library'),
    libraryMs: elapsed('library', 'database'),
    databaseMs: elapsed('database', 'acquisition-start'),
    acquisitionMs: elapsed('acquisition-start', 'acquisition-output'),
    sourceMaterializationMs: elapsed('acquisition-output', 'capture'),
    captureMs: elapsed('capture', 'dispatch'),
    dispatchMs: elapsed('dispatch', 'strategy-execute'),
    computeAndIdentityMs: elapsed('strategy-execute', 'execution-end'),
    cleanupMs: elapsed('execution-end', 'cleanup-end'),
    scope: 'monotonic enclosing operation-start boundaries; not additive with nested task phases'});
}

export function admitNativePhysicalPhases({events, ownerCorrespondence, taskIntervals,
  cleanupMicroseconds}) {
  assert(Array.isArray(events), 'MissingNativePhysicalPhaseEvents');
  const choices = ownerCorrespondence.observations.choices;
  const attempts = ownerCorrespondence.attempts;
  const durations = new Map(taskIntervals.map(item => [item.task, item.elapsedMicroseconds]));
  const intervals = [];
  const taskExecutionIntervals = [], taskReleaseIntervals = [], environmentCleanupIntervals = [];
  let previous = -1;
  const pending = [];
  let cleanup = false, cleanupRank = -1;
  const childPhases = ['environment', 'import', 'compute'];
  const cleanupPhases = ['environment-close', 'task-release', 'environment-release'];
  for (const event of events) {
    assert(['task', ...childPhases, ...cleanupPhases].includes(event.phase) &&
      ['begin', 'end'].includes(event.boundary) && safe(event.task) &&
      safe(event.elapsedMicroseconds) && safe(event.observerMicroseconds),
    'InvalidNativePhysicalPhaseEvent');
    assert(event.elapsedMicroseconds >= previous, 'NativePhysicalPhaseClockRetreat');
    previous = event.elapsedMicroseconds;
    const environmentCleanup = ['environment-close', 'environment-release'].includes(event.phase);
    assert(environmentCleanup ? event.task === 0 : event.task > 0 &&
      choices.some(choice => choice.task === event.task), 'NativePhysicalPhaseWithoutTaskChoice');
    if (childPhases.includes(event.phase)) assert(
      choices.some(choice => choice.task === event.task && choice.resident),
    'NativePhysicalPhaseWithoutResidentChoice');
    assert(environmentCleanup ? safe(event.producer) : event.phase === 'import'
      ? safe(event.producer) && event.producer < event.task : event.producer === null,
    'InvalidNativePhysicalPhaseProducer');
    if (event.boundary === 'begin') {
      assert(event.success === null, 'InvalidNativePhysicalPhaseBegin');
      if (childPhases.includes(event.phase)) {
        assert(pending.length === 1 && pending[0].phase === 'task' &&
          pending[0].task === event.task, 'NativePhysicalChildOutsideTask');
      } else {
        assert(pending.length === 0, 'OverlappingNativePhysicalPhase');
        if (event.phase === 'task') assert(!cleanup, 'NativeTaskAfterCleanup');
        else {
          cleanup = true;
          const rank = cleanupPhases.indexOf(event.phase);
          assert(rank >= cleanupRank, 'NativeCleanupPhaseOrderMismatch');
          cleanupRank = rank;
        }
      }
      pending.push(event);
    } else {
      const begin = pending.pop();
      assert(begin && sameBoundary(begin, event), 'UnmatchedNativePhysicalPhaseEnd');
      assert.equal(event.success, true, 'FailedNativePhysicalPhase');
      const destination = event.phase === 'task' ? taskExecutionIntervals :
        event.phase === 'task-release' ? taskReleaseIntervals :
          environmentCleanup ? environmentCleanupIntervals : intervals;
      destination.push({phase: event.phase, task: event.task, producer: event.producer,
        elapsedMicroseconds: event.elapsedMicroseconds - begin.elapsedMicroseconds,
        clockObservationMicroseconds: begin.observerMicroseconds + event.observerMicroseconds});
    }
  }
  assert.equal(pending.length, 0, 'UnclosedNativePhysicalPhase');
  assert.deepEqual(taskExecutionIntervals.map(item => item.task), attempts.map(item => item.task),
    'NativeTaskExecutionPhaseCountMismatch');
  assert.deepEqual(taskReleaseIntervals.map(item => item.task).sort((a, b) => a - b),
    attempts.map(item => item.task).sort((a, b) => a - b), 'NativeTaskReleasePhaseCountMismatch');
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
    const outer = taskExecutionIntervals.find(item => item.task === attempt.task);
    assert(safe(span) && span <= outer.elapsedMicroseconds &&
      safe(durations.get(attempt.task)) && outer.elapsedMicroseconds <= durations.get(attempt.task),
    'NativePhysicalPhasesExceedTaskInterval');
  }
  const environments = attempts.reduce((sum, attempt) => sum + attempt.environments, 0);
  for (const phase of ['environment-close', 'environment-release']) assert.deepEqual(
    environmentCleanupIntervals.filter(item => item.phase === phase).map(item => item.producer),
    Array.from({length: environments}, (_, index) => index), 'NativeEnvironmentCleanupCountMismatch');
  const cleanupSpan = [...taskReleaseIntervals, ...environmentCleanupIntervals]
    .reduce((sum, item) => sum + item.elapsedMicroseconds, 0);
  assert(safe(cleanupMicroseconds) && safe(cleanupSpan) && cleanupSpan <= cleanupMicroseconds,
    'NativePhysicalPhasesExceedCleanupInterval');
  return Object.freeze({intervals, taskExecutionIntervals, taskReleaseIntervals, environmentCleanupIntervals,
    scope: 'selected physical task execution (nested preparation/import/Compute), task-owner release and resident environment close/release; excludes planner and common Run/acquisition cleanup',
    observerCostScope: 'clock observation only; buffering/callback overhead remains in process time and requires off/on measurement'});
}
