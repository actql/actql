import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {qualifyProgram, groupedQualifyProgram, nullableGroupedQualifyProgram,
  groupedOrderWindowProgram, qualifySuccesses, qualifyRefusals, qualifyExecutionFailures}
  from './fixtures/qualify-source-input.mjs';

test('QUALIFY oracles distinguish aliases inputs NULLs duplicates and output demand', () => {
  const cases = new Map(qualifySuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('qualify-independent-json').text), qualifyProgram);
  assert.deepEqual(qualifyProgram.stages[1].steps[1], {filter: {lte: [{field: 'n'}, {literal: 2}]}});
  assert.deepEqual(cases.get('qualify-alias-collision').expected, [{amount: 20, id: 1}]);
  assert.deepEqual(cases.get('qualify-qualified-input-control').expected, [{amount: null, id: 4}]);
  assert.deepEqual(cases.get('qualify-nullable-filter-and-duplicates').expected,
    [{id: 3, n: 3}, {id: 3, n: 4}]);
  assert.deepEqual(cases.get('qualify-distinct-order-limit').expected, [{amount: 30}]);
  assert.deepEqual(cases.get('qualify-typed-empty').columns, cases.get('qualify-window-alias').columns);
  assert.deepEqual(cases.get('qualify-undemanded-select-error').expected,
    [{ratio: 1, n: 2}, {ratio: 0.5, n: 3}, {ratio: 0.5, n: 4}]);
  const all = [...qualifySuccesses, ...qualifyRefusals, ...qualifyExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('grouped later-clause oracles separate COUNT aliases from retained input keys', () => {
  const cases = new Map(qualifySuccesses.map(item => [item.name, item]));
  for (const [name, control] of [['grouped-alias-json', groupedQualifyProgram],
    ['grouped-nullable-json', nullableGroupedQualifyProgram],
    ['grouped-order-window-json', groupedOrderWindowProgram]]) {
    assert.deepEqual(JSON.parse(cases.get('qualify-' + name).text), control);
  }
  assert.deepEqual(groupedQualifyProgram.stages[1].steps[2],
    {filter: {gt: [{field: 'counted'}, {literal: 1}]}});
  assert.deepEqual(cases.get('qualify-grouped-alias-collision').expected,
    [{original: 3, id: 2, rn: 3}]);
  assert.deepEqual(cases.get('qualify-grouped-qualified-input').expected,
    [{original: 2, id: 1, rn: 2}, {original: 3, id: 2, rn: 3}]);
  assert.deepEqual(cases.get('qualify-grouped-nullable-collision').columns,
    [{name: 'original', contract: {type: 'number', nullable: true}},
      {name: 'amount', contract: {type: 'number', nullable: false}},
      {name: 'rn', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(cases.get('qualify-grouped-count-is-not-null').expected, []);
  assert.deepEqual(cases.get('qualify-grouped-typed-empty').columns,
    cases.get('qualify-grouped-alias-collision').columns);
  assert.deepEqual(cases.get('qualify-grouped-order-window-alias').expected,
    [{original: 3, id: 2}, {original: 1, id: 1}, {original: 2, id: 1}]);
  assert.deepEqual(cases.get('qualify-grouped-order-window-qualified-input').expected,
    [{original: 3, id: 2}, {original: 2, id: 1}, {original: 1, id: 1}]);
  for (const item of qualifySuccesses.filter(item => item.name.startsWith('qualify-grouped-'))) {
    assert.equal(item.sourceReadSessionCount, 1);
    assert.deepEqual(Object.keys(item.expected[0] ?? Object.fromEntries(item.columns.map(c => [c.name, null]))),
      item.columns.map(c => c.name));
  }
  for (const name of ['qualify-grouped-discarded-input', 'qualify-grouped-order-discarded-input']) {
    assert.equal(qualifyRefusals.find(item => item.name === name).expectedCode, 'ClientProgramInvalidInput');
  }
});

test('QUALIFY runs in both the ordinary and narrow packed public corpora', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'qualifySuccesses'], ['refusals', 'qualifyRefusals'],
    ['executionFailures', 'qualifyExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.match(fixture, /const scopeOnly = [^;]*qualifyOnly/u);
  assert.ok(fixture.includes('qualifyOnly ? {successes: qualifySuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_QUALIFY_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/qualify-source-input.mjs', 'qualify-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--qualify-only'/u);
  assert.match(driver, /if \(process\.argv\.includes\('--qualify-only'\)\) return;/u);
});
