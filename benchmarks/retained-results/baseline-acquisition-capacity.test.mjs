import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {adaptBaselineAcquisitionCapacity, adaptBaselineAcquisitionLedger} from './baseline-acquisition-capacity.mjs';
import {retainedCase, workloads} from './fixtures.mjs';

const original = readFileSync(new URL('./baseline-host-limits.mbt.txt', import.meta.url), 'utf8');
const application = readFileSync(new URL('./baseline-application.mbt.txt', import.meta.url), 'utf8');
test('baseline ledger adaptation leaves native offers and execution logic unchanged', () => {
  const result = adaptBaselineAcquisitionLedger(application, 2560000);
  assert.equal(result.transferBytes, 2860000);
  assert.equal(result.source.replace(/\d+/g, '#'), application.replace(/\d+/g, '#'));
  const dispatch = value => value.slice(value.indexOf('pub fn application_dispatch('));
  assert.equal(dispatch(result.source), dispatch(application));
  assert(result.source.includes('retained_bytes: 1073741824L'));
  assert(result.source.includes('execution_bytes: 4294967296L'));
  assert.throws(() => adaptBaselineAcquisitionLedger(application + '// changed', 2560000), /UnrecognizedBaseline/);
  assert.throws(() => adaptBaselineAcquisitionLedger(application, NaN), /InvalidBaseline/);
  assert.throws(() => adaptBaselineAcquisitionLedger(application, 2147483648), /InvalidBaseline/);
});
test('baseline receiver adaptation preserves original dispatch and query logic', () => {
  for (const rows of [100, 1000, 10000, 100000, 1000000]) {
    const fixture = retainedCase(workloads[0], 'narrow', rows);
    const result = adaptBaselineAcquisitionCapacity(original, fixture);
    assert.equal(result.profile, fixture.id);
    assert.equal(result.source.slice(result.source.indexOf('fn dispatch_limits(')),
      original.slice(original.indexOf('fn dispatch_limits(')));
    const query = value => value.slice(value.indexOf('fn native_query_limits('), value.indexOf('fn transport('));
    assert.equal(query(result.source), query(original));
    const records = value => value.slice(value.indexOf('      records: {'), value.indexOf('    retention: {'));
    assert.equal(records(result.source), records(original));
    assert(result.changes.every(change => change.after > change.before));
    assert(result.changes.some(change => change.field === 'max_received_rows' && change.after === rows + 4));
    // The two helper copies prevent Acquisition bounds changing Compute.
    const normalized = result.source.slice(0, result.source.indexOf('fn acquisition_measurement(')) +
      result.source.slice(result.source.indexOf('fn acquisition_limits('));
    assert.equal(normalized.replaceAll('acquisition_measurement()', 'measurement()')
      .replaceAll('acquisition_transport()', 'transport()').replace(/\d+/g, '#'),
    original.replace(/\d+/g, '#'));
    assert(Object.isFrozen(result) && Object.isFrozen(result.changes));
  }
});
test('baseline adaptation rejects unknown source, unrelated profiles and overflow', () => {
  const fixture = retainedCase(workloads[0], 'narrow', 1000);
  assert.throws(() => adaptBaselineAcquisitionCapacity(original + '// changed', fixture), /UnrecognizedBaseline/);
  assert.throws(() => adaptBaselineAcquisitionCapacity(original,
    retainedCase(workloads[1], 'narrow', 1000)), /UnsupportedBaseline/);
  assert.throws(() => adaptBaselineAcquisitionCapacity(original,
    retainedCase(workloads[0], 'numeric-64', 1000)), /UnsupportedBaseline/);
  assert.throws(() => adaptBaselineAcquisitionCapacity(original,
    {...fixture, limits: {...fixture.limits, representationBytes: 2147483647}}), /InvalidBaseline/);
});
