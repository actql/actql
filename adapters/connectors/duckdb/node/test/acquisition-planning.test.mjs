import assert from 'node:assert/strict';
import test from 'node:test';
import {checkDuckDBAcquisitionPlanning} from '../acquisition-planning.mjs';

const evidence = () => ({inputConditions: {requirementCid: 'sha256:' + 'a'.repeat(64),
  source: {database: '/fixture/source.duckdb', schema: 'main', table: 'records',
    sourceRef: 'connector://fixture/records#v'}},
unit: 'milliseconds', basis: 'Independently supplied finite test estimate; not a measurement',
estimates: [{workSlots: Array.from({length: 11}, (_, index) => index), milliseconds: 10}],
quantities: {transferBytes: 137, retainedBytes: 103, moneyUnits: null}});

test('Host selection policy is explicit and never inherits a compatibility estimate', () => {
  for (const value of [undefined, null, {}, {policy: 'native'},
    {policy: 'priority', priority: ['nativeQuery']},
    {policy: 'priority', priority: ['nativeQuery', 'nativeQuery']},
    {policy: 'priority', priority: ['nativeQuery', 'broadQuery'], candidates: {}}]) {
    assert.throws(() => checkDuckDBAcquisitionPlanning(value),
      {message: 'InvalidInstalledAcquisitionPlanning'});
  }
  assert.deepEqual(checkDuckDBAcquisitionPlanning({policy: 'estimatedLatency', candidates: {}}),
    {policy: 'estimatedLatency', candidates: {}});
  assert.deepEqual(checkDuckDBAcquisitionPlanning({policy: 'priority', priority: ['broadQuery', 'nativeQuery']}),
    {policy: 'priority', priority: ['broadQuery', 'nativeQuery']});
});

test('estimate scope, unit, provenance and quantities are admitted together', () => {
  const input = {policy: 'estimatedLatency', candidates: {nativeQuery: evidence()}};
  const installed = checkDuckDBAcquisitionPlanning(input);
  input.candidates.nativeQuery.inputConditions.source.table = 'replacement';
  input.candidates.nativeQuery.estimates[0].workSlots[0] = 99;
  input.candidates.nativeQuery.estimates[0].milliseconds = 0;
  assert.equal(installed.candidates.nativeQuery.inputConditions.source.table, 'records');
  assert.equal(installed.candidates.nativeQuery.estimates[0].workSlots[0], 0);
  assert.equal(installed.candidates.nativeQuery.estimates[0].milliseconds, 10);
  assert.ok(Object.isFrozen(installed.candidates.nativeQuery.estimates[0].workSlots));
  for (const change of [value => { value.unit = 'seconds'; },
    value => { value.basis = ''; },
    value => { value.inputConditions.requirementCid = 'unbound'; },
    value => { delete value.inputConditions.source; },
    value => { value.estimates[0].milliseconds = -1; },
    value => { value.estimates[0].milliseconds = Number.MAX_SAFE_INTEGER + 1; },
    value => { value.quantities.retainedBytes = -1; }]) {
    const value = evidence(); change(value);
    assert.throws(() => checkDuckDBAcquisitionPlanning({policy: 'estimatedLatency',
      candidates: {nativeQuery: value}}), {message: 'InvalidInstalledAcquisitionPlanning'});
  }
  const unknown = evidence(); unknown.estimates[0].milliseconds = null;
  unknown.quantities.transferBytes = null;
  assert.equal(checkDuckDBAcquisitionPlanning({policy: 'estimatedLatency',
    candidates: {nativeQuery: unknown}}).candidates.nativeQuery.estimates[0].milliseconds, null);
});
