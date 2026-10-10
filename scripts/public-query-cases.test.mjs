import assert from 'node:assert/strict';
import test from 'node:test';
import {uniquePublicQueryCases} from './fixtures/public-query-cases.mjs';
import {relationDataSuccesses, relationDataRefusals} from './fixtures/public-query-input.mjs';
import {graphSourceSuccesses} from './fixtures/graph-source-input.mjs';
import {pipePivotSuccesses, pipePivotRefusals, pivotArgumentExpressionProgram}
  from './fixtures/pipe-pivot-source-input.mjs';

test('shared Relation controls and Graph source cases have one request each', () => {
  const selected = uniquePublicQueryCases([
    ...relationDataSuccesses, ...graphSourceSuccesses,
  ]);
  assert.equal(selected.length, 42);
  assert.deepEqual(selected.slice(0, 3).map(item => item.name), [
    'data-set-order-reuses-hidden-slot', 'data-quoted-set-order',
    'data-retained-results',
  ]);
  assert.equal(selected.filter(item => item.name.startsWith('keyed-')).length, 35);
  assert.deepEqual(selected.slice(7), graphSourceSuccesses.slice(3));
});

test('duplicate request names cannot hide conflicting source or expectations', () => {
  const original = relationDataSuccesses[0];
  for (const conflicting of [{...original, text: 'SELECT 999 AS id'},
    {...original, results: {nodes: {rows: [{id: 999}]}}}]) {
    assert.throws(() => uniquePublicQueryCases([original, conflicting]),
      /Conflicting public query fixture/u);
  }
});

test('DATA positional fixture keeps NULL duplicates and public output contracts', () => {
  const cases = new Map(relationDataSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('data-anonymous-set-duplicate-order-limit').results.nodes.rows,
    [{id: 1}, {id: 1}]);
  assert.deepEqual(cases.get('data-anonymous-set-null-source').results,
    cases.get('data-anonymous-set-null-json-control').results);
  assert.deepEqual(cases.get('data-anonymous-set-null-source').results.nodes.columns,
    [{name: 'id', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(cases.get('data-anonymous-set-cte-source').results.nodes.rows,
    [{id: 1}, {id: 2}]);
});

test('DATA refusal fixtures distinguish unsupported output names from private references', () => {
  const cases = new Map(relationDataRefusals.map(item => [item.name, item]));
  assert.equal(cases.get('data-anonymous-set-by-name').expectedCode,
    'ClientProgramImplementationLimit');
  assert.equal(cases.get('data-anonymous-set-private-field').expectedCode,
    'ClientProgramInvalidInput');
});

test('PIVOT expression controls distinguish consumed fields, constants and frozen input slots', () => {
  const cases = new Map(pipePivotSuccesses.map(item => [item.name, item]));
  const source = cases.get('pipe-pivot-argument-expression-consumption');
  const control = cases.get('pipe-pivot-argument-expression-json-control');
  assert.deepEqual(source.expected, [{product: 1, A: 5}]);
  assert.deepEqual(source.columns, control.columns);
  assert.deepEqual(source.expected, control.expected);
  assert.deepEqual(JSON.parse(control.text), pivotArgumentExpressionProgram);
  assert.deepEqual(pivotArgumentExpressionProgram.stages[0].steps[2].pivot.index, ['product']);
  assert.deepEqual(cases.get('pipe-pivot-argument-expression-constant').expected,
    [{product: 1, amount: 1, A: 1}, {product: 1, amount: 2, A: 1}]);
  assert.deepEqual(cases.get('pipe-pivot-argument-expression-immutable-range').expected,
    [{product: 1, amount: 7, A: 5}]);
  assert.deepEqual(cases.get('pipe-pivot-argument-expression-current-slot').expected,
    [{product: 1, A: 16}]);
  assert.deepEqual(cases.get('pipe-pivot-argument-expression-property-null-propagation').expected,
    [{product: 1, A: 11}, {product: 2, A: null}, {product: 3, A: null}]);
  assert.equal(pipePivotRefusals.filter(item => item.name.startsWith('pipe-pivot-refusal-argument-expression-')).length, 6);
});
