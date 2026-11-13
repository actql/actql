import test from 'node:test';
import assert from 'node:assert/strict';
import {derive} from './derive.mjs';
import {registry, corpusBaseline} from './registry.mjs';
import {registrations} from './obligations.mjs';
import {fixedCorpus, coverage} from './corpus.mjs';
import {initialState, clone, candidates, inspect, oracle} from './engine.mjs';
import {plan} from './proof-parts.mjs';

test('numeric derive has independent nullable arithmetic, schema and occurrence observations', () => {
  const rows = [
    {id: 'first', values: {extra: 1, k: null, tag: 0}},
    {id: 'middle', values: {extra: 0, k: -1, tag: 2}},
    {id: 'duplicate', values: {extra: 1, k: null, tag: 0}},
  ];
  const before = clone(rows), args = {field: 'k', output: 'd_k', increment: 2};
  assert.deepEqual(derive.oracle(rows, args), [
    {id: 'first', values: {extra: 1, k: null, tag: 0, d_k: null}},
    {id: 'middle', values: {extra: 0, k: -1, tag: 2, d_k: 1}},
    {id: 'duplicate', values: {extra: 1, k: null, tag: 0, d_k: null}},
  ]);
  assert.deepEqual(rows, before);
  assert.deepEqual(derive.oracle([], args), []);
  const state = initialState(), after = derive.contract(state, args);
  assert.deepEqual(after.fields, ['d_k', 'extra', 'k', 'tag']);
  assert.deepEqual(after.schema.d_k, {type: 'number', nullable: true});
  assert.deepEqual(after.order, state.order);
  assert.deepEqual(state, initialState());
});

test('numeric derive refuses unreviewed variants and output/input collisions', () => {
  const state = initialState(), valid = {field: 'k', output: 'd_k', increment: 1};
  assert(derive.admits(state, valid));
  for (const value of [null, [], {}, {...valid, output: 'k'}, {...valid, field: 'missing'},
    {...valid, output: 'invalid-name'}, {...valid, increment: 3}, {...valid, increment: 0.5},
    {...valid, sequential: true}]) assert(!derive.admits(state, value));
  assert(!derive.admits({...state, schema: {...state.schema, k: {type: 'text', nullable: true}}}, valid));
  assert.deepEqual(derive.syntax(valid), {derive: {d_k: {add: [{field: 'k'}, {literal: 1}]}}});
});

test('existing generator completes derive obligations and existing shrinker preserves derived references', () => {
  const cases = fixedCorpus(registry, registrations), witnesses = coverage(cases, registry, registrations);
  for (const obligation of registrations.derive.obligations)
    assert(witnesses[`derive:${obligation.id}`].length > 0);
  const retained = fixedCorpus(corpusBaseline, registrations);
  assert.deepEqual(cases.slice(0, retained.length), retained);
  assert.equal(retained.length, 86);
  const normal = Object.values(plan.parts).filter(part => part.role === 'capacity-normal');
  assert.equal(normal.length, 1);
  assert.equal(cases.length, normal[0].obligations.finalNormal.caseCount);
  assert.equal(new Set(cases.map(value => value.id)).size, cases.length);
  assert(cases.slice(retained.length).every(value => value.steps.some(step => step.op === 'derive')));
  const pairs = cases.filter(value => value.id.startsWith('pair:'));
  assert.equal(pairs.filter(value => value.steps.some(step => step.op === 'derive')).length, 13);
  const value = {id: 'typed-derived', rows: [{id: 'a', values: {extra: 1, k: null, tag: -1}}], steps: [
    {id: 'compute', op: 'derive', args: {field: 'k', output: 'd_k', increment: 2}},
    {id: 'project', op: 'select', args: {fields: ['d_k', 'tag']}},
  ]};
  assert.deepEqual(oracle(value, registry).rows, [[null, -1]]);
  const missing = clone(value); missing.steps.shift();
  assert.throws(() => inspect(missing, registry), /Unmet operation premise/u);
  for (const reduction of candidates(value, registry)) assert.doesNotThrow(() => inspect(reduction, registry));
  const obligation = 'derive:nonzero arithmetic retains its source field';
  assert.throws(() => coverage(cases.filter(item => !witnesses[obligation].includes(item.id)), registry, registrations),
    /Missing concrete semantic obligation/u);
});
