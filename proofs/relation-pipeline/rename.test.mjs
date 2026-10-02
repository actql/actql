import assert from 'node:assert/strict';
import test from 'node:test';
import { rename } from './rename.mjs';
import { initialState, inspect, oracle, program, candidates, clone } from './engine.mjs';
import { registry } from './registry.mjs';

test('rename uses canonical input expansion while preserving field contracts and logical order', () => {
  const state = { ...initialState(), fields: ['tag', 'k', 'extra'],
    order: { origin: 's0', kind: 'sort', total: true,
      keys: [{ field: 'k', dir: 'asc', nulls: 'last' }], ties: [initialState().order] } };
  const before = clone(state);
  const after = rename.contract(state, { mapping: { extra: 'z', k: 'a' } });
  assert.deepEqual(after.fields, ['z', 'a', 'tag']);
  assert.deepEqual(after.schema, {
    z: { type: 'number', nullable: false }, a: { type: 'number', nullable: true },
    tag: { type: 'number', nullable: false },
  });
  assert.equal(after.order.origin, 's0');
  assert.deepEqual(after.order.keys, [{ field: 'a', dir: 'asc', nulls: 'last' }]);
  assert.deepEqual(state, before);
});

test('simultaneous swap preserves unequal values, NULL and occurrence order', () => {
  const rows = [
    { id: 'null', values: { extra: 2, k: null, tag: -1 } },
    { id: 'number', values: { extra: -2, k: 1, tag: 0 } },
  ];
  const before = clone(rows);
  assert.deepEqual(rename.oracle(rows, { mapping: { extra: 'k', k: 'extra' } }), [
    { id: 'null', values: { k: 2, extra: null, tag: -1 } },
    { id: 'number', values: { k: -2, extra: 1, tag: 0 } },
  ]);
  assert.deepEqual(rows, before);
  const state = rename.contract(initialState(), { mapping: { extra: 'k', k: 'extra' } });
  assert.equal(state.schema.extra.nullable, true);
  assert.equal(state.schema.k.nullable, false);
});

test('unknown sources, duplicate outputs and invalid field identifiers are outside the admitted rename variant', () => {
  const state = initialState();
  for (const mapping of [{ missing: 'new' }, { extra: 'k' }, { k: '' }, { k: 'not a field' }]) {
    assert.equal(rename.admits(state, { mapping }), false);
  }
  assert.equal(rename.admits(state, { mapping: {} }), true);
  assert.equal(rename.admits(state, { mapping: { extra: 'k', k: 'extra' } }), true);
});

test('downstream references use the renamed field and reductions preserve their premises', () => {
  const descriptors = registry;
  const value = { id: 'new-field', rows: [
    { id: 'kept', values: { extra: 0, k: 1, tag: 2 } },
    { id: 'null', values: { extra: 0, k: null, tag: 1 } },
    { id: 'removed', values: { extra: 0, k: -1, tag: 0 } },
  ], steps: [
    { id: 'rename', op: 'rename', args: { mapping: { k: 'key' } } },
    { id: 'filter', op: 'filter', args: { mode: 'gt', field: 'key', threshold: 0 } },
    { id: 'select', op: 'select', args: { fields: ['key', 'tag'] } },
  ] };
  assert.deepEqual(oracle(value, descriptors).rows, [[1, 2]]);
  assert.deepEqual(JSON.parse(program(value, descriptors).steps), [
    { from: 'prior', rename: { k: 'key' }, as: 's0' },
    { from: 's0', filter: 'key > 0', as: 's1' },
    { from: 's1', select: ['key', 'tag'], as: 's2' },
  ]);
  const wrong = clone(value);
  wrong.steps[1].args.field = 'k';
  assert.throws(() => inspect(wrong, descriptors), /Unmet operation premise/);
  for (const reduction of candidates(value, descriptors)) {
    assert.doesNotThrow(() => inspect(reduction, descriptors));
    assert(reduction.steps.some(step => step.id === 'rename'));
  }
});
