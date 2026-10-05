// Finite correspondence for the installed numeric/NULL serial benchmark.
// Actual child ledger quantities and connector preparation observations are
// distinct from parent process admission and independently owned file custody.
import assert from 'node:assert/strict';

const driverKeys = {planningWork: 'planning_work', attempts: 'attempts',
  holdings: 'holdings', transferredBytes: 'transferred_bytes',
  reservedTransferBytes: 'reserved_transfer_bytes', heldBytes: 'held_bytes',
  reservedRetentionBytes: 'reserved_retention_bytes', reservedExecutionBytes: 'reserved_execution_bytes'};
const quantity = value => {
  assert(typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ||
    typeof value === 'string' && /^(0|[1-9][0-9]*)$/.test(value),
  'InvalidNodeOwnerQuantity');
  return BigInt(value);
};

export function admitNodePlannerOwnerObservations(report, limits) {
  const observations = report.plannerObservations;
  const ids = report.tasks.map(task => task.task);
  assert.deepEqual(observations?.map(value => [value.boundary, value.task]),
    ids.flatMap(task => [['before-task', task], ['after-task', task]]),
  'MissingNodePlannerOwnerBoundary');
  const attempts = ids.map((task, index) => {
    const before = observations[index * 2], after = observations[index * 2 + 1];
    const actual = report.tasks[index];
    assert.equal(before.managed, false, 'NodeOwnerObservationOutsideSerialScope');
    const selected = before.explanation.selection;
    assert(before.explanation.kind === 'host-private-strategy-explanation/0.1' &&
      before.explanation.selection_state === 'selected' && selected?.dispatch_authorized &&
      selected.revision === before.explanation.assessment_revision,
    'NodePlannerSelectionMismatch');
    const offer = selected.tasks.find(value => value.task === task);
    assert(offer && offer.completed === false &&
      offer.capability === before.registrationKey &&
      offer.capability === actual.realization.replace(/-resident$/, ''),
    'NodePlannerTaskMismatch');
    assert.equal(offer.resident_profile !== null,
      actual.realization === 'duckdb-resident', 'NodePlannerResidentMismatch');
    for (const [driver, owner] of Object.entries(driverKeys)) {
      assert.equal(quantity(before.driverUsage[driver]), quantity(before.usage[owner]),
        'NodeDriverOwnerLedgerMismatch');
      assert.equal(quantity(before.explanation.ledger[owner]), quantity(before.usage[owner]),
        'NodeExplanationOwnerLedgerMismatch');
    }
    const preparation = actual.preparation;
    const environments = preparation?.environmentCreated ? 1 : 0;
    const imports = preparation?.imports?.length ?? 0;
    assert.equal(quantity(after.usage.attempts) - quantity(before.usage.attempts),
      BigInt(1 + environments + imports), 'UnattributedNodePhysicalAttempt');
    assert.equal(quantity(after.usage.holdings) - quantity(before.usage.holdings),
      1n, 'NodeTaskHoldingCorrespondence');
    const charged = quantity(after.usage.held_bytes) - quantity(before.usage.held_bytes);
    assert(charged >= BigInt(report.completionDescriptors[index].bytes) &&
      charged <= quantity(offer.capacity.retained_bytes), 'NodeHoldingOutsideSelectedBound');
    if (index > 0) assert.equal(quantity(before.usage.attempts),
      quantity(observations[index * 2 - 1].usage.attempts),
    'UnattributedNodeBetweenTaskAttempt');
    for (const observation of [before, after]) {
      assert(quantity(observation.usage.attempts) <= BigInt(limits.attempts) &&
        quantity(observation.usage.reserved_execution_bytes) <= limits.execution_bytes &&
        quantity(observation.usage.held_bytes) +
          quantity(observation.usage.reserved_retention_bytes) <= limits.retained_bytes,
      'NodeOwnerExceedsRegisteredLimit');
    }
    if (offer.resident_profile !== null) assert(
      quantity(after.usage.reserved_execution_bytes) > 0n,
      'NodeResidentReservationReleasedEarly');
    assert(Number.isFinite(actual.plannerObserverMilliseconds) &&
      actual.plannerObserverMilliseconds >= 0, 'MissingNodePlannerObserverInterval');
    return {task, compute: 1, environments, imports,
      physicalAttempts: 1 + environments + imports};
  });
  for (let index = 0; index < observations.length; index++) {
    assert(Number.isFinite(observations[index].elapsedMilliseconds) &&
      observations[index].elapsedMilliseconds >= 0 &&
      (index === 0 || observations[index].elapsedMilliseconds >=
        observations[index - 1].elapsedMilliseconds), 'NodeOwnerClockRetreat');
  }
  // The acquisition was already admitted before these snapshots. The parent
  // starts exactly one actual execution process and merges its consumed usage.
  assert.equal(quantity(report.usage.attempts),
    quantity(observations.at(-1).usage.attempts) + 1n,
  'NodeProcessAttemptCorrespondence');
  for (const field of ['held_bytes', 'reserved_retention_bytes',
    'reserved_execution_bytes', 'reserved_transfer_bytes', 'uncertain_transfer_bytes']) {
    assert.equal(quantity(report.usage[field]), 0n, 'NodeProcessReservationPending');
  }
  return Object.freeze({scope: 'successful numeric/NULL serial Node experiment',
    attempts, acquisitionAttempts: Number(quantity(observations[0].usage.attempts)),
    executionProcessAttempts: 1,
    plannerObserverMilliseconds: report.tasks.reduce((sum, task) =>
      sum + task.plannerObserverMilliseconds, 0),
    custody: 'existing comparator independently admits retained descriptors and close',
    limitation: 'finite counters/preparation correspondence; no opaque attempt identity or heap bound'});
}
