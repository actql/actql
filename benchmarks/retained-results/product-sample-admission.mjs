// Qualify one normal product leg for paired timing. This does not assess speed
// or make the independent comparator or the complete matrix admissible.
import assert from 'node:assert/strict';
import {workloads} from './fixtures.mjs';

export function admitRetainedProductSample({fixture, estimates, calibration,
  report}) {
  assert(fixture && estimates && calibration && report,
    'IncompleteProductSampleAdmission');
  const taskCount = fixture.workload === workloads[1] ? 4 : 3;
  assert.equal(calibration.verified, true, 'UnverifiedCalibration');
  assert.equal(calibration.trainingCaseId, estimates.trainingCaseId);
  assert.equal(calibration.targetCaseId, fixture.id);
  assert.equal(estimates.targetCaseId, fixture.id);
  assert.equal(calibration.estimateSource, estimates.estimateSource);
  assert.match(calibration.targetSourceSha256, /^[0-9a-f]{64}$/);
  assert.equal(report.status, 'completed');
  assert.equal(report.comparator, 'retained-actql');
  assert.equal(report.caseId, fixture.id);
  assert.equal(report.expectedRowsCid, fixture.identity().rowsCid);
  assert.equal(report.rows, fixture.identity().rows);
  assert.equal(report.selection?.resident, true);
  assert.equal(report.selection.estimateSource, estimates.estimateSource);
  assert.deepEqual(report.selection.localTaskMilliseconds,
    estimates.localTaskMilliseconds);
  assert.deepEqual(report.selection.nativeTaskMilliseconds,
    estimates.nativeTaskMilliseconds);
  assert.equal(report.selection.nativeMilliseconds,
    estimates.nativeTaskMilliseconds[0]);
  assert.equal(report.tasks?.length, taskCount);
  assert.deepEqual(report.tasks.map(task => task.task),
    Array.from({length: taskCount}, (_, index) => index + 1));
  assert(report.tasks.every(task =>
    ['local', 'duckdb', 'duckdb-resident'].includes(task.realization)),
  'InvalidSelectedRealization');
  assert.equal(report.completionDescriptors?.length, taskCount);
  assert.equal(report.completionDescriptors.at(-1).rows_cid,
    fixture.identity().rowsCid);
  assert(Number.isFinite(report.cleanupMs) && report.cleanupMs >= 0,
    'UnconfirmedProductRelease');
  assert.equal(report.storage?.cleanupPending, false,
    'PendingProductStorageCleanup');
  return Object.freeze({accepted: true,
    scope: 'one held-out, cost-grounded normal product selection',
    estimateSource: estimates.estimateSource,
    trainingCaseId: estimates.trainingCaseId,
    targetCaseId: fixture.id});
}
