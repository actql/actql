import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {groupSelectScopeSuccesses, groupSelectScopeRefusals}
  from './fixtures/group-select-scope-source-input.mjs';

const cases = new Map(groupSelectScopeSuccesses.map(item => [item.name, item]));
test('numeric reuse fixtures retain independent values, NULLs, duplicates and alias scope', () => {
  const grouped = cases.get('group-select-scope-numeric-sql-group');
  assert.deepEqual(grouped.expected,
    [{next: 2, n: 1}, {next: 3, n: 1}, {next: 4, n: 2}]);
  assert.deepEqual(cases.get('group-select-scope-numeric-json-control').expected,
    grouped.expected);
  assert.deepEqual(cases.get('group-select-scope-numeric-nullable-group').expected,
    [{next: null, n: 1}, {next: 21, n: 1}, {next: 31, n: 2}]);
  assert.deepEqual(cases.get('group-select-scope-numeric-distinct-reuse').expected,
    [{next: 4}, {next: 3}]);
  // ORDER uses the output amount: the keys are NULL, 20 and 30, not the
  // selected values NULL, -19 and -29. Reusing SELECT reverses the last two.
  const alias = cases.get('group-select-scope-numeric-distinct-alias-guard');
  assert.deepEqual(alias.expected, [{amount: null}, {amount: -19}, {amount: -29}]);
  assert.deepEqual(alias.columns,
    [{name: 'amount', contract: {type: 'number', nullable: true}}]);
  for (const fixture of groupSelectScopeSuccesses.filter(item => item.name.includes('-numeric-'))) {
    assert.equal(fixture.sourceReadSessionCount, 1);
  }
  const control = JSON.parse(cases.get('group-select-scope-numeric-json-control').text);
  assert.deepEqual(control.stages[1].steps, [
    {from: 'records', derive: {group_value: {add: [{field: 'id'}, {literal: 1}]}}},
    {group: {by: ['group_value'], aggregates: {n: {fn: 'count'}}}},
    {select: [{next: 'group_value'}, 'n']},
    {sort: [{field: 'next', dir: 'asc', nulls: 'first'}], as: 'summary'},
  ]);
  assert.deepEqual(control.stages[1].results.rows.fields, ['next', 'n']);
  assert.equal(groupSelectScopeRefusals.filter(item => item.name.includes('-numeric-')).length, 2);
});

test('numeric reuse fixtures remain part of ordinary and focused public acceptance', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...groupSelectScopeSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...groupSelectScopeRefusals)'));
  assert.ok(fixture.includes('groupSelectScopeOnly ? {successes: groupSelectScopeSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GROUP_SELECT_SCOPE_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/group-select-scope-source-input.mjs', 'group-select-scope-source-input.mjs']"));
});
