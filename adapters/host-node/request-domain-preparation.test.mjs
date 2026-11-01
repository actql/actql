import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {types} from 'node:util';
import {parse} from 'acorn';
import {cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';

// Execute the existing manager method with explicit Core original/phase ports.
// These cases do not supply physical Model/Content construction backing.
const source = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const managerHelpers = source.slice(source.indexOf('  function constructRequestDomain('), source.indexOf('  const view = Object.freeze({'));
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
    'checkedRequestProgramPreparation', 'requestPreparationAvailable',
    `const closing=false,closed=false;const pendingRunRegistrations=new Set();${managerHelpers}return ({${method}});`)(() => {},
    actual => {assert.equal(actual, request); return producer;}, fail, originals, value => value,
    (_moon, value) => value, () => true);
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

test('mixed inventory retains the Model constructor borrow and a foreign original still refuses before domain construction', async () => {
  const mixed = fixture({infers: [{}], serializations: [{}]});
  assert.equal((await mixed.read()).prepared, mixed.prepared);
  assert.equal(mixed.state.holder, mixed.selected); assert.equal(mixed.state.inventoryHolder, undefined);
  assert.equal(mixed.state.compilationFamily, 'model');
  assert.deepEqual(mixed.calls, ['check', 'compile', 'inventory', 'infer', 'serialization', 'model', 'return-inventory']);
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
    `const pendingRunRegistrations=new Set();${managerHelpers}return ({${source.slice(a,b).trim().replace(/,$/u,'')}});`)(() => {},
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


// Extract the same private constructors and bookkeeping, with explicit native
// and current ports. No Common image or physical admission is supplied here.
function requestManagerMethods(names, ports) {
  const selected = [], helpers = [];
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.method && names.includes(node.key?.name)) selected.push(source.slice(node.start, node.end));
    if (node.type === 'FunctionDeclaration' && ['constructRequestDomain', 'registerRequestRun'].includes(node.id?.name)) {
      helpers.push(source.slice(node.start, node.end));
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(selected.length, names.length);
  return Function(...Object.keys(ports), `const pendingRunRegistrations = new Set();
    ${helpers.join('\n')} return ({${selected.join(',\n')}});`)(...Object.values(ports));
}

function registrationFixture(family, {full = false} = {}) {
  const prepared = {}, request = {}, identity = {}, parent = {}, input = {}, holder = {}, value = {}, original = {};
  const plan = {}, graph = {}, model = {graph, scope: undefined}, scope = {}, calls = [];
  const state = {prepared, parent, holder, original, compilationKind: 'effect_free',
    compilationFamily: family === 'capture' ? 'pure' : family, acquisitionCount: family === 'capture' ? 1 : 0,
    modelGraph: graph, modelCompilation: {}, context: undefined};
  const producer = {request, receipt: input, preparation: state, liveRuns: 0};
  const runs = new WeakMap(), liveRuns = new Set(Array.from({length: full ? 4096 : 0}, () => ({})));
  let onAdopt, after;
  const nativeAdopt = () => {calls.push('adopt'); if (onAdopt) onAdopt(); return value;};
  const moon = {clientProgramPreparationBorrowRead: h => {assert.equal(h, holder); return prepared;},
    clientProgramRequestProgramModuleIssueCode() {}, clientProgramPrepareRequestCaptureModuleBody() {calls.push('module');},
    clientProgramAdoptRequestCapturePreparation: nativeAdopt, clientProgramAdoptRequestProgramPreparation: nativeAdopt,
    clientProgramPrepareRequestModelReadScope() {calls.push('scope'); return scope;},
    clientProgramCompleteRequestModelPreparation() {calls.push('complete');},
    clientProgramAdoptRequestModelPreparation: nativeAdopt,
    clientProgramCompleteRequestContentPreparation() {calls.push('complete');},
    clientProgramAdoptRequestContentPreparation: nativeAdopt};
  state.context = {runtime: moon};
  const ports = {current: () => {if (after) after();}, fail, types, runs, liveRuns,
    originals: {installation: {sequenceContractOriginal: {moon, admission: {}}}},
    callbacks: {request: () => request, contentRequirements: () => ({attempts: 1})},
    producerForRequest: r => r === request ? producer : undefined,
    checked: v => v, checkedRequestProgramPreparation: (_moon, v) => v,
    originalTimedInvocation: () => undefined};
  const methods = requestManagerMethods(['adoptPreparation', 'adoptCapturePreparation', 'adoptModelPreparation', 'adoptContentPreparation'], ports);
  const invoke = () => family === 'pure' ? methods.adoptPreparation(prepared, request, identity)
    : family === 'capture' ? methods.adoptCapturePreparation(prepared, request, identity, () => {calls.push('plan'); return plan;})
    : family === 'model' ? methods.adoptModelPreparation(prepared, identity, plan, model)
    : methods.adoptContentPreparation(prepared, identity, plan);
  return {invoke, calls, state, producer, prepared, runs, liveRuns, value,
    onAdopt: f => {onAdopt = f;}, after: f => {after = f;}};
}

test('Request registration refuses every full or duplicate original before native adoption', () => {
  for (const family of ['pure', 'capture', 'model', 'content']) {
    const full = registrationFixture(family, {full: true});
    assert.throws(full.invoke, {code: 'ForeignInstalledSourceProducer'});
    assert(!full.calls.includes('adopt')); assert.equal(full.producer.liveRuns, 0);
    const duplicate = registrationFixture(family);
    duplicate.runs.set(duplicate.prepared, {});
    assert.throws(duplicate.invoke, {code: 'ForeignInstalledSourceProducer'});
    assert(!duplicate.calls.includes('adopt')); assert.equal(duplicate.producer.liveRuns, 0);
  }
});

test('Request registration owns the original returned Run before the next fallible current', () => {
  for (const family of ['pure', 'capture', 'model', 'content']) {
    const f = registrationFixture(family);
    f.onAdopt(() => assert.throws(f.invoke, {code: 'ForeignInstalledSourceProducer'}));
    const run = f.invoke();
    assert.equal(run.value, f.value); assert.equal(f.runs.get(f.prepared), run);
    assert(f.liveRuns.has(run)); assert.equal(f.producer.liveRuns, 1);
    assert.equal(f.calls.filter(v => v === 'adopt').length, 1);
    const primary = new Error('original current after adoption');
    f.after(() => {throw primary;}); assert.throws(f.invoke, error => error === primary);
    assert.equal(f.runs.get(f.prepared), run); assert(f.liveRuns.has(run));
  }
});

test('Request Model retains its constructor Plan before adoption current and preserves null or undefined failures', () => {
  for (const primary of [null, undefined]) {
    const prepared = {}, request = {}, parent = {}, input = {}, model = {graph: {}}, plan = {}, compilation = {};
    const state = {prepared, parent, compilationFamily: 'model'}, producer = {preparation: state, receipt: input};
    let object, constructions = 0;
    const view = {prepareModelCompilation: () => compilation,
      adoptModelPreparation() {assert.equal(state.modelPlan, plan); throw primary;}};
    object = requestManagerMethods(['prepareModelRun'], {current() {}, fail, view,
      producerForRequest: () => producer});
    const invoke = () => object.prepareModelRun(prepared, request, {}, model, (p, i, c) => {
      assert.deepEqual([p, i, c], [parent, input, compilation]); assert.equal(state.preparing, true);
      assert.throws(invoke, {code: 'ForeignInstalledSourceProducer'}); constructions++; return plan;
    });
    const capture = f => {let caught = false; try {f();} catch (cause) {caught = true; assert.equal(cause, primary);} assert(caught);};
    capture(invoke); assert.equal(state.modelPlan, plan); assert.equal(state.preparing, false);
    // The constructor body itself is covered separately; this continuation
    // proves that post-constructor adoption failure cannot lose its same Plan.
    assert.equal(constructions, 1);
  }
});

test('Request registration reserves the final live slot across another Request callback and releases only failed reservations', () => {
  for (const nativeFailure of [false, true]) {
    const prepared = [{}, {}], requests = [{}, {}], states = prepared.map(p => ({prepared: p, parent: {}, holder: {},
      compilationFamily: 'pure', acquisitionCount: 0, context: undefined}));
    const producers = states.map((state, i) => ({preparation: state, request: requests[i], liveRuns: 0}));
    const runs = new WeakMap(), liveRuns = new Set(Array.from({length: 4095}, () => ({})));
    let object, adopts = 0;
    const invoke = i => object.adoptPreparation(prepared[i], requests[i], {});
    const moon = {clientProgramAdoptRequestProgramPreparation(parent) {
      adopts++;
      if (parent === states[0].parent) {
        assert.throws(() => invoke(1), {code: 'ForeignInstalledSourceProducer'});
        if (nativeFailure) throw null;
      }
      return {};
    }};
    states.forEach(state => {state.context = {runtime: moon};});
    object = requestManagerMethods(['adoptPreparation'], {current() {}, fail, runs, liveRuns,
      producerForRequest: request => producers[requests.indexOf(request)], originals: {installation: {}}, checked: v => v});
    if (nativeFailure) {
      let caught = false; try {invoke(0);} catch (cause) {caught = true; assert.equal(cause, null);} assert(caught);
      assert.equal(runs.get(prepared[0]), undefined); assert.equal(producers[0].liveRuns, 0);
    } else {
      const run = invoke(0); assert.equal(runs.get(prepared[0]), run); assert.equal(liveRuns.size, 4096);
      // Simulate the already checked bookkeeping release, not a physical ACK.
      liveRuns.delete(run); runs.delete(prepared[0]); producers[0].liveRuns--;
    }
    assert.equal(invoke(1), runs.get(prepared[1])); assert.equal(liveRuns.size, 4096); assert.equal(adopts, 2);
  }
});

test('Request synchronous constructor helper latches an original null or undefined failure and clears busy once', () => {
  for (const primary of [null, undefined]) {
    const prepared = {}, request = {}, state = {prepared, parent: {}, compilationFamily: 'model'};
    const producer = {preparation: state, receipt: {}}, model = {graph: {}};
    let compiles = 0, constructs = 0;
    const object = requestManagerMethods(['prepareModelRun'], {current() {}, fail, producerForRequest: () => producer,
      view: {prepareModelCompilation() {compiles++; return {};}, adoptModelPreparation() {assert.fail('No adoption after constructor refusal');}}});
    const invoke = () => object.prepareModelRun(prepared, request, {}, model, () => {
      constructs++; assert.equal(state.preparing, true); throw primary;
    });
    for (let i = 0; i < 2; i++) {
      let caught = false; try {invoke();} catch (cause) {caught = true; assert.equal(cause, primary);} assert(caught);
      assert.equal(state.preparing, false); assert.equal(state.preparationFailed, true); assert.equal(state.preparationFailure, primary);
    }
    assert.equal(compiles, 1); assert.equal(constructs, 1);
  }
});
