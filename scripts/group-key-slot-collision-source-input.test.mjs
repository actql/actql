import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {groupKeyCollisionProgram as program, groupSelectScopeSuccesses as successes,
  groupSelectScopeRefusals as refusals} from './fixtures/group-select-scope-source-input.mjs';

test('independent GROUP collision control preserves predicate key and public nullable column order', () => {
  const cases = successes.filter(item => item.name.startsWith('group-select-scope-private-key-'));
  assert.equal(cases.length, 7);
  const get = name => cases.find(item => item.name.endsWith('-' + name));
  assert.deepEqual(JSON.parse(get('independent-json').text), program);
  assert.deepEqual(program.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(program.stages[1].steps[0].derive,
    {key: {add: [{field: 'x'}, {literal: 1}]}});
  assert.deepEqual(program.stages[1].steps[1].group,
    {by: ['key'], aggregates: {n: {fn: 'count'}}});
  assert.deepEqual(program.stages[1].results.rows.fields, ['bucket', 'n']);
  assert.deepEqual(get('sql-input').expected,
    [{bucket: null, n: 1}, {bucket: 2, n: 1}, {bucket: 3, n: 2}]);
  assert.deepEqual(get('sql-input').columns, [{name: 'bucket', contract: {type: 'number', nullable: true}},
    {name: 'n', contract: {type: 'number', nullable: false}}]);
  assert.notEqual(get('sql-input').sourceRows[0].id, get('sql-input').sourceRows[2].id);
  assert.equal(get('sql-input').sourceRows[0].amount, get('sql-input').sourceRows[2].amount);
  assert.deepEqual(get('empty').expected, []);
  assert.ok(get('quoted-case').text.includes('AS `AQL_GROUP_KEY_0`'));
  assert.deepEqual(get('output-alias').expected,
    [{bucket: null, aql_group_key_0: 1}, {bucket: 2, aql_group_key_0: 1}, {bucket: 3, aql_group_key_0: 2}]);
  for (const item of cases) assert.equal(item.sourceReadSessionCount, 1);
  assert.ok(refusals.find(item => item.name === 'group-select-scope-private-key-ungrouped-input')
    .text.includes('HAVING colliding.aql_group_key_0 > 0'));
  assert.equal(refusals.find(item => item.name === 'group-select-scope-private-key-ungrouped-input')
    .expectedCode, 'ClientProgramInvalidInput');
  assert.equal(refusals.find(item => item.name === 'group-select-scope-numeric-distinct-unselected')
    .expectedCode, 'ClientProgramImplementationLimit');
});

test('normal public acceptance and the existing focused Group selection retain the collision fixtures', async () => {
  const app = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(app.includes('scopeInputs.successes.push(...groupSelectScopeSuccesses)'));
  assert.ok(app.includes('scopeInputs.refusals.push(...groupSelectScopeRefusals)'));
  assert.ok(app.includes('groupSelectScopeOnly ? {successes: groupSelectScopeSuccesses, refusals: groupSelectScopeRefusals}'));
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/group-select-scope-source-input.mjs', 'group-select-scope-source-input.mjs']"));
  assert.ok(driver.includes('--group-select-scope-only'));
});
