import assert from 'node:assert/strict';
import test from 'node:test';
import {uniquePublicQueryCases} from './fixtures/public-query-cases.mjs';
import {relationDataSuccesses} from './fixtures/public-query-input.mjs';
import {propertyGraphSourceSuccesses} from './fixtures/property-graph-source-input.mjs';

test('shared Relation controls and Graph source cases have one request each', () => {
  const selected = uniquePublicQueryCases([
    ...relationDataSuccesses, ...propertyGraphSourceSuccesses,
  ]);
  assert.equal(selected.length, 20);
  assert.deepEqual(selected.slice(0, 3).map(item => item.name), [
    'data-set-order-reuses-hidden-slot', 'data-quoted-set-order',
    'data-retained-results',
  ]);
  assert.equal(selected.filter(item => item.name.startsWith('keyed-')).length, 17);
  assert.deepEqual(selected, propertyGraphSourceSuccesses);
});

test('duplicate request names cannot hide conflicting source or expectations', () => {
  const original = relationDataSuccesses[0];
  for (const conflicting of [{...original, text: 'SELECT 999 AS id'},
    {...original, results: {nodes: {rows: [{id: 999}]}}}]) {
    assert.throws(() => uniquePublicQueryCases([original, conflicting]),
      /Conflicting public query fixture/u);
  }
});
