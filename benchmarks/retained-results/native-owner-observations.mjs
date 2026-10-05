// Finite correspondence with the real Native Run owner and ledger. These
// counters are not opaque attempt handles or proof of allocator/GC lifetimes.
import assert from 'node:assert/strict';

const liveCapacity = ['heldBytes', 'reservedExecutionBytes',
  'reservedRetentionBytes', 'reservedTransferBytes', 'uncertainTransferBytes'];
const counters = ['task', 'planningWork', 'attempts', 'holdings', ...liveCapacity,
  'environments', 'imports', 'borrowedInputs', 'importedRows',
  'unconfirmedEnvironments', 'importScratchBytes', 'taskDemandBytes'];
const parsed = (lines, prefix) => lines.filter(line => line.startsWith(prefix))
  .map(line => JSON.parse(line.slice(prefix.length)));
const safe = (value, label) => assert(Number.isSafeInteger(value) && value >= 0,
  `InvalidNativeOwnerQuantity:${label}`);

export function nativeOwnerObservations(stdout) {
  const lines = stdout.split('\n');
  const owners = parsed(lines, 'owner-observation:');
  for (const owner of owners) {
    for (const key of counters) safe(owner[key], key);
    for (const key of ['temporaryViews', 'tables']) {
      assert(Number.isSafeInteger(owner[key]) && owner[key] >= -1,
        `InvalidNativeOwnerQuantity:${key}`);
    }
  }
  const candidates = lines.filter(line => line.startsWith('compute-candidates:'))
    .map(line => {
      const match = /^compute-candidates:([1-9][0-9]*):(.*)$/.exec(line);
      assert(match, 'InvalidNativeCandidateObservation');
      return {task: Number(match[1]), body: JSON.parse(match[2])};
    });
  const choices = parsed(lines, 'compute-choice:');
  const acquisitionChoices = parsed(lines, 'acquisition-choice:');
  const plannerObserver = prefix => lines.filter(line => line.startsWith(prefix))
    .map(line => {
      const match = new RegExp('^' + prefix + '([1-9][0-9]*):(0|[1-9][0-9]*)$').exec(line);
      assert(match, 'InvalidNativePlannerObserver');
      const task = Number(match[1]), value = Number(match[2]);
      safe(task, 'planner-task'); safe(value, 'planner-observer');
      return {task, value};
    });
  const plannerObserverTime = plannerObserver('planner-observer-us:');
  const plannerObserverWork = plannerObserver('planner-observer-work:');
  for (const choice of choices) {
    const before = lines.findIndex(line => line.startsWith('compute-candidates:' + choice.task + ':'));
    const chosen = lines.findIndex(line => line.startsWith('compute-choice:') &&
      JSON.parse(line.slice('compute-choice:'.length)).task === choice.task);
    const after = lines.findIndex(line => line.startsWith('task-elapsed-us:' + choice.task + ':'));
    assert(before >= 0 && chosen > before && after > chosen,
      'NativeChoiceNotObservedBeforeCompletion');
  }
  const phases = lines.filter(line => line.startsWith('phase-time-us:'))
    .map(line => {
      const match = /^phase-time-us:([a-z-]+):(0|[1-9][0-9]*)$/.exec(line);
      assert(match, 'InvalidNativePhaseObservation');
      const elapsedMicroseconds = Number(match[2]);
      safe(elapsedMicroseconds, 'phase');
      return {boundary: match[1], elapsedMicroseconds};
    });
  const observerMicroseconds = lines.filter(line =>
    line.startsWith('observer-elapsed-us:')).map(line => {
    const value = Number(line.slice('observer-elapsed-us:'.length));
    safe(value, 'observer');
    return value;
  });
  assert.equal(observerMicroseconds.length, owners.length,
    'MissingNativeObserverInterval');
  return {owners, candidates, choices, phases, observerMicroseconds,
    acquisitionChoices, plannerObserverTime, plannerObserverWork};
}

