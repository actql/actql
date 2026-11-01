import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {types} from 'node:util';
import {cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';

// Execute the existing manager method with explicit Core original/phase ports.
// These cases do not supply physical Model/Content construction backing.
const source = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const start = source.indexOf('    async fundedPreparation(');
const end = source.indexOf('    publicationPreparation(prepared) {', start);
assert(start >= 0 && end > start);
const method = source.slice(start, end).trim().replace(/,$/u, '');
const fail = code => {throw Object.assign(new Error(code), {code});};

function fixture({infers = [], serializations = [], acquisitions = 0, refusal,
  returned = true, foreign = false, retirementComplete = true} = {}) {
  const parent = {}, input = {}, request = {}, prepared = {}, inventory = {}, selected = {};
  const snapshot = {input: {}, parameters: {}}, calls = [];
  let selectedLive = false, returnFailure = returned === true ? undefined : returned;
  const same = (owner, receipt) => {assert.equal(owner, parent); assert.equal(receipt, input);};
  const moon = {
    clientProgramPrepareRequestNativeComputation(owner, receipt) {same(owner, receipt); calls.push('check');},
    clientProgramFinishRequestComputation(owner, receipt) {same(owner, receipt); calls.push('compile'); return 'effect_free';},
    clientProgramBorrowRequestProgramPlanInput(owner, receipt) {same(owner, receipt); calls.push('inventory'); return inventory;},
    clientProgramPreparationBorrowRead(holder) {
      assert(holder === inventory || holder === selected);
      return holder === selected && foreign ? {} : prepared;
    },
    clientProgramAcquisitionCount(actual) {assert.equal(actual, prepared); return acquisitions;},
    clientProgramComposedInferOccurrences(actual) {assert.equal(actual, prepared); calls.push('infer'); return infers;},
    clientProgramSerializationOccurrences(actual) {assert.equal(actual, prepared); calls.push('serialization'); return serializations;},
    clientProgramBorrowRequestModelPlanInput(owner, receipt) {
      same(owner, receipt); calls.push('model'); if (refusal) throw refusal;
      selectedLive = true; return selected;
    },
    clientProgramBorrowRequestContentPlanInput(owner, receipt) {
      same(owner, receipt); calls.push('content'); if (refusal) throw refusal;
      selectedLive = true; return selected;
    },
    clientProgramPreparationBorrowReturn(holder) {
      assert.equal(holder, inventory); assert(selectedLive, 'Select and retain the domain before returning inventory');
      calls.push('return-inventory');
      if (returnFailure !== undefined) throw returnFailure;
      return retirementComplete;
    },
    clientProgramPrepareRequestProgramModuleBody() {calls.push('ordinary-module');},
    clientProgramRequiresQueryTime: () => false,
    clientProgramRequestParametersOriginal: () => undefined,
  };
  const state = {parent, snapshot, context: {runtime: moon}};
  const producer = {receipt: input, request, kind: 'program', body: snapshot, preparation: state};
  const originals = {installation: {sequenceContractOriginal: {moon, admission: {}}}};
  const read = Function('current', 'producerForRequest', 'fail', 'originals', 'checked',
    'checkedRequestProgramPreparation', 'requestPreparationAvailable', 'reportCapacityRefusal',
    `const closing=false,closed=false;return ({${method}});`)(() => {},
    actual => {assert.equal(actual, request); return producer;}, fail, originals, value => value,
    (_moon, value) => value, () => true, () => {});
  return {state, calls, inventory, selected, prepared, moon, parent, input, request,
    read: () => read.fundedPreparation(request),
    compile: graph => read.prepareModelCompilation(prepared, request, graph),
    clearReturnFailure() {returnFailure = undefined;}};
}

test('original INFER and Content inventory select their own constructor borrow before ordinary ModuleBody', async () => {
  for (const family of ['model', 'content']) {
    const f = fixture(family === 'model' ? {infers: [{}]} : {serializations: [{}], acquisitions: 1});
    for (let index = 0; index < 2; index++) {
      const result = await f.read(); assert.equal(result.prepared, f.prepared);
    }
    assert.deepEqual(f.calls, ['check', 'compile', 'inventory', 'infer', 'serialization', family, 'return-inventory']);
    assert.equal(f.state.holder, f.selected);
    assert.equal(f.state.inventoryHolder, undefined);
    assert.equal(f.state.compilationFamily, family);
  }
});

test('domain selection refuses once and a consumed inventory return keeps its original parent failure', async () => {
  const refusal = new Error('original-domain-refusal');
  const f = fixture({infers: [{}], refusal});
  await assert.rejects(f.read(), error => error === refusal);
  await assert.rejects(f.read(), error => error === refusal);
  assert.equal(f.state.holder, f.inventory);
  assert.equal(f.calls.filter(value => value === 'model').length, 1);
  const returnFailure = new Error('original-inventory-return');
  const g = fixture({serializations: [{}], acquisitions: 1, returned: returnFailure});
  await assert.rejects(g.read(), error => error === returnFailure);
  assert.equal(g.state.holder, g.selected);
  assert.equal(g.state.inventoryHolder, undefined);
  g.clearReturnFailure();
  await assert.rejects(g.read(), error => error === returnFailure);
  assert.equal(g.calls.filter(value => value === 'content').length, 1);
});

test('mixed inventories and foreign domain originals refuse before ordinary or domain construction', async () => {
  const mixed = fixture({infers: [{}], serializations: [{}]});
  await assert.rejects(mixed.read(), {code: 'NodeManagedRunPlanUnavailable'});
  assert.equal(mixed.state.holder, mixed.inventory);
  assert(!mixed.calls.includes('model')); assert(!mixed.calls.includes('content'));
  assert(!mixed.calls.includes('ordinary-module'));
  const foreign = fixture({infers: [{}], foreign: true});
  await assert.rejects(foreign.read(), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(foreign.state.holder, foreign.selected);
  assert.equal(foreign.state.inventoryHolder, foreign.inventory);
  assert(!foreign.calls.includes('return-inventory'));
});

test('original Request cleanup consumes both borrows once and retries only the retained parent settlement', () => {
  const parent = {}, prepared = {}, inventory = {}, selected = {}, primary = new Error('original-settlement');
  const calls = [], consumed = new Set();
  let retired = 0;
  const state = {parent, holder: selected, inventoryHolder: inventory, prepared,
    compilationKind: 'effect_free', compilationFamily: 'model'};
  const ok = value => ({$tag: 1, _0: value});
  const moon = {
    clientProgramAbortRequestPreparation(owner) {
      assert.equal(owner, parent); calls.push('abort');
      return consumed.size === 2 ? ok() : {$tag: 0, _0: 'retained-original-borrows'};
    },
    clientProgramPreparationBorrowRetirementStarted(holder) {
      assert(holder === inventory || holder === selected); return true;
    },
    clientProgramPreparationBorrowReturn(holder) {
      assert(!consumed.has(holder), 'The original Core consumes each borrower before settlement');
      consumed.add(holder); calls.push(holder === inventory ? 'inventory' : 'selected');
      return holder === inventory ? ok(false) : {$tag: 0, _0: primary};
    },
  };
  state.context = {runtime: moon};
  const retire = actual => {assert.equal(actual, prepared); retired++;};
  assert.throws(() => cleanupRequestInput(state, retire), error => error.cause === primary || error === primary);
  assert.equal(state.inventoryHolder, undefined); assert.equal(state.holder, undefined);
  assert.equal(state.parent, parent); assert.equal(retired, 1);
  cleanupRequestInput(state, retire);
  assert.equal(state.parent, undefined); assert.equal(retired, 1);
  assert.deepEqual(calls, ['abort', 'inventory', 'selected', 'abort']);
});

test('a false original inventory return consumes that borrow while the selected Model owner remains live', async () => {
  const f = fixture({infers: [{}], retirementComplete: false});
  const result = await f.read(); assert.equal(result.prepared, f.prepared);
  assert.equal(f.state.inventoryHolder, undefined); assert.equal(f.state.holder, f.selected);
  assert.equal(f.state.preparationFailed, undefined);
  assert.deepEqual(f.calls, ['check', 'compile', 'inventory', 'infer', 'serialization', 'model', 'return-inventory']);
});


test('Request Model compilation retains one original artifact and graph without a second compile', async () => {
  const f = fixture({infers: [{}]}), graph = {}, artifact = {}, admission = [];
  let compiles = 0;
  f.moon.clientProgramRequestProgramModuleIssueCode = () => undefined;
  f.moon.clientProgramPrepareRequestModelCompilation = function(parent, input, original, contracts) {
    assert.equal(this, f.moon); assert.equal(parent, f.parent); assert.equal(input, f.input);
    assert.equal(original, graph); admission.push(contracts); compiles++; return artifact;
  };
  await f.read();
  assert.equal(f.compile(graph), artifact); assert.equal(f.compile(graph), artifact);
  assert.throws(() => f.compile({}), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(compiles, 1); assert.equal(admission.length, 1);
  const g = fixture({infers: [{}]}), failure = new Error('original-model-compiler');
  let attempts = 0;
  g.moon.clientProgramRequestProgramModuleIssueCode = () => undefined;
  g.moon.clientProgramPrepareRequestModelCompilation = () => {attempts++; throw failure;};
  await g.read();
  assert.throws(() => g.compile(graph), error => error === failure);
  assert.throws(() => g.compile(graph), error => error === failure);
  assert.equal(attempts, 1);
});


function adoptionFixture(family, failure) {
  const parent = {}, input = {}, request = {}, identity = {}, prepared = {}, holder = {};
  const plan = {}, scope = {}, value = {}, graph = {}, artifact = {}, original = {}, calls = [];
  const model = {graph, scope: undefined};
  const originals = {}, requirements = Object.freeze({attempts: 2});
  const state = {parent, prepared, holder, context: {}, original, compilationFamily: family,
    modelCompilation: artifact, modelGraph: graph};
  const producer = {request, receipt: input, preparation: state, liveRuns: 0};
  const runs = new WeakMap(), liveRuns = new Set();
  const moon = {
    clientProgramPreparationBorrowRead(actual) {assert.equal(actual, holder); return prepared;},
    clientProgramPrepareRequestModelReadScope(p, i, selected) {
      assert.equal(this, moon); assert.equal(p, parent); assert.equal(i, input); assert.equal(selected, plan);
      calls.push('scope'); return scope;
    },
    clientProgramCompleteRequestModelPreparation(p, i, selected) {
      assert.equal(this, moon); assert.equal(p, parent); assert.equal(i, input); assert.equal(selected, plan);
      assert.equal(model.scope, scope, 'The existing caller must retain Scope before completion');
      calls.push('complete'); if (failure) throw failure;
    },
    clientProgramAdoptRequestModelPreparation(p, id, originalScope) {
      assert.equal(this, moon); assert.equal(p, parent); assert.equal(id, identity); assert.equal(originalScope, scope);
      calls.push('adopt'); return value;
    },
    clientProgramCompleteRequestContentPreparation(p, i, id, selected) {
      assert.equal(this, moon); assert.equal(p, parent); assert.equal(i, input);
      assert.equal(id, identity); assert.equal(selected, plan); calls.push('complete');
      if (failure) throw failure;
    },
    clientProgramAdoptRequestContentPreparation(p, id) {
      assert.equal(this, moon); assert.equal(p, parent); assert.equal(id, identity); calls.push('adopt'); return value;
    },
  };
  state.context.runtime = moon;
  const name = family === 'model' ? 'adoptModelPreparation' : 'adoptContentPreparation';
  const a = source.indexOf('    '+name+'('), b = source.indexOf('    adopt'+(family === 'model' ? 'Content' : 'Effect')+'Preparation(', a);
  assert(a >= 0 && b > a);
  const object = Function('current', 'callbacks', 'originals', 'producerForRequest', 'runs', 'liveRuns', 'fail', 'types', 'checked',
    `return ({${source.slice(a,b).trim().replace(/,$/u,'')}});`)(() => {},
    {request(actualOriginals, actual) {assert.equal(actualOriginals, originals); assert.equal(actual, prepared); return request;},
      contentRequirements(actualOriginals, actual, selected) {
        assert.equal(actualOriginals, originals); assert.equal(actual, prepared); assert.equal(selected, plan);
        calls.push('requirements'); return requirements;
      }}, originals,
    actual => {assert.equal(actual, request); return producer;}, runs, liveRuns, fail, types, result => result);
  return {state, model, plan, scope, value, calls, original, requirements, producer, runs, liveRuns, prepared,
    adoptModel: actual => object[name](prepared, identity, plan, actual),
    adopt: () => family === 'model' ? object[name](prepared, identity, plan, model) : object[name](prepared, identity, plan)};
}

test('Model handoff retains the original Scope before completion and adopts the same parent Request', () => {
  const f = adoptionFixture('model'), run = f.adopt();
  assert.equal(run.original, f.original); assert.equal(run.value, f.value); assert.equal(run.model, f.model);
  assert.equal(f.model.scope, f.scope); assert.equal(f.runs.get(f.prepared), run);
  assert(f.liveRuns.has(run)); assert.equal(f.producer.liveRuns, 1);
  assert.deepEqual(f.calls, ['scope', 'complete', 'adopt']);
  assert.equal(f.state.modelCompilation, undefined); assert.equal(f.state.modelPlan, undefined);
  const primary = new Error('original-model-completion'), g = adoptionFixture('model', primary);
  assert.throws(g.adopt, error => error === primary);
  assert.equal(g.model.scope, g.scope); assert.equal(g.state.modelPlan, g.plan);
  assert.throws(g.adopt, error => error === primary);
  assert.deepEqual(g.calls, ['scope', 'complete']); assert.equal(g.producer.liveRuns, 0);
});

test('keyed Content completion and adoption preserve the original parent and selected Plan on failure', () => {
  const f = adoptionFixture('content'), run = f.adopt();
  assert.equal(run.original, f.original); assert.equal(run.value, f.value); assert.equal(run.content, f.plan);
  assert.equal(run.required, f.requirements);
  assert.equal(f.runs.get(f.prepared), run); assert.equal(f.producer.liveRuns, 1);
  assert.deepEqual(f.calls, ['requirements', 'complete', 'adopt']); assert.equal(f.state.contentPlan, undefined);
  const primary = new Error('original-content-completion'), g = adoptionFixture('content', primary);
  assert.throws(g.adopt, error => error === primary);
  assert.equal(g.state.contentPlan, g.plan); assert.throws(g.adopt, error => error === primary);
  assert.deepEqual(g.calls, ['requirements', 'complete']); assert.equal(g.producer.liveRuns, 0);
});

test('Model Scope cannot be acquired for a copied graph or accessor-owned cleanup carrier', () => {
  const f = adoptionFixture('model');
  const proxy = new Proxy(f.model, {get() {assert.fail('Proxy carrier must not be observed');}});
  assert.throws(() => f.adoptModel(proxy), {code: 'ForeignInstalledSourceProducer'});
  assert.throws(() => f.adoptModel({...f.model, graph: {}}), {code: 'ForeignInstalledSourceProducer'});
  const accessor = {graph: f.model.graph, get scope() {assert.fail('Scope accessor must not be observed');}};
  assert.throws(() => f.adoptModel(accessor), {code: 'ForeignInstalledSourceProducer'});
  assert.deepEqual(f.calls, []); assert.equal(f.producer.liveRuns, 0);
});
