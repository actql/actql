import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {groupComparisonProgram, groupComparisonSuccesses as cases,
  groupComparisonRefusals as refusals} from './fixtures/group-comparison-source-input.mjs';
import {groupOrdinalSuccesses, groupOrdinalRefusals}
  from './fixtures/group-ordinal-source-input.mjs';

test('comparison group control keeps nullable Boolean keys and duplicate counts', () => {
  assert.deepEqual(JSON.parse(cases[0].text), groupComparisonProgram);
  assert.deepEqual(groupComparisonProgram.stages[1].steps[0],
    {from: 'records', derive: {key: {neq: [{field: 'amount'}, {literal: 10}]}}});
  assert.deepEqual(cases[0].expected,
    [{flag: false, n: 1}, {flag: true, n: 2}, {flag: null, n: 1}]);
  assert.deepEqual(cases[0].columns,
    [{name: 'flag', contract: {type: 'boolean', nullable: true}},
      {name: 'n', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(cases[5].expected, [{flag: false, n: 1}, {flag: null, n: 1}]);
  assert.deepEqual(cases[7].expected, []);
  assert.deepEqual(cases[7].columns, cases[0].columns);
});

test('normal public corpus and focused consumer retain operator identity cases', () => {
  assert.equal(cases.length, 8);
  assert.equal(refusals.length, 3);
  assert.ok(cases.every(value => groupOrdinalSuccesses.includes(value)));
  assert.ok(refusals.every(value => groupOrdinalRefusals.includes(value)));
  assert.ok(cases.every(value => value.sourceReadSessionCount === 1));
  assert.ok(refusals.every(value => value.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(readFileSync('scripts/test-packed-public-query.mjs', 'utf8')
    .includes("['scripts/fixtures/group-comparison-source-input.mjs', 'group-comparison-source-input.mjs']"));
  const consumer = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  assert.ok(consumer.includes('...groupStarSuccesses, ...groupOrdinalSuccesses]'));
  assert.ok(consumer.includes('...groupStarRefusals, ...groupOrdinalRefusals]'));
});
