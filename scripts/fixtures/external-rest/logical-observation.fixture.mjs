// Ordinary caller DATA only. This fixture never issues a logical key, grant,
// Core handle or cleanup acknowledgment. Product imports stay installed-only.
import assert from 'node:assert/strict';

export function createTimedLogicalObservation(createConnection) {
  const records = [];
  let failure;
  const connection = createConnection({include: ['compute'],
    correlation: {include: ['run', 'task']}, measurements: {include: []},
    deliver(record) {
      // Application-owned copies do not retain the original delivery object.
      // Bound this functional fixture independently of the product queue.
      try {
        assert(records.length < 256, 'LogicalObservationFixtureRecordLimit');
        const wire = JSON.stringify(record);
        assert(Buffer.byteLength(wire) <= 4096, 'LogicalObservationFixtureByteLimit');
        records.push(JSON.parse(wire));
      } catch (cause) {failure ??= cause;}
    }});
  return Object.freeze({connection, snapshot() {
    return {records, status: connection.status(),
      ...(failure === undefined ? {} : {failure: {name: failure.name, message: failure.message}})};
  }});
}

export function assertTimedLogicalObservation(snapshot, explanation, ref, runId, phase) {
  assert(['read', 'saved'].includes(phase));
  assert.equal(snapshot.failure, undefined, 'LogicalObservationFixtureCaptureFailed');
  assert.equal(snapshot.status?.closed, true, 'ActualObservationCloseNotObserved');
  assert.equal(snapshot.status.cleanupPending, false, 'OriginalObservationReturnStillPending');
  assert.deepEqual(explanation.run_ref, ref);
  assert.equal(explanation.explanation.state, 'projected');
  const steps = explanation.explanation.facts.steps;
  const boundaries = snapshot.records.filter(record =>
    ['logical_boundary_observed', 'logical_boundary_unavailable'].includes(record.event));
  if (phase === 'saved') {
    assert.equal(snapshot.records.length, 0, 'SavedMustNotExecuteAnotherComputeBoundary');
  } else {
    assert(boundaries.length > 0, 'NoActualLogicalBoundaryDelivered');
    assert(snapshot.records.some(record => record.event === 'task_completed'),
      'OriginalPhysicalTaskCompletionNotObserved');
  }
  let projected = 0, notProjected = 0;
  for (const record of boundaries) {
    assert.equal(record.operation, 'compute');
    const attributes = record.attributes;
    assert.equal(attributes['actql.operation'], 'compute');
    assert.equal(attributes['actql.event'], record.event);
    assert.equal(attributes['actql.observation.version'], 'actql-observation/0.1');
    assert.equal(attributes['actql.run.definition_cid'], ref.runDefinitionCid);
    assert.equal(attributes['actql.run.id'], runId);
    assert(Number.isSafeInteger(attributes['actql.task.ordinal']) && attributes['actql.task.ordinal'] >= 0);
    assert(Object.keys(attributes).every(name => [
      'actql.operation', 'actql.event', 'actql.observation.version',
      'actql.run.definition_cid', 'actql.run.id', 'actql.task.ordinal',
      'actql.logical_step.key', 'actql.logical_boundary.phase',
      'actql.logical_boundary.reason'].includes(name)), 'UnexpectedLogicalMetadataDisclosure');
    if (record.event === 'logical_boundary_observed') {
      const key = JSON.parse(attributes['actql.logical_step.key']);
      // Compare complete compiler originals; never infer a key from a task
      // ordinal, a matching CID alone, or the fixture's authored SQL/rows.
      assert(steps.some(step => {try {assert.deepEqual(key, step.key); return true;} catch {return false;}}),
        'LogicalBoundaryDoesNotMatchOriginalFacts');
      assert(['before', 'settled', 'output_emitted'].includes(attributes['actql.logical_boundary.phase']));
      assert.equal(attributes['actql.logical_boundary.reason'], undefined);
      projected++;
    } else {
      assert.equal(attributes['actql.logical_boundary.reason'], 'not_projected');
      assert.equal(attributes['actql.logical_step.key'], undefined);
      assert.equal(attributes['actql.logical_boundary.phase'], undefined);
      notProjected++;
    }
  }
  return {phase, deliveredBoundaries: boundaries.length, projected, notProjected,
    logicalCompletionClaimed: false, internalRequestIdentityObserved: false,
    newSampleOrControl: false};
}
