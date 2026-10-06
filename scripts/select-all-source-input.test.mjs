import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {selectAllSuccesses, selectAllRefusals} from './fixtures/select-all-source-input.mjs';

test('SELECT ALL expectations distinguish multiplicity, NULL, filtering and LIMIT', () => {
  const byName = new Map(selectAllSuccesses.map(value => [value.name, value]));
  const limited = [{amount: 1}, {amount: 1}, {amount: 2}];
  for (const name of ['json-control', 'sql-limited', 'pipe-limited']) {
    assert.deepEqual(byName.get('select-all-' + name).expected, limited);
  }
  assert.notDeepEqual(byName.get('select-all-sql-full').expected,
    byName.get('select-all-sql-distinct-control').expected);
  assert.deepEqual(byName.get('select-all-sql-empty').expected, []);
  assert.deepEqual(byName.get('select-all-sql-empty').columns,
    [{name: 'amount', contract: {type: 'number', nullable: true}}]);
  const control = JSON.parse(byName.get('select-all-json-control').text);
  assert.deepEqual(control.stages[1].steps, [
    {from: 'records', filter: {gt: [{field: 'id'}, {literal: 0}]}},
    {select: ['amount']}, {sort: [{field: 'amount', dir: 'asc', nulls: 'first'}]},
    {take: {count: 3, offset: 1}, as: 'ordered'},
  ]);
  const names = [...selectAllSuccesses, ...selectAllRefusals].map(value => value.name);
  assert.equal(new Set(names).size, names.length);
});

test('ordinary packed corpus includes SELECT ALL and narrow selection keeps the real boundary', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...selectAllSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...selectAllRefusals)'));
  assert.ok(fixture.includes('selectAllOnly ? {successes: selectAllSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_SELECT_ALL_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/select-all-source-input.mjs', 'select-all-source-input.mjs']"));
  assert.ok(driver.includes("process.argv.some(flag => ['--select-all-only'"));
  assert.ok(driver.includes("if (process.argv.includes('--select-all-only')) return;"));
});
