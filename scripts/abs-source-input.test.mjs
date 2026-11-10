import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {absSuccesses, absRefusals, absExecutionFailures} from './fixtures/abs-source-input.mjs';

const cases = new Map(absSuccesses.map(item => [item.name, item]));
test('absolute-value expected magnitudes are independent finite binary64 values', () => {
  assert.deepEqual(cases.get('abs-finite-values').expected,
    [{zero: 0, fractional: 0.25, exact: 2.25, negative_zero: 0}]);
  assert.deepEqual(cases.get('abs-finite-extremes').expected,
    [{tiny: 5e-324, large: 1.7976931348623157e308}]);
  assert.deepEqual(cases.get('abs-safe-integer-boundary').expected, [{value: 9007199254740991}]);
  assert.deepEqual(JSON.parse(cases.get('abs-json-control').text).stages[0].steps[1].derive.value,
    {abs: {literal: -9}});
  assert.deepEqual(cases.get('abs-sql-field').expected,
    [{id: 1, value: 4}, {id: 2, value: null}, {id: 3, value: 9}, {id: 3, value: 9}]);
  assert.deepEqual(cases.get('abs-pipe-field').expected, cases.get('abs-sql-field').expected);
});

test('absolute-value fixtures distinguish NULL, lazy demand, type refusal and child failure', () => {
  assert.deepEqual(cases.get('abs-literal-null').expected, [{value: null, typed_value: null}]);
  assert.deepEqual(cases.get('abs-number-parameter').parameters, {n: -4});
  assert.deepEqual(cases.get('abs-lazy-operand').expected, [{value: 9}]);
  assert.deepEqual(cases.get('abs-lazy-failure').expected, [{value: 7}]);
  assert.deepEqual(cases.get('abs-empty-failure').expected, []);
  assert.equal(absSuccesses.length, 14);
  assert.equal(absRefusals.length, 8);
  const zero = cases.get('abs-authored-negative-zero');
  assert.equal(zero.text, 'SELECT ABS(-0.0) AS value');
  assert.deepEqual(zero.expected, [{value: 0}]);
  assert.equal(Object.is(zero.expected[0].value, -0), false);
  assert.deepEqual(zero.columns, [{name: 'value', contract: {type: 'number', nullable: false}}]);
  assert.equal(zero.sourceReadCount, 0);
  assert.equal(zero.sourceReadSessionCount, 0);
  assert(!absRefusals.some(item => item.name === zero.name));
  assert.ok(absRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.equal(absExecutionFailures.length, 2);
  assert.deepEqual(absExecutionFailures.find(item => item.name === 'abs-failure-after-valid-row').sourceRows,
    [{id: 1, amount: -2}, {id: 2, amount: 0}]);
});

test('absolute-value corpus participates in the normal producer and a bounded selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'absSuccesses'], ['refusals', 'absRefusals'],
    ['executionFailures', 'absExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('absOnly ? {successes: absSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\babsOnly\b/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ABS_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/abs-source-input.mjs', 'abs-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = [^;]*'--abs-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--abs-only')) return;"));
});
