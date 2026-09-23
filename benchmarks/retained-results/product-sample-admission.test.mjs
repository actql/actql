import test from 'node:test';
import assert from 'node:assert/strict';
import {retainedCase, workloads} from './fixtures.mjs';
import {admitRetainedProductSample} from './product-sample-admission.mjs';

const fixture = retainedCase(workloads[0], 'narrow', 1000);
const estimates = Object.freeze({trainingCaseId: retainedCase(workloads[0],
  'narrow', 100).id, targetCaseId: fixture.id,
estimateSource: `sha256:${'a'.repeat(64)}`,
localTaskMilliseconds: ['12', '3', '4'],
nativeTaskMilliseconds: ['18', '9', '8']});
const calibration = Object.freeze({verified: true,
  trainingCaseId: estimates.trainingCaseId, targetCaseId: fixture.id,
  estimateSource: estimates.estimateSource,
  targetSourceSha256: 'b'.repeat(64)});

function sample() {
  return {fixture, estimates, calibration, report: {
    status: 'completed', comparator: 'retained-actql', caseId: fixture.id,
    expectedRowsCid: fixture.identity().rowsCid,
    rows: fixture.identity().rows,
    selection: {resident: true, nativeMilliseconds: '18',
      estimateSource: estimates.estimateSource,
      localTaskMilliseconds: [...estimates.localTaskMilliseconds],
      nativeTaskMilliseconds: [...estimates.nativeTaskMilliseconds]},
    tasks: [1, 2, 3].map(task => ({task, realization: 'duckdb-resident'})),
    completionDescriptors: [1, 2, 3].map(() => ({
      rows_cid: fixture.identity().rowsCid})),
    storage: {cleanupPending: false}, cleanupMs: 1,
  }};
}

test('only a released held-out normal selection qualifies for timing', () => {
  assert.equal(admitRetainedProductSample(sample()).accepted, true);
  for (const change of [
    input => { input.estimates = undefined; },
    input => { input.calibration.verified = false; },
    input => { input.calibration.targetSourceSha256 = 'invalid'; },
    input => { input.report.caseId = estimates.trainingCaseId; },
    input => { input.report.selection.nativeMilliseconds = '1'; },
    input => { input.report.selection.nativeTaskMilliseconds[1] = '1'; },
    input => { input.report.selection.estimateSource = `sha256:${'c'.repeat(64)}`; },
    input => { input.report.tasks[1].task = 1; },
    input => { input.report.tasks[1].realization = 'forced'; },
    input => { input.report.completionDescriptors[2].rows_cid = 'foreign'; },
    input => { input.report.storage.cleanupPending = true; },
    input => { input.report.cleanupMs = undefined; },
  ]) {
    const input = sample();
    input.calibration = {...input.calibration};
    change(input);
    assert.throws(() => admitRetainedProductSample(input));
  }
});
