// One Native product and independent execution of the same registered case.
// The Local evaluator and independent DuckDB assembly have different work
// meters. Their exact contents, bounded guards, physical custody and release
// are admitted here; physical traffic and implementation work stay separate.
import assert from 'node:assert/strict';
import {isDeepStrictEqual} from 'node:util';
import {workloads} from './fixtures.mjs';

const integer = (value, label) => {
  assert(Number.isSafeInteger(value) && value >= 0,
    `InvalidNativeEquivalentQuantity:${label}`);
  return value;
};

const released = (ledger, label) => {
  assert(ledger, `MissingNativeEquivalentLedger:${label}`);
  for (const field of ['uncertain_transfer_bytes', 'reserved_transfer_bytes',
    'held_bytes', 'reserved_retention_bytes', 'reserved_execution_bytes']) {
    assert.equal(BigInt(ledger[field]), 0n,
      `UnreleasedNativeEquivalentCapacity:${label}.${field}`);
  }
};

export function admitNativeEquivalentPair({fixture, native, equivalent,
  selectionProfile}) {
  assert(fixture && native && equivalent && selectionProfile?.admitted === true,
    'IncompleteNativeEquivalentPair');
  assert([100, 1000].includes(fixture.rows), 'NativeEquivalentOutsideSmallProfile');
  assert.equal(selectionProfile.targetCaseId, fixture.id);
  assert.equal(equivalent.status, 'diagnostic-completed');
  assert.equal(equivalent.comparator, 'independent-obligation-assembly');
  assert.equal(equivalent.caseId, fixture.id);
  assert.deepEqual(equivalent.missing,
    ['matched process/cold timing boundaries']);
  assert.equal(equivalent.validationRows, fixture.cardinalities.source);
  assert.equal(equivalent.capacity?.conformance, 'registered-fixture-bounded');
  assert(equivalent.capacity.execution.admittedBytes <=
    equivalent.capacity.execution.limitBytes);
  assert(equivalent.capacity.independentRetention.fileReservedBytes <=
    equivalent.capacity.independentRetention.limitBytes);
  const rows = fixture.workload === workloads[1]
    ? [fixture.cardinalities.a, fixture.cardinalities.b,
        fixture.cardinalities.join, fixture.cardinalities.count]
    : [fixture.cardinalities.a, fixture.cardinalities.b,
        fixture.cardinalities.c];
  const stages = equivalent.stages.slice(1);
  assert.equal(equivalent.stages.length, rows.length + 1);
  assert.equal(equivalent.holding.holdings, rows.length + 1);
  assert.deepEqual(stages.map(stage => stage.rows), rows);
  assert.deepEqual(native.taskHoldings.map(holding => holding.rows), rows);
  assert.deepEqual(native.taskHoldings.map(holding =>
    [holding.rowsCid, holding.bytes]),
  stages.map(stage => [stage.cid, stage.bytes]));
  assert.equal(native.record.rows_cid, fixture.identity().rowsCid);
  assert.equal(stages.at(-1).cid, native.record.rows_cid);
  assert(isDeepStrictEqual(native.acquisitionEvidenceMetadata,
    equivalent.acquisitionEvidenceMetadata),
  'NativeEquivalentAcquisitionEvidenceMismatch');
  assert.equal(native.acquisitionEvidenceMetadata.validationScan.receivedRows,
    fixture.cardinalities.source);
  assert.equal(native.acquisitionEvidenceMetadata.validationScan.receivedRowsCid,
    equivalent.validationCid);
  assert.equal(native.acquisitionEvidenceMetadata.nativeResult.receivedRowsCid,
    equivalent.stages[0].cid);
  const acquisition = native.record.acquisition;
  assert.equal(acquisition.comparison_rows, fixture.cardinalities.source);
  for (const field of ['guard_work', 'guard_bytes', 'guard_nodes',
    'comparison_work', 'comparison_bytes', 'comparison_nodes']) {
    integer(acquisition[field], `acquisition.${field}`);
  }
  assert(acquisition.guard_work > 0 && acquisition.comparison_work > 0);
  assert.deepEqual(native.taskUsages.map(usage => usage.task),
    rows.map((_, index) => index + 1));
  for (const usage of native.taskUsages) {
    for (const field of ['measurementWork', 'measurementBytes',
      'measurementNodes', 'comparisonWork', 'comparisonBytes',
      'comparisonNodes']) integer(usage[field], `task.${field}`);
    assert(usage.measurementWork + usage.comparisonWork > 0,
      'NativeEquivalentTaskWithoutLogicalCharge');
  }
  assert.equal(native.record.usage.attempts, rows.length);
  assert.equal(native.record.usage.holdings, rows.length);
  released(native.record.usage, 'native');
  released(equivalent.releasedRetentionLedger, 'independent-retention');
  released(equivalent.releasedExecutionLedger, 'independent-execution');
  assert.equal(equivalent.holding.cleanupPending, false);
  assert.equal(equivalent.holding.activeReaders, 0);
  return Object.freeze({
    version: 'actql-native-retained-equivalent-admission/0.1',
    accepted: true,
    scope: 'one calibrated Native small case and independent execution',
    chargeBasis: 'profile-specific operation meters under registered bounds',
  });
}
