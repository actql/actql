import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {fullJoinScopeProgram, fullJoinScopeSuccesses, fullJoinScopeRefusals,
  fullUsingScopeProgram, fullUsingScopeSuccesses}
  from './fixtures/full-join-scope-source-input.mjs';

test('FULL control retains conditional keys both unmatched sides and declared order', () => {
  const cases = new Map(fullJoinScopeSuccesses.map(item => [item.name, item]));
  const control = JSON.parse(cases.get('full-join-scope-independent-json').text);
  assert.deepEqual(control, fullJoinScopeProgram);
  assert.deepEqual(control.stages[1].steps[0].assert_rows, {unique_by: ['id']});
  assert.equal(control.stages[1].steps[3].join.kind, 'full');
  assert.equal(control.stages[1].steps[3].join.max_output_rows, 10);
  const normal = cases.get('full-join-scope-qualified-star');
  assert.deepEqual(normal.expected, [{amount: null, id: 1, rid: null},
    {amount: 20, id: 2, rid: 2}, {amount: null, id: null, rid: 3}]);
  assert.deepEqual(normal.columns.map(column => column.name), ['amount', 'id', 'rid']);
  assert.ok(normal.columns.every(column => column.contract.nullable));
  assert.deepEqual(cases.get('full-join-scope-empty-typed').expected, []);
  assert.equal(cases.get('full-join-scope-null-join-keys').sourceRows.filter(row => row.amount === null).length, 2);
  assert.ok(cases.get('full-join-scope-pipe-current-row').text.includes('|> FULL JOIN'));
  assert.equal(new Set([...fullJoinScopeSuccesses, ...fullJoinScopeRefusals]
    .map(item => item.name)).size, fullJoinScopeSuccesses.length + fullJoinScopeRefusals.length);
});

test('FULL USING expectations distinguish coalescence qualified keys and alias order', () => {
  const cases = new Map(fullUsingScopeSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('full-join-scope-using-independent-json').text), fullUsingScopeProgram);
  assert.deepEqual(fullUsingScopeProgram.stages[1].steps[4].derive,
    {id: {coalesce: [{field: 'lid'}, {field: 'rid'}]}});
  assert.deepEqual(cases.get('full-join-scope-using-merged-star').expected.map(row => row.id), [1, 2, 3]);
  assert.deepEqual(cases.get('full-join-scope-using-alias-order').expected.map(row => row.id), [-3, -2, -1]);
  assert.deepEqual(cases.get('full-join-scope-using-qualified-order').expected.map(row => row.id), [-1, -2, -3]);
  const composite = cases.get('full-join-scope-using-composite-null-keys');
  assert.deepEqual(composite.columns.map(column => column.name), ['amount', 'id', 'lid', 'rid']);
  assert.deepEqual(composite.expected.filter(row => row.id === 2), [
    {amount: null, id: 2, lid: 2, rid: null}, {amount: null, id: 2, lid: null, rid: 2}]);
  assert.deepEqual(cases.get('full-join-scope-using-later-join').expected.at(-1), {id: 3, lid: null, rid: 3});
  assert.deepEqual(cases.get('full-join-scope-using-empty-typed').expected, []);
  assert.ok(fullJoinScopeRefusals[0].text.includes('USING (id, `ID`)'));
});

test('FULL acceptance is included in normal packed execution', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...fullJoinScopeSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...fullJoinScopeRefusals)'));
  assert.ok(fixture.includes('fullJoinScopeOnly ? {successes: fullJoinScopeSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_FULL_JOIN_SCOPE_ONLY = '1'"));
  assert.ok(driver.includes("if (process.argv.includes('--full-join-scope-only')) return;"));
});
