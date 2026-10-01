import test from 'node:test';
import assert from 'node:assert/strict';
import { generate, inspect, oracle, program, candidates, clone, shrink } from './engine.mjs';
import { baseRegistry } from './registry.mjs';
import { sort } from './sort.mjs';
const row = (id, k, tag) => ({ id, values: { extra: 0, k, tag } });
test('seeded construction tracks schema, exact predecessor and owned order without rejection sampling', () => {
  const cases = generate(baseRegistry);
  assert.deepEqual(cases, generate(baseRegistry));
  const pairs = new Set(cases.filter(c => c.id.startsWith('pair:')).map(c => c.steps.map(s => s.op).join('/')));
  assert.equal(pairs.size, 9);
  for (const c of cases) {
    const state = inspect(c, baseRegistry);
    assert.equal(state.length, c.steps.length + 1);
    const p = JSON.parse(program(c, baseRegistry).steps);
    p.forEach((s, i) => assert.equal(s.from, i ? `s${i - 1}` : 'prior'));
    assert(state.every(s => s.order.total));
  }
  assert(cases.some(c => c.rows.length === 0));
  assert(cases.some(c => c.rows.some(r => r.values.k === null)));
  assert(cases.some(c => new Set(c.rows.map(r => JSON.stringify(r.values))).size < c.rows.length));
  assert(cases.some(c => oracle(c, baseRegistry).rows.length === 0));
});
test('independent insertion oracle uses admitted relative ties, not unasserted data uniqueness', () => {
  const rows = [row('a', 1, 2), row('b', 1, -1), row('c', null, 0), row('d', -1, 1)];
  assert.deepEqual(sort.oracle(rows, { field: 'k', dir: 'desc', nulls: 'first' }).map(r => r.id), ['c', 'a', 'b', 'd']);
  assert.deepEqual(sort.oracle(rows, { field: 'k', dir: 'asc', nulls: 'last' }).map(r => r.id), ['d', 'a', 'b', 'c']);
});
test('shrinking rebinds references and excludes removal of required projected fields', () => {
  const c = { id: 'typed', rows: [row('a', 2, 1), row('b', null, 0)], steps: [
    { id: 'keep', op: 'select', args: { fields: ['tag', 'k'] } },
    { id: 'filter', op: 'filter', args: { mode: 'gt', field: 'k', threshold: 1 } },
    { id: 'sort', op: 'sort', args: { field: 'tag', dir: 'desc', nulls: 'last' } },
  ] };
  const invalid = clone(c); invalid.steps[0].args.fields = ['tag'];
  assert.throws(() => inspect(invalid, baseRegistry), /premise/);
  for (const v of candidates(c, baseRegistry)) {
    assert.doesNotThrow(() => inspect(v, baseRegistry));
    JSON.parse(program(v, baseRegistry).steps).forEach((s, i) => assert.equal(s.from, i ? `s${i - 1}` : 'prior'));
  }
});
test('shrinker preserves explicit predicate and exhausts every allowed one-step reduction', async () => {
  const c = { id: 'local', rows: [row('anchor-a', 2, 1), row('anchor-b', 2, -1), row('noise', 0, 0)], steps: [
    { id: 'anchor-sort', op: 'sort', args: { field: 'k', dir: 'asc', nulls: 'last' } },
    { id: 'noise', op: 'filter', args: { mode: 'true' } },
  ] };
  const retains = v => v.steps.some(s => s.id === 'anchor-sort') &&
    ['anchor-a', 'anchor-b'].every(id => v.rows.some(r => r.id === id));
  const result = await shrink(c, baseRegistry, async values => values.map(retains), (_v, observed) => observed);
  assert(retains(result.minimal));
  assert.equal(result.minimal.rows.length, 2);
  assert.equal(result.minimal.steps.length, 1);
  assert(result.finalObservations.every(x => !x));
});