export function admitNativeOwnerObservations(observations, taskHoldings, selected,
  finalUsage) {
  const {owners, candidates, choices, phases, observerMicroseconds} = observations;
  const ids = taskHoldings.map(holding => holding.task);
  for (const key of ['plannerObserverTime', 'plannerObserverWork']) {
    assert.deepEqual(observations[key]?.map(item => item.task), ids,
      'MissingNativePlannerObserver');
  }
  assert.deepEqual(candidates.map(item => item.task), ids,
    'MissingNativePlannerCandidates');
  assert.deepEqual(choices.map(item => item.task), ids,
    'MissingNativePlannerChoice');
  assert.deepEqual(owners.map(item => [item.boundary, item.task]),
    [...ids.flatMap(task => [['before-task', task], ['after-task', task]]),
      ...['before-close', 'after-close', 'duplicate-close'].map(boundary =>
        [boundary, ids.at(-1)])], 'MissingNativeOwnerBoundary');
  assert.equal(owners[0].attempts, 0, 'UnattributedNativeInitialAttempt');
  assert.equal(owners[0].holdings, 0, 'UnattributedNativeInitialHolding');
  const attempts = ids.map((task, index) => {
    const before = owners[index * 2], after = owners[index * 2 + 1];
    if (index > 0) assert.deepEqual(before, {...owners[index * 2 - 1],
      boundary: 'before-task', task}, 'NativeOwnerChangedBetweenTasks');
    const environments = after.environments - before.environments;
    const imports = after.imports - before.imports;
    assert(environments >= 0 && imports >= 0, 'NativeOwnerCounterRetreat');
    assert.equal(after.attempts - before.attempts, 1 + environments + imports,
      'UnattributedNativePhysicalAttempt');
    assert.equal(after.holdings - before.holdings, 1,
      'NativeTaskHoldingCorrespondence');
    const retainedChargeBytes = after.heldBytes - before.heldBytes;
    assert(retainedChargeBytes >= taskHoldings[index].bytes,
      'NativeSealedHoldingUndercharged');
    assert(after.reservedExecutionBytes >= 0);
    assert.equal(after.unconfirmedEnvironments, 0,
      'NativeResidentTransactionUnconfirmed');
    const body = candidates[index].body;
    assert(Array.isArray(body) && body[0] === 'actql-policy-candidates/0.2' &&
      Array.isArray(body[5]), 'InvalidNativePlannerProjection');
    const choice = choices[index];
    assert.equal(choice.name, selected[index], 'NativeExecutionSelectionChanged');
    const assignment = body[5].find(candidate => candidate[0] === choice.position);
    assert(assignment, 'NativeChoiceOutsideCandidateSet');
    const offer = assignment[5].find(offer => offer?.[0] === task);
    assert(offer && offer[1] === choice.registration,
      'NativeChoiceRegistrationMismatch');
    assert(BigInt(retainedChargeBytes) <= BigInt(offer[5]),
      'NativeHoldingExceedsSelectedBound');
    assert.equal(offer[9] !== null, choice.resident,
      'NativeChoiceResidentMismatch');
    if (choice.resident) {
      assert(after.environments > 0 && after.reservedExecutionBytes > 0,
        'NativeResidentReservationReleasedEarly');
    } else {
      assert.equal(environments + imports, 0,
        'NativeNonresidentTaskCreatedResidentAttempt');
    }
    return {task, compute: 1, environments, imports,
      canonicalRowsBytes: taskHoldings[index].bytes, retainedChargeBytes,
      selectedRetentionBoundBytes: offer[5],
      physicalAttempts: after.attempts - before.attempts};
  });
  const beforeClose = owners.at(-3), afterClose = owners.at(-2);
  assert.deepEqual(beforeClose, {...owners.at(-4), boundary: 'before-close'},
    'NativeHoldingLostBeforeClose');
  assert.equal(afterClose.attempts, beforeClose.attempts);
  assert.equal(afterClose.holdings, beforeClose.holdings);
  for (const field of liveCapacity) assert.equal(afterClose[field], 0,
    `NativeOwnerClosePending:${field}`);
  assert.deepEqual(owners.at(-1), {...afterClose, boundary: 'duplicate-close'},
    'NativeDuplicateCloseChangedOwner');
  assert.equal(finalUsage.attempts, afterClose.attempts);
  assert.equal(finalUsage.holdings, afterClose.holdings);
  assert(phases.length > 1 && new Set(phases.map(item => item.boundary)).size ===
    phases.length, 'MissingNativePhaseBoundaries');
  for (let index = 1; index < phases.length; index++) assert(
    phases[index].elapsedMicroseconds >= phases[index - 1].elapsedMicroseconds,
    'NativePhaseClockRetreat');
  const phaseIntervals = phases.map((phase, index) => ({...phase,
    precedingIntervalMicroseconds: phase.elapsedMicroseconds -
      (phases[index - 1]?.elapsedMicroseconds ?? 0)}));
  return Object.freeze({scope: 'successful tasks and explicit Run close',
    attempts, observations, phaseIntervals,
    observerMicroseconds: observerMicroseconds.reduce((sum, value) => sum + value, 0),
    plannerObserverMicroseconds: observations.plannerObserverTime.reduce((sum, item) => sum + item.value, 0),
    plannerObserverWork: observations.plannerObserverWork.reduce((sum, item) => sum + item.value, 0),
    accounting: 'cumulative owner counters, sealed holding bytes, live reservations',
    timing: 'enclosing elapsed boundaries; nested task/observer intervals are not additive'});
}
