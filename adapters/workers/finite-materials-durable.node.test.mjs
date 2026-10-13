import assert from 'node:assert/strict';
import test from 'node:test';
import {runFiniteCase} from './finite-runtime-fixture.mjs';

// Real Common owners in one matching compiled fixture link unit. The durable
// booleans below are observations supplied by this fixture, not physical CAS ACKs.
test('original finite materials retain their Run and canonical export owners on Node', async () => {
  const rows = [{id: 7}, {id: null}, {id: 7}];
  const value = await runFiniteCase({rows, nullable: true,
    restoreMaterials: true, exportMeasurement: true});
  assert.equal(value.status, 'completed');
  assert.deepEqual(value.rows, rows);
  assert.deepEqual(value.exportRows, rows);
  assert.deepEqual(value.schema, {id: {type: 'number', nullable: true}});
  assert.equal(value.materialsChecks.originalIdentity, value.materialsChecks.restoredIdentity);
  assert.equal(value.materialsChecks.foreignPreparation, 'InvalidWorkersFiniteInstallation');
  assert.equal(value.materialsChecks.duplicateAdmission, 'WorkersFiniteRunAlreadyOpened');
  for (const key of ['malformed', 'wrongIdentity']) assert.equal(value.materialsChecks[key], 'MoonBitHostFailure');
  assert.equal(value.measurement.rowCount, 3);
  assert.deepEqual(value.measurement.columnRows, [3]);
  assert.deepEqual(value.measurement.columnNullRows, [1]);
  assert.equal(value.released, true);
  assert.equal(value.cleanupPending, false);
});

test('Common durable observations refuse false, stale and consumed commits without changing the original record', async () => {
  const value = await runFiniteCase({durableRecords: true});
  for (const key of ['initialMatch', 'plannedMatch', 'unchangedAfterRefusal',
    'unchangedAfterStaleCommit', 'initialIdentityMatches', 'originalWireMatches', 'restoredWireMatches']) {
    assert.equal(value[key], true, key);
  }
  for (const key of ['refusedAdmission', 'refusedCommit', 'refusedStaleCommit',
    'refusedConsumedCommit', 'collision', 'releasedCustody', 'malformed', 'unknownField']) {
    assert.equal(value[key], 'MoonBitHostFailure', key);
  }
  assert.equal(value.expectedRevision, 0);
  assert.equal(value.initialRevision, 0);
  assert.equal(value.restoredRevision, 5);
  assert.deepEqual(value.actions, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  assert.equal(value.outputRequestMatches, true);
  assert.deepEqual(value.outputProjection, value.outputIntentInput);
});
