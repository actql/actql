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
  assert.deepEqual(byName.get('correlated-unnest-current-column').columns, [
    {name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'element', contract: {type: 'number', nullable: false}},
    {name: 'position', contract: {type: 'number', nullable: false}},
  ]);
  assert.deepEqual(byName.get('correlated-unnest-immutable-range').columns, control.columns);
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

test('INNER expansion preserves the explicit ON filter and independently counted duplicate matches', async () => {
  const {innerCorrelatedUnnestProgram, innerCorrelatedUnnestImmutableProgram}
    = await import('./fixtures/correlated-unnest-source-input.mjs');
  const byName = new Map(correlatedUnnestSuccesses.map(value => [value.name, value]));
  const control = byName.get('correlated-unnest-inner-json-control');
  assert.deepEqual(JSON.parse(control.text), innerCorrelatedUnnestProgram);
  assert.deepEqual(innerCorrelatedUnnestProgram.stages[0].steps[6],
    {filter: {eq: [{field: 'element'}, {field: 'id'}]}});
  assert.deepEqual(control.expected, [{id: 1, element: 1, position: 0},
    {id: 2, element: 2, position: 0}, {id: 2, element: 2, position: 2}]);
  assert.deepEqual(byName.get('correlated-unnest-inner-sql-on').expected, control.expected);
  assert.deepEqual(byName.get('correlated-unnest-inner-pipe-on').expected, control.expected);
  assert.notDeepEqual(byName.get('correlated-unnest-inner-no-on').expected, control.expected);
  assert.deepEqual(byName.get('correlated-unnest-inner-on-false').expected, []);
  assert.deepEqual(byName.get('correlated-unnest-inner-empty').columns, control.columns);
  assert.deepEqual(byName.get('correlated-unnest-inner-immutable-parent').expected,
    [{id: 99, element: 1, position: 0}, {id: 99, element: 2, position: 0},
      {id: 99, element: 2, position: 2}]);
  const immutable = byName.get('correlated-unnest-inner-immutable-parent');
  assert.match(immutable.text, /SET id = 99.*ON element = p\.id.*SELECT id, element, position/u);
  assert.deepEqual(JSON.parse(byName.get('correlated-unnest-inner-immutable-json-control').text),
    innerCorrelatedUnnestImmutableProgram);
  assert.deepEqual(innerCorrelatedUnnestImmutableProgram.stages[0].steps.slice(4, 6),
    [{derive: {original_id: {field: 'id'}}}, {derive: {current_id: {literal: 99}}}]);
  assert.deepEqual(innerCorrelatedUnnestImmutableProgram.stages[0].steps[8],
    {filter: {eq: [{field: 'element'}, {field: 'original_id'}]}});
  assert.deepEqual(innerCorrelatedUnnestImmutableProgram.stages[0].steps[10],
    {select: [{id: 'current_id'}, 'element', 'position'], as: 'selected'});
  const acquired = byName.get('correlated-unnest-inner-acquired-parent');
  assert.equal(acquired.sourceReadCount, 1);
  assert.equal(acquired.sourceReadSessionCount, 1);
  assert.deepEqual(acquired.expected, control.expected.slice(1));
  const refusals = correlatedUnnestRefusals.filter(item => item.name.startsWith('correlated-unnest-refusal-inner-'));
  assert.equal(refusals.length, 4);
  for (const item of refusals) assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
});

test('correlated expansion is registered in normal and focused packed execution', () => {
  const corpus = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(corpus.includes('scopeInputs.successes.push(...correlatedUnnestSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...correlatedUnnestRefusals)'));
  assert.equal(corpus.split('scopeInputs.successes.push(...correlatedUnnestSuccesses)').length - 1, 1);
  assert.equal(corpus.split('scopeInputs.refusals.push(...correlatedUnnestRefusals)').length - 1, 1);
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

test('retained schemas keep set multiplicity, CTE column order and nullable objects', async () => {
  const {retainedArrayProgram, retainedArraySuccesses, retainedArrayRefusals}
    = await import('./fixtures/correlated-unnest-source-input.mjs');
  const byName = new Map(retainedArraySuccesses.map(value => [value.name, value]));
  const control = byName.get('correlated-unnest-retained-json-control');
  assert.deepEqual(JSON.parse(control.text), retainedArrayProgram);
  assert.deepEqual(retainedArrayProgram.stages[0].steps[5],
    {from: 'parents', append: {with: 'parents'}, as: 'combined'});
  assert.deepEqual(control.expected, [
    {id: 1, element: 1, position: 0}, {id: 1, element: 1, position: 0},
    {id: 2, element: 2, position: 0}, {id: 2, element: 2, position: 0},
    {id: 2, element: null, position: 1}, {id: 2, element: null, position: 1},
    {id: 2, element: 2, position: 2}, {id: 2, element: 2, position: 2},
  ]);
  assert.deepEqual(byName.get('correlated-unnest-retained-pipe-set-star').expected, control.expected);
  assert.deepEqual(byName.get('correlated-unnest-retained-pipe-set-filter-limit').expected,
    [{id: 1, element: 1, position: 0}, {id: 1, element: 1, position: 0},
      {id: 2, element: 2, position: 0}]);
  assert.equal(byName.get('correlated-unnest-retained-empty-set-star').expected.length, 0);
  assert.deepEqual(byName.get('correlated-unnest-retained-cte-current-array').columns[1],
    {name: 'element', contract: {type: 'number', nullable: false}});
  const object = byName.get('correlated-unnest-retained-cte-object-star');
  assert.deepEqual(object.columns.map(column => column.name), ['id', 'label', 'position']);
  assert.deepEqual(object.expected[1], {id: null, label: null, position: 1});
  for (const item of retainedArraySuccesses) {
    assert.ok(correlatedUnnestSuccesses.includes(item));
    assert.equal(item.sourceReadCount, 0);
    assert.equal(item.sourceReadSessionCount, 0);
  }
  for (const item of retainedArrayRefusals) {
    assert.ok(correlatedUnnestRefusals.includes(item));
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
  }
});
