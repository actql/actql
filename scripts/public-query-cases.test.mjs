import assert from 'node:assert/strict';
import test from 'node:test';
import {uniquePublicQueryCases} from './fixtures/public-query-cases.mjs';
import {relationDataSuccesses} from './fixtures/public-query-input.mjs';
import {graphSourceSuccesses} from './fixtures/graph-source-input.mjs';

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
