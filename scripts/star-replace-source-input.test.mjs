import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {starReplaceProgram, starReplaceSuccesses, starReplaceRefusals, starAggregateSnapshotProgram}
  from './fixtures/star-replace-source-input.mjs';

test('star replacements preserve simultaneous inputs types order NULLs and duplicates', () => {
  const cases = new Map(starReplaceSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('star-replace-independent-json').text), starReplaceProgram);
  assert.deepEqual(starReplaceProgram.stages[1].steps[0].select, [{amount: 'id'}, {id: 'amount'}]);
  assert.deepEqual(cases.get('star-replace-sql-swap-and-null').expected,
    [{amount: 2, id: 20}, {amount: 3, id: 30}, {amount: 3, id: 30}, {amount: 1, id: null}]);
  assert.deepEqual(cases.get('star-replace-order-alias-collision').expected.map(row => row.id), [-1, -2, -3, -3]);
  assert.deepEqual(cases.get('star-replace-order-qualified-control').expected.map(row => row.id), [-3, -3, -2, -1]);
  assert.deepEqual(cases.get('star-replace-typed-empty').columns, cases.get('star-replace-sql-swap-and-null').columns);
  assert.deepEqual(cases.get('star-replace-range-snapshot').expected.map(row => row.amount), [null, 20, 30, 30]);
  const all = [...starReplaceSuccesses, ...starReplaceRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('star REPLACE remains in the normal and narrowly selected packed corpora', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'starReplaceSuccesses'], ['refusals', 'starReplaceRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.match(fixture, /const scopeOnly = [^;]*starReplaceOnly/u);
  assert.ok(fixture.includes('starReplaceOnly ? {successes: starReplaceSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_STAR_REPLACE_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/star-replace-source-input.mjs', 'star-replace-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--star-replace-only'/u);
  assert.match(driver, /if \(process\.argv\.includes\('--star-replace-only'\)\) return;/u);
});

test('star aggregate snapshot oracle distinguishes original input from replaced values', () => {
  const cases = starReplaceSuccesses.filter(item => item.name.includes('aggregate-snapshot-'));
  assert.equal(cases.length, 5);
  assert.deepEqual(JSON.parse(cases[0].text), starAggregateSnapshotProgram);
  assert.deepEqual(starAggregateSnapshotProgram.stages[1].steps[0].group,
    {by: ['amount'], aggregates: {id: {fn: 'sum', field: 'amount'}}});
  for (const item of cases) {
    assert.deepEqual(item.expected, [{amount: 11, id: 20}, {amount: 31, id: 30}, {amount: null, id: null}]);
    assert.deepEqual(item.columns.map(entry => [entry.name, entry.contract.nullable]),
      [['amount', true], ['id', true]]);
    assert.notDeepEqual(item.expected.map(row => row.id), [22, 31, null]);
  }
});
