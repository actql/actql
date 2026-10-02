import test from 'node:test';
import assert from 'node:assert/strict';
import { distinct } from './distinct.mjs';
import { initialState, clone } from './engine.mjs';
test('whole-row distinct compares every field including NULL and preserves first-occurrence order', () => {
  const rows = [
    { id: 'first', values: { extra: 1, k: null, tag: 0 } },
    { id: 'different', values: { extra: 1, k: 2, tag: 0 } },
    { id: 'last', values: { extra: 1, k: null, tag: 0 } },
  ];
  const before = clone(rows);
  assert.deepEqual(distinct.oracle(rows).map(r => r.id), ['first', 'different']);
  assert.deepEqual(rows, before);
  assert.deepEqual(distinct.oracle([]), []);
});
test('whole-row registration retains schema and requires its exact variant', () => {
  const state = initialState();
  assert.deepEqual(distinct.contract(state), state);
  assert(distinct.admits(state, {}));
  assert(!distinct.admits({ ...state, order: { total: false } }, {}));
  for (const args of [null, [], { fields: ['extra'] }, { keyed: true }]) assert(!distinct.admits(state, args));
  assert.deepEqual(distinct.syntax({}), { distinct: true });
});
