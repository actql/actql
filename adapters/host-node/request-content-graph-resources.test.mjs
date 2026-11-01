import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Actual private caller bodies with explicit Request/current ports. No
// Common, Resource admission, Account, Store or physical ACK is simulated.
function extract(file, name, ports, variable = false) {
  const source = readFileSync(new URL(file, import.meta.url), 'utf8');
  let selected;
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (variable ? node.type === 'VariableDeclarator' && node.id?.name === name
      : node.type === 'Property' && node.key?.name === name) {
      assert.equal(selected, undefined, name); selected = variable ? node.init : node;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(selected, name);
  const body = source.slice(selected.start, selected.end);
  const helpers = file === './ordinary-source-managed.mjs' ? source.slice(source.indexOf('  function constructRequestDomain('), source.indexOf('  const view = Object.freeze({')) : '';
  return Function(...Object.keys(ports), variable ? `return (${body});`
    : `const pendingRunRegistrations=new Set();${helpers}return ({${body}}).${name};`)(...Object.values(ports));
}

function fixture() {
  const prepared = {}, request = {}, parent = {}, input = {}, contracts = {}, holder = {};
  const graph = {}, tokens = new WeakMap(), calls = [], state = {
    parent, prepared, holder, compilationFamily: 'content', context: undefined,
  };
  const options = {task: 0, step: 1, maxRows: 2, maxBytes: 128,
    resultDataPolicy: {kind: 'data_policy', cid: 'original-policy', wire: 'original-wire'}};
  let refused, constructing = false, after, borrowed = prepared;
  const moon = {
    clientProgramPreparationBorrowRead(h) { assert.equal(h, holder); return borrowed; },
    clientProgramPrepareRequestSerializationGraph(p, i, task, step, cid, wire, rows, bytes, roots, c) {
      assert.equal(this, moon);
      assert.deepEqual([p, i, task, step, cid, wire, rows, bytes, roots, c],
        [parent, input, 0, 1, 'original-policy', 'original-wire', 2, 128, true, contracts]);
      assert.equal(state.preparing, true); calls.push('owned-constructor');
      constructing = true;
      assert.throws(() => prepare(prepared, request, construct), {code: 'ForeignInstalledSourceProducer'});
      if (refused) throw refused;
      return graph;
    },
    clientProgramSerializationPlanGraphWire(g) {assert.equal(g, graph); return 'original-graph-wire';},
    clientProgramSerializationPlanGraph() {throw new Error('legacy Graph issuer must not run');},
  };
  state.context = {runtime: moon};
  const native = extract('../host-common/runtime-core.mjs', 'prepareSerializationGraph',
    {moon, serializationPlanTokens: tokens, compiledRunResult: result => result}, true);
  const construct = (p, i, c) => native(prepared, options, false, {parent: p, input: i, contracts: c});
  const producer = {receipt: input, preparation: state};
  const prepare = extract('./ordinary-source-managed.mjs', 'prepareContentGraph', {
    current() {
      if (constructing && state.contentGraph !== undefined) {
        assert.equal(tokens.get(state.contentGraph), graph);
        if (after) after();
      }
    },
    producerForRequest(r) {assert.equal(r, request); return producer;},
    originals: {installation: {sequenceContractOriginal: {moon, admission: contracts}}},
    fail: code => {throw Object.assign(new Error(code), {code});},
  });
  return {state, graph, tokens, calls, prepare: () => prepare(prepared, request, construct),
    refuse: error => {refused = error;}, after: callback => {after = callback;},
    changeBorrow() {borrowed = {};}, removePort() {delete moon.clientProgramPrepareRequestSerializationGraph;}};
}

test('actual Content Graph caller forwards same parent/input/contracts and retains original before post-current', () => {
  const f = fixture();
  const selected = f.prepare();
  assert.equal(f.tokens.get(selected), f.graph);
  assert.equal(f.state.contentGraph, selected);
  assert.equal(f.prepare(), selected);
  assert.deepEqual(f.calls, ['owned-constructor']);
  assert.equal(f.state.preparing, false);
});

test('Content Graph refuses missing owned port and retains same constructor or post-current failure for Request cleanup', () => {
  const missing = fixture(); missing.removePort();
  assert.throws(missing.prepare, /Request Content Graph constructor unavailable/);
  assert.equal(missing.state.preparationFailed, true);
  assert.equal(missing.state.contentGraph, undefined);
  assert.deepEqual(missing.calls, []);
  const primary = new Error('original capacity refusal'), refused = fixture(); refused.refuse(primary);
  assert.throws(refused.prepare, error => error === primary);
  assert.throws(refused.prepare, error => error === primary);
  assert.deepEqual(refused.calls, ['owned-constructor']);
  const changed = fixture(); changed.after(() => changed.changeBorrow());
  assert.throws(changed.prepare, {code: 'ForeignInstalledSourceProducer'});
  assert.equal(changed.tokens.get(changed.state.contentGraph), changed.graph);
  assert.equal(changed.state.preparing, false);
  const retained = changed.state.preparationFailure;
  assert.throws(changed.prepare, error => error === retained);
  assert.deepEqual(changed.calls, ['owned-constructor']);
});

test('acquired Content Graph forwards same Request without borrowing an external policy or legacy issuer', () => {
  const parent = {}, input = {}, contracts = {}, prepared = {}, graph = {}, tokens = new WeakMap();
  const options = {task: 1, step: 3, maxRows: 3, maxBytes: 4096,
    resultDataPolicy: new Proxy({}, {get() {throw new Error('acquired policy is an original checked Source');}})};
  let calls = 0;
  const moon = {
    clientProgramPrepareRequestAcquiredSerializationGraph(...args) {
      assert.equal(this, moon); calls++;
      assert.deepEqual(args, [parent, input, 1, 3, 3, 4096, false, contracts]);
      return graph;
    },
    clientProgramAcquiredSerializationPlanComponent() {throw new Error('legacy issuer');},
    clientProgramSerializationPlanGraphWire(value) {assert.equal(value, graph); return 'same-original-wire';},
  };
  const construct = extract('../host-common/runtime-core.mjs', 'prepareAcquiredSerializationGraph',
    {moon, serializationPlanTokens: tokens, compiledRunResult: value => value}, true);
  const selected = construct(prepared, options, true, {parent, input, contracts});
  assert.equal(tokens.get(selected), graph); assert.equal(calls, 1);
  delete moon.clientProgramPrepareRequestAcquiredSerializationGraph;
  assert.throws(() => construct(prepared, options, true, {parent, input, contracts}),
    /Request acquired Content Graph constructor unavailable/);
  assert.equal(calls, 1);
});
