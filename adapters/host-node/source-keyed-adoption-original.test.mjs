import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';

// Execute the actual installed method with its closed surrounding originals.
// Nominal Core ports below check forwarding/order only, never grant a Run.
const text = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
let method;
function visit(value) {
  if (!value || typeof value !== 'object') return;
  if (value.type === 'Property' && value.method && value.key.name === 'adoptEffectPreparation') {
    assert.equal(method, undefined); method = text.slice(value.start, value.end);
  }
  for (const child of Object.values(value)) {
    if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  }
}
visit(ast); assert.equal(typeof method, 'string');
function fixture({refuse = false} = {}) {
  const prepared = {}, request = {}, identity = {}, plan = {}, holder = {}, receipt = {},
    parent = {}, original = {}, value = {}, compiled = {}, definition = {}, compilation = {},
    acquisition = {}, graph = {}, runtime = {};
  const events = [], runs = new WeakMap(), liveRuns = new Set();
  const producer = {receipt, liveRuns: 0};
  const state = {prepared, holder, compilationKind: 'effectful', context: {runtime},
    parent, original, effectKeyedPlan: graph};
  producer.preparation = state;
  state.effectBorrowMethods = {
    clientProgramEffectPreparationInputRead: h => {assert.strictEqual(h, holder); return prepared;},
    clientProgramPrepareRequestEffectKeyedOriginal: () => {},
    clientProgramCompleteRequestEffectPreparation: (...args) => {
      assert.deepEqual(args, [parent, receipt, plan]); events.push('complete'); return {_0: undefined};
    },
    clientProgramAdoptRequestEffectPreparation: (...args) => {
      assert.deepEqual(args, [parent, identity]); events.push('adopt'); return {_0: value};
    },
  };
  const ports = {current() {}, producerForRequest: actual => {assert.strictEqual(actual, request); return producer;},
    fail: code => {throw Object.assign(new Error(code), {code});}, runs, liveRuns,
    pendingRunRegistrations: new Set(), checked: result => result._0,
    runtimeCore: actual => {
      assert.strictEqual(actual, runtime);
      return {publicationControl: {bindCheckedClientRequestEffectKeyedOriginal(...args) {
        assert.deepEqual(args, [parent, receipt, plan, compilation, compiled, definition,
          graph, acquisition, state.effectBorrowMethods.clientProgramPrepareRequestEffectKeyedOriginal]);
        events.push('bind'); if (refuse) throw undefined;
      }}};
    }};
  const invoke = new Function(...Object.keys(ports), 'return ({' + method + '}).adoptEffectPreparation;')(...Object.values(ports));
  const args = [prepared, request, identity, plan, {graph, acquisition, compiled, compilation, runDefinition: definition}];
  return {invoke: () => invoke(...args), events, value, state, runs, prepared, liveRuns};
}

test('keyed Effect adoption borrows its same runtime before binding and original completion', () => {
  const f = fixture(), run = f.invoke();
  assert.strictEqual(run.value, f.value);
  assert.strictEqual(f.runs.get(f.prepared), run);
  assert.deepEqual(f.events, ['bind', 'complete', 'adopt']);
});

test('keyed Effect adoption retains undefined original bind failure and cannot retry completion', () => {
  const f = fixture({refuse: true});
  let caught = false;
  try {f.invoke();} catch (cause) {caught = true; assert.strictEqual(cause, undefined);}
  assert(caught); assert.equal(f.state.preparationFailed, true);
  assert.throws(f.invoke, cause => cause === undefined);
  assert.deepEqual(f.events, ['bind']); assert.equal(f.liveRuns.size, 0);
});
