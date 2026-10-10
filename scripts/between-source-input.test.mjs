import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {betweenSuccesses, betweenRefusals, betweenExecutionFailures} from './fixtures/between-source-input.mjs';

test('BETWEEN expectations preserve false AND unknown, NULL typing, bounds and duplicate values', () => {
  const cases = new Map(betweenSuccesses.map(input => [input.name, input]));
  assert.deepEqual(cases.get('between-null-truth-table').expected,
    [{false_first: false, false_second: false, unknown: null, null_value: null, true_not: true}]);
  assert.ok(cases.get('between-null-truth-table').columns.every(column => column.contract.nullable));
  assert.deepEqual(cases.get('between-inclusive-and-reversed').expected,
    [{lower: true, upper: true, outside: false, reversed: false}]);
  const control = JSON.parse(cases.get('between-json-null-boundary').text);
  assert.deepEqual(control.stages[0].steps[1].derive.value,
    {between: [{literal: 3}, {literal: 4}, {literal: null}]});
  for (const name of ['between-acquired-json', 'between-acquired-sql', 'between-acquired-pipe']) {
    assert.deepEqual(cases.get(name).expected, [{id: 1}, {id: 2}, {id: 3}]);
    assert.deepEqual(cases.get(name).sourceRows.filter(row => row.amount === 2).map(row => row.id), [2, 3]);
    assert.equal(cases.get(name).sourceReadSessionCount, 1);
  }
  assert.deepEqual(cases.get('between-empty').columns, [{name: 'value', contract: {type: 'boolean', nullable: true}}]);
  assert.deepEqual(cases.get('between-parameter-null').parameters, {p: null});
  assert.ok(betweenExecutionFailures.some(input => input.text.includes('1 BETWEEN 2 AND (1 / 0)')));
  const all = [...betweenSuccesses, ...betweenRefusals, ...betweenExecutionFailures];
  assert.equal(new Set(all.map(input => input.name)).size, all.length);
});

test('BETWEEN joins the normal packed corpus and a bounded selection with the same fixtures', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'betweenSuccesses'], ['refusals', 'betweenRefusals'],
    ['executionFailures', 'betweenExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/^const scopeOnly = (.+);$/mu)[1].split(/\s*\|\|\s*/u).includes('betweenOnly'));
  assert.ok(fixture.includes('betweenOnly ? {successes: betweenSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_BETWEEN_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/between-source-input.mjs', 'between-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--between-only'/u);
  assert.ok(driver.slice(driver.indexOf('// The first Host process has exited:') - 7000)
    .includes("if (process.argv.includes('--between-only')) return;"));
});
