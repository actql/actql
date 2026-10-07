import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {correlatedUnnestSuccesses, correlatedUnnestRefusals, correlatedUnnestProgram,
  correlatedUnnestFilterLimitProgram}
  from './fixtures/correlated-unnest-source-input.mjs';

test('correlated expansion obligations distinguish current arrays and original receivers', () => {
  const byName = new Map(correlatedUnnestSuccesses.map(value => [value.name, value]));
  const control = byName.get('correlated-unnest-json-control');
  assert.deepEqual(control.expected, [{id: 1, element: 1, position: 0},
    {id: 2, element: 2, position: 0}, {id: 2, element: null, position: 1}, {id: 2, element: 2, position: 2}]);
  assert.deepEqual(correlatedUnnestProgram.stages[0].steps[5],
    {unnest: {column: 'array', as: 'element', with_index: 'position'}});
  assert.deepEqual(byName.get('correlated-unnest-immutable-range').expected, control.expected);
  assert.notDeepEqual(byName.get('correlated-unnest-current-column').expected, control.expected);
  for (const name of ['empty-parents', 'empty-arrays']) {
    assert.deepEqual(byName.get('correlated-unnest-' + name).expected, []);
    assert.deepEqual(byName.get('correlated-unnest-' + name).columns, control.columns);
  }
  const acquired = byName.get('correlated-unnest-acquired-parent');
  assert.equal(acquired.sourceReadCount, 1);
  assert.equal(acquired.sourceReadSessionCount, 1);
  assert.equal(acquired.expected.length, 6);
  assert.deepEqual(acquired.expected.map(row => row.id), [1, 1, 1, 2, 2, 2]);
  assert.equal(new Set([...correlatedUnnestSuccesses, ...correlatedUnnestRefusals].map(value => value.name)).size,
    correlatedUnnestSuccesses.length + correlatedUnnestRefusals.length);
});

test('correlated expansion is registered in normal and focused packed execution', () => {
  const corpus = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(corpus.includes('scopeInputs.successes.push(...correlatedUnnestSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...correlatedUnnestRefusals)'));
  assert.ok(corpus.includes('correlatedUnnestOnly ? {successes: correlatedUnnestSuccesses'));
  assert.ok(driver.includes("['scripts/fixtures/correlated-unnest-source-input.mjs', 'correlated-unnest-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_CORRELATED_UNNEST_ONLY = '1'"));
  assert.ok(driver.includes("process.argv.includes('--correlated-unnest-only')) return;"));
});

test('filter/LIMIT common control retains the original predicate, order and bound', () => {
  const control = correlatedUnnestSuccesses.find(item => item.name === 'correlated-unnest-filter-limit-json-control');
  const source = correlatedUnnestSuccesses.find(item => item.name === 'correlated-unnest-filter-limit');
  assert.deepEqual(JSON.parse(control.text), correlatedUnnestFilterLimitProgram);
  assert.deepEqual(control.expected, [{id: 1, element: 1, position: 0}, {id: 2, element: 2, position: 0}]);
  assert.deepEqual(source.expected, control.expected);
  assert.deepEqual(correlatedUnnestFilterLimitProgram.stages[0].steps.slice(6), [
    {filter: {not: {is_null: {field: 'element'}}}},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}, {field: 'position', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'element', 'position']},
    {take: {count: 2, offset: 0}, as: 'limited'},
  ]);
  assert.deepEqual(control.parameters, source.parameters);
  assert.equal(control.parameterDeclarations, undefined);
  assert.match(source.text, /WHERE element IS NOT NULL ORDER BY p\.id, position LIMIT 2$/u);
});
