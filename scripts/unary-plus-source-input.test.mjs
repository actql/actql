import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {unaryPlusSuccesses, unaryPlusRefusals, unaryPlusExecutionFailures}
  from './fixtures/unary-plus-source-input.mjs';
import {signedLiteralSuccesses, signedLiteralRefusals}
  from './fixtures/unary-plus-source-input.mjs';

test('signed-literal controls fix grouped values independently and retain typed refusals', () => {
  const cases = new Map(signedLiteralSuccesses.map(item => [item.name, item]));
  const control = cases.get('unary-plus-group-json-control');
  const program = JSON.parse(control.text);
  assert.deepEqual(program.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(program.stages[1].steps[0].derive.key,
    {add: [{field: 'amount'}, {literal: 1}]});
  assert.deepEqual(program.stages[1].steps[1].group.by, ['key']);
  assert.deepEqual(control.expected,
    [{bucket: -3, n: 1}, {bucket: 1, n: 2}, {bucket: null, n: 1}]);
  assert.deepEqual(control.columns, [{name: 'bucket', contract: {type: 'number', nullable: true}},
    {name: 'n', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(cases.get('unary-plus-group-selected-plus').expected, control.expected);
  assert.deepEqual(cases.get('unary-plus-group-empty').columns, control.columns);
  assert.deepEqual(cases.get('unary-plus-group-empty').expected, []);
  assert.deepEqual(cases.get('unary-plus-group-sql-pipe-tail').expected, [{bucket: 1, n: 2}]);
  assert.deepEqual(cases.get('unary-plus-signed-literal-alias-receiver').expected,
    [{amount: 5}, {amount: 1}, {amount: null}]);
  assert.deepEqual(signedLiteralRefusals.map(item => item.expectedCode),
    ['ClientProgramInvalidInput', 'ClientProgramInvalidInput', 'ClientProgramImplementationLimit']);
  for (const item of [...signedLiteralSuccesses, ...signedLiteralRefusals]) {
    assert.equal(item.sourceReadSessionCount ?? 1, 1);
  }
});

test('numeric identity fixtures retain NULL, duplicates, negative values and ordered contracts', () => {
  const cases = new Map(unaryPlusSuccesses.map(item => [item.name, item]));
  const sql = cases.get('unary-plus-sql-field');
  assert.deepEqual(sql.expected, sql.sourceRows.map(({id, amount}) => ({id, value: amount})));
  assert.deepEqual(cases.get('unary-plus-pipe-field').expected, sql.expected);
  assert.deepEqual(cases.get('unary-plus-empty').expected, []);
  assert.deepEqual(cases.get('unary-plus-empty').columns, sql.columns);
  assert.deepEqual(cases.get('unary-plus-nullable-parameter').columns,
    [{name: 'value', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(cases.get('unary-plus-negative-parameter').expected, [{value: -7}]);
  const control = JSON.parse(cases.get('unary-plus-json-control').text);
  assert.deepEqual(control.stages[0].steps[1].derive.value,
    {negate: {negate: {literal: -7}}});
  const all = [...unaryPlusSuccesses, ...unaryPlusRefusals, ...unaryPlusExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('qualified input and output alias sorting have independently different orders', () => {
  const cases = new Map(unaryPlusSuccesses.map(item => [item.name, item]));
  const alias = cases.get('unary-plus-order-output-alias');
  const input = cases.get('unary-plus-order-qualified-input');
  assert.deepEqual(alias.expected.map(row => row.id), [3, 3, 1, 2]);
  assert.deepEqual(input.expected.map(row => row.id), [1, 3, 3, 2]);
  assert.deepEqual(alias.sourceRows, input.sourceRows);
  assert.deepEqual(alias.columns, input.columns);
  assert.equal(alias.sourceReadSessionCount, 1);
  assert.equal(input.sourceReadSessionCount, 1);
});

test('normal packed corpus and focused invocation execute the same authored cases', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'unaryPlusSuccesses'], ['refusals', 'unaryPlusRefusals'],
    ['executionFailures', 'unaryPlusExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('unaryPlusOnly ? {successes: unaryPlusSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\bunaryPlusOnly\b/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_UNARY_PLUS_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/unary-plus-source-input.mjs', 'unary-plus-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^;]*'--unary-plus-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--unary-plus-only')) return;"));
});
