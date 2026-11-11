import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {prepareInstalledEffectManagedPlanRun, readInstalledEffectManagedPlanRun,
  finishInstalledEffectModelScope, installedEffectModelPreparation} from './installed-effect-managed-run.mjs';

// Actual JS owner; the nominal Common/Root/Model/Scope ports are explicit.
// This does not issue an actual admission, Model permission or cleanup ACK.
const ok = value => ({$tag: 1, _0: value});
const checked = value => {if (value.$tag !== 1) throw value._0; return value._0;};
const same = (actual, expected) => {assert.equal(actual.length, expected.length); actual.forEach((value, i) => assert.equal(value, expected[i]));};

test('actual Effect Model control unwraps only its original compiled holder and definition token', () => {
  const source = readFileSync(new URL('../host-common/runtime-core.mjs', import.meta.url), 'utf8');
  let method;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'prepareCheckedClientEffectModelDemand') method = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(parse(source, {ecmaVersion: 'latest', sourceType: 'module'})); assert(method);
  const prepared = {}, compiled = Object.freeze({kind: 'infer'}), native = {}, compilation = {},
    definition = {}, definitionToken = {}, occurrence = {}, graph = {}, demand = {};
  const originals = new WeakMap([[compiled, native]]); let calls = 0;
  const moon = {clientProgramInstalledEffectModelDemandPrepare(...actual) {
    same(actual, [prepared, native, compilation, definitionToken, occurrence, graph]); calls++; return ok(demand);
  }};
  const control = Function('moon', 'compiledRunTokens', 'token', 'checked',
    'return ({' + source.slice(method.start, method.end) + '});')(
    moon, originals, value => {assert.strictEqual(value, definition); return definitionToken;}, checked);
  const prepare = value => control.prepareCheckedClientEffectModelDemand(prepared, value,
    compilation, definition, occurrence, graph);
  assert.strictEqual(prepare(compiled), demand);
  assert.throws(() => prepare({...compiled}), /Foreign Client compiled Infer preparation/);
  assert.throws(() => prepare(native), /Foreign Client compiled Infer preparation/);
  assert.equal(calls, 1);
});

function fixture() {
  const prepared = {}, request = {}, plan = {}, parent = {}, scope = {}, demand = {}, admission = {}, original = {};
  const model = Object.freeze({kind: 'local-mock', compiled: {}, definition: {}, occurrence: {}, graph: {}});
  const facts = Object.freeze({prepared, identity: request, compilation: {}, allowed: {},
    definition: model.definition, modelCompiled: model.compiled, queryTimePreparation: undefined});
  const runs = new WeakMap(), liveRuns = new Set(), calls = [], registry = {};
  let pending = true, beginFailure, finishCallback;
  const runtime = {
    clientProgramInstalledEffectPlanMatchesModelDemand(actual, selected) {
      assert.equal(this, runtime); return actual === plan && selected === demand;
    },
    clientProgramInstalledEffectModelDemandPrepare(p, compiled, compilation, definition, occurrence, graph) {
      assert.equal(this, runtime); same([p, compiled, compilation, definition, occurrence, graph],
        [prepared, model.compiled, facts.compilation, model.definition, model.occurrence, model.graph]);
      calls.push('demand'); return ok(demand);
    },
    clientProgramNodeEffectModelManagedPlanPrepare(o, p) {
      assert.equal(this, runtime); assert.equal(o, original); assert.equal(p, plan);
      calls.push('admit-model'); return ok(admission);
    },
    clientProgramInstalledEffectModelManagedPlanBegin(a, p, r, selected) {
      assert.equal(this, runtime); same([a, p, r, selected], [admission, prepared, request, plan]);
      calls.push('begin-model'); if (beginFailure) return {$tag: 0, _0: beginFailure};
      return ok({_0: parent, _1: scope});
    },
    clientProgramInstalledEffectManagedRunCheck(p, value, r) {
      assert.equal(this, runtime); same([p, value, r], [parent, prepared, request]); return ok();
    },
    clientProgramInstalledEffectManagedOperationPlan(p, value, r) {assert.equal(p, parent); assert.equal(value, prepared); assert.equal(r, request); return ok(plan);},
    clientProgramInstalledEffectOperationControlConstructionBegin() {return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlConstructionComplete() {return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlsRetain() {return ok(plan);},
    clientProgramInstalledManagedRunRetire() {calls.push('retire-parent'); return ok();},
    clientProgramInstalledManagedRunQuiesce(value) {
      assert.equal(this, runtime); assert.strictEqual(value, parent); return ok();
    },
    clientProgramNodeEffectManagedPlanCleanup(a) {assert.equal(a, admission); calls.push('cleanup-admission'); return ok();},
    clientProgramFinishInferOriginalReadScope(s, compiled, definition, graph, complete) {
      assert.equal(this, runtime); same([s, compiled, definition, graph],
        [scope, model.compiled, model.definition, model.graph]);
      calls.push('finish-scope'); finishCallback?.(); return ok(complete && !pending);
    },
    clientProgramNodeEffectManagedPlanPrepare() {assert.fail('no ordinary-purpose admission');},
    clientProgramInstalledEffectManagedPlanBegin() {assert.fail('no ordinary-purpose begin');},
  };
  const manager = {
    adoptEffectModelPreparation(p, input, identity, selected, run) {
      assert.equal(this, manager); same([p, input, identity, selected], [prepared, options.requestInput, request, plan]);
      assert.equal(run, runs.get(p)); assert.equal(run.operationPlan, plan); assert.equal(run.modelDemand, demand);
      run.original = original; run.modelScope = scope;
      calls.push('adopt-request-model'); if (beginFailure) throw beginFailure;
      return {original, operationPlan: plan, value: parent};
    },
    prepareEffectModelPlanRun() {assert.fail('no separate manager admission');},
    prepareEffectPlanRun() {assert.fail('no ordinary-purpose Root');},
  };
  const selection = Object.freeze({prepareManagedPlan(f, inputs) {
    assert.equal(this, selection); assert.equal(f, facts); assert.equal(inputs.registry, registry);
    assert.equal(inputs.modelDemand, demand); calls.push('plan'); return plan;
  }});
  const options = {runs, liveRuns, runtime, manager, prepared, request, requestInput: {}, selection,
    facts, inputs: Object.freeze({registry}), model, sourceProfile: {}, checked, assertCurrent() {}};
  return {options, calls, scope, parent, model, admission, runs, prepared, runtime, plan, demand,
    settle() {pending = false;}, failBegin(cause) {beginFailure = cause;},
    onFinish(fn) {finishCallback = fn;}};
}

test('Effect Model binds its JS compiled holder through the existing control before one native provider Plan', () => {
  const f = fixture(), definition = {}, provider = {}, nativeRead = {};
  f.options.facts = Object.freeze({...f.options.facts, runDefinition: definition});
  const facts = f.options.facts;
  f.options.modelSelection = Object.freeze({localMock: true, occurrence: f.model.occurrence, graph: f.model.graph});
  let issuers = 0, reads = 0, settlements = 0;
  f.runtime.clientProgramComposedInferLocalProvider = occurrence => {
    assert.strictEqual(occurrence, f.model.occurrence); issuers++; return provider;
  };
  f.options.selection = Object.freeze({prepareManagedPlan(actual, input) {
    assert.strictEqual(actual, facts); assert.strictEqual(input.modelDemand, f.demand);
    assert.strictEqual(input.modelComponents[0], provider); return f.plan;
  }});
  f.runtime.clientProgramInstalledEffectModelDemandPrepare = () => assert.fail('a JS holder is not a native compiled Run');
  f.runtime.clientProgramInstalledEffectModelReadWindow = demand => {
    assert.strictEqual(demand, f.demand); return [23n, 29n];
  };
  const control = f.options.publicationControl = {
    prepareCheckedClientEffectModelDemand(p, compiled, compilation, actualDefinition, occurrence, graph) {
      assert.strictEqual(this, control); same([p, compiled, compilation, actualDefinition, occurrence, graph],
        [f.prepared, f.model.compiled, facts.compilation, definition, f.model.occurrence, f.model.graph]); return f.demand;
    },
    prepareCheckedClientInferOriginalRead(compiled, actualDefinition, graph, scope, budget) {
      same([compiled, actualDefinition, graph, scope], [f.model.compiled, definition, f.model.graph, f.scope]);
      assert.deepEqual([budget.readRetainedBytes, budget.readExecutionBytes,
        budget.modelRetainedBytes, budget.modelExecutionBytes], [23n, 29n, 23n, 29n]); reads++; return nativeRead;
    },
    stopCheckedClientInferOriginalReadPreparation(compiled, actualDefinition, graph, scope, read) {
      same([compiled, actualDefinition, graph, scope, read], [f.model.compiled, definition, f.model.graph, f.scope, nativeRead]);
    },
    settleCheckedClientInferOriginalReadPreparation(compiled, actualDefinition, graph, read, complete) {
      same([compiled, actualDefinition, graph, read, complete], [f.model.compiled, definition, f.model.graph, nativeRead, true]); settlements++;
    },
    finishCheckedClientInferOriginalReadScope(compiled, actualDefinition, graph, scope, complete) {
      same([compiled, actualDefinition, graph, scope, complete], [f.model.compiled, definition, f.model.graph, f.scope, true]); return true;
    },
  };
  prepareInstalledEffectManagedPlanRun(f.options);
  const run = readInstalledEffectManagedPlanRun(f.options);
  const view = installedEffectModelPreparation(run, () => ({}), () => {});
  view.retain(); assert.strictEqual(view.prepareRead().read, nativeRead);
  assert.throws(() => view.prepareRead(), {code: 'ForeignInstalledEffectModelScope'});
  assert.equal(view.retire(), true); assert.equal(view.retire(), true);
  finishInstalledEffectModelScope(run, true, checked);
  assert.equal(issuers, 1); assert.equal(reads, 1); assert.equal(settlements, 1);
});

test('Model Effect retains one demand Plan parent and original Scope before Source work', () => {
  const f = fixture();
  assert.equal(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  const run = readInstalledEffectManagedPlanRun(f.options);
  assert.equal(run.modelScope, f.scope); assert.equal(run.model, f.model);
  assert.equal(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  assert.deepEqual(f.calls, ['demand', 'plan', 'adopt-request-model']);
  assert.throws(() => prepareInstalledEffectManagedPlanRun({...f.options, model: {...f.model}}),
    {code: 'ForeignInstalledEffectManagedRun'});
  assert.throws(() => finishInstalledEffectModelScope(run, false, checked),
    {code: 'InstalledEffectModelScopeCleanupPending'});
  assert.throws(() => finishInstalledEffectModelScope(run, true, checked),
    {code: 'InstalledEffectModelScopeCleanupPending'});
  assert.equal(run.modelScopeFinished, undefined);
  f.settle(); finishInstalledEffectModelScope(run, true, checked);
  assert.equal(run.modelScopeFinished, true);
  const calls = f.calls.slice(); finishInstalledEffectModelScope(run, true, checked);
  assert.deepEqual(f.calls, calls);
});

test('Model Effect retains the original Content cleanup before selecting the same parent Plan', () => {
  const f = fixture(), preparation = {}, cleanup = {}, content = {preparation};
  let prepared = 0;
  f.options.prepareContent = retain => {prepared++; retain(cleanup); return content;};
  f.options.selection = Object.freeze({prepareManagedPlan(facts, inputs) {
    assert.strictEqual(facts, f.options.facts);
    assert.strictEqual(inputs.contentPreparation, preparation);
    assert.strictEqual(inputs.modelDemand, f.demand);
    const run = f.runs.get(f.prepared);
    assert.strictEqual(run.contentOriginal, content);
    assert.strictEqual(run.contentCleanup, cleanup);
    return f.plan;
  }});
  assert.strictEqual(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  assert.equal(prepared, 1);
  assert.strictEqual(f.runs.get(f.prepared).contentOriginal, content);
  assert.equal(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  assert.equal(prepared, 1);
});

test('partial Model adoption retains its same Request Scope and never reissues or falls back', () => {
  const f = fixture(), failure = new Error('original Model adoption failure');
  f.failBegin(failure);
  assert.throws(() => prepareInstalledEffectManagedPlanRun(f.options), error => error === failure);
  const run = f.runs.get(f.prepared);
  assert.equal(run.admission, undefined); assert.equal(run.modelScope, f.scope);
  assert.throws(() => prepareInstalledEffectManagedPlanRun(f.options), error => error === failure);
  assert.throws(() => finishInstalledEffectModelScope(run, true, checked),
    {code: 'InstalledEffectModelScopeCleanupPending'});
  f.settle(); finishInstalledEffectModelScope(run, true, checked);
  assert.deepEqual(f.calls, ['demand', 'plan', 'adopt-request-model', 'finish-scope', 'finish-scope']);
});

test('Model Scope cleanup joins reentry and refuses an original replaced by its callback', () => {
  const f = fixture(); prepareInstalledEffectManagedPlanRun(f.options);
  const run = readInstalledEffectManagedPlanRun(f.options); f.settle();
  f.onFinish(() => {
    assert.throws(() => finishInstalledEffectModelScope(run, true, checked),
      {code: 'InstalledEffectModelScopeCleanupPending'});
    run.modelScope = {};
  });
  assert.throws(() => finishInstalledEffectModelScope(run, true, checked), {code: 'ForeignInstalledEffectModelScope'});
  assert.equal(run.modelScopeFinished, undefined); assert.equal(run.modelScopeFinishing, false);
});

// The same Request/Scope/parent identities are explicit manager/Core ports.
// This tests the actual Node caller, not a Model provider, initial backing or
// actual native backing. There must be no new standalone admission.
test('Model Effect adopts its original Request and retains the same manager Run instead of another admission', () => {
  const f = fixture(), requestInput = {}, original = {};
  f.options.requestInput = requestInput;
  let retained;
  f.options.manager.adoptEffectModelPreparation = function(p, input, identity, selected, run) {
    assert.equal(this, f.options.manager);
    same([p, input, identity, selected],
      [f.prepared, requestInput, f.options.request, f.plan]);
    assert.equal(run, f.runs.get(p));
    assert.equal(run.requestInput, input); assert.equal(run.operationPlan, selected);
    run.original = original; run.modelScope = f.scope;
    retained = run; f.calls.push('adopt-request-model');
    return {original, operationPlan: selected, value: f.parent};
  };
  f.options.manager.prepareEffectModelPlanRun = () => assert.fail('Model must adopt the original Request');
  f.runtime.clientProgramNodeEffectModelManagedPlanPrepare =
    f.runtime.clientProgramInstalledEffectModelManagedPlanBegin = () => assert.fail('no second admission or parent');
  assert.equal(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  const run = readInstalledEffectManagedPlanRun(f.options);
  assert.equal(run.requestInput, requestInput); assert.equal(run.original, original);
  assert.equal(run, retained); assert.equal(run.modelScope, f.scope);
  assert.equal(run.preparationFunded, true); assert.equal(run.admission, undefined);
  assert.equal(f.calls.filter(value => value === 'adopt-request-model').length, 1);
  assert.equal(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  assert.equal(f.calls.filter(value => value === 'adopt-request-model').length, 1);
});


test('foreign Model demand and missing original Request refuse before Scope construction', () => {
  const f = fixture();
  f.runtime.clientProgramInstalledEffectPlanMatchesModelDemand = () => false;
  assert.throws(() => prepareInstalledEffectManagedPlanRun(f.options), {code: 'ForeignInstalledEffectModelSelection'});
  assert.equal(f.calls.includes('adopt-request-model'), false);
  const g = fixture(); g.options.requestInput = undefined;
  assert.throws(() => prepareInstalledEffectManagedPlanRun(g.options), {code: 'InstalledEffectRequestPreparationUnavailable'});
  assert.equal(g.calls.includes('adopt-request-model'), false);
});

// Execute the existing Host retirement body with explicit original Core return
// ports. A checked Unit or its one existing sever observation controls managed
// alias retirement; neither port is a physical cleanup acknowledgement.
function effectRetirementFixture() {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  let method;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'retireManagedComputeRun') method = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk);
      else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(parse(source, {ecmaVersion: 'latest', sourceType: 'module'})); assert(method);
  const prepared = {}, request = {}, value = {}, original = {}, plan = {};
  const record = {computeRuns: new WeakMap(), computeLiveRuns: new Set()};
  const counts = {retire: 0, observations: 0, returns: 0, finish: 0};
  const moon = {clientProgramInstalledPreparationPayloadSevered(v, r) {
    assert.equal(v, value); assert.equal(r, request); counts.observations++;
    return observe();
  }};
  let before = () => {}, observe = () => true;
  const run = {prepared, request, runtime: moon, value, original, operationPlan: plan,
    preparationKind: 'effect-plan', preparationFunded: true, closed: false,
    manager: {severPreparation(p, o) {
      assert.equal(p, prepared); assert.equal(o, original); counts.returns++;
    }},
    retire(v) {
      assert.equal(this, moon); assert.equal(v, value); counts.retire++; before();
      return ok(undefined);
    }};
  record.computeRuns.set(prepared, run); record.computeLiveRuns.add(run);
  const ports = {record, moon, checked, finishInstalledEffectModelScope,
    clientOperationError: code => Object.assign(new Error(code), {code}),
    managedPreparationRetirementContinuation(actual, bag) {
      assert.equal(actual, run); assert.equal(bag, record);
      return () => {counts.finish++;};
    }};
  const retire = Function(...Object.keys(ports),
    `return ({${source.slice(method.start, method.end)}}).retireManagedComputeRun;`)(...Object.values(ports));
  return {prepared, request, value, original, plan, record, run, counts,
    retire: () => retire(prepared), setBefore: callback => {before = callback;},
    setObserve: callback => {observe = callback;}};
}

test('Effect Host retirement fences same-record reentry before returning the original Request borrower', () => {
  const f = effectRetirementFixture();
  f.setBefore(() => {
    // The original Core retire may call current. That callback must not enter
    // the same retirement body or consume the Request borrower a second time.
    assert.throws(f.retire, {code: 'InstalledEffectRunCleanupPending'});
    assert.equal(f.counts.returns, 0); assert.equal(f.run.operationPlan, f.plan);
  });
  const finish = f.retire();
  assert.deepEqual(f.counts, {retire: 1, observations: 0, returns: 1, finish: 0});
  assert.equal(f.run.operationPlan, undefined); assert.equal(f.run.closed, true);
  finish(); assert.equal(f.counts.finish, 1);
});

test('Effect Host retirement retains originals on one failed sever observation or a changed original bag', () => {
  const f = effectRetirementFixture(), primary = new Error('original retire callback');
  f.setBefore(() => {throw primary;});
  f.setObserve(() => {
    assert.throws(f.retire, {code: 'InstalledEffectRunCleanupPending'});
    return false;
  });
  assert.throws(f.retire, error => error === primary);
  assert.deepEqual(f.counts, {retire: 1, observations: 1, returns: 0, finish: 0});
  assert.equal(f.run.operationPlan, f.plan); assert.equal(f.run.prepared, f.prepared);
  f.setObserve(() => {
    assert.throws(f.retire, {code: 'InstalledEffectRunCleanupPending'});
    return true;
  });
  f.retire(); assert.equal(f.counts.observations, 2); assert.equal(f.counts.returns, 1);
  const g = effectRetirementFixture();
  g.setBefore(() => {g.record.computeRuns.set(g.prepared, {});});
  assert.throws(g.retire, {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(g.counts.observations, 0); assert.equal(g.counts.returns, 0);
  assert.equal(g.run.operationPlan, g.plan); assert.equal(g.run.prepared, g.prepared);
});


test('Effect fallback observes only the same original parent after a throwing retirement callback', () => {
  const f = effectRetirementFixture(), primary = new Error('retire changed original');
  f.setBefore(() => {f.run.value = {}; f.run.request = {}; throw primary;});
  assert.throws(f.retire, {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(f.counts.observations, 1); assert.equal(f.counts.returns, 0);
  assert.equal(f.run.operationPlan, f.plan); assert.equal(f.run.prepared, f.prepared);
});


test('Effect control retirement keeps its original receiver and fences reentry before parent return', () => {
  const f = effectRetirementFixture(), originalControl = {};
  let calls = 0;
  f.run.controlConstruction = originalControl;
  f.run.retireControlConstruction = function() {
    assert.equal(this, originalControl); calls++;
    assert.throws(f.retire, {code: 'InstalledEffectRunCleanupPending'});
    return true;
  };
  f.retire(); assert.equal(calls, 1); assert.equal(f.counts.returns, 1);
  const pending = effectRetirementFixture();
  pending.run.controlConstruction = {};
  pending.run.retireControlConstruction = () => false;
  assert.throws(pending.retire, {code: 'InstalledEffectControlConstructionCleanupPending'});
  assert.equal(pending.counts.retire, 0); assert.equal(pending.counts.returns, 0);
  assert.equal(pending.run.operationPlan, pending.plan);
  const changed = effectRetirementFixture();
  changed.run.controlConstruction = {};
  changed.run.retireControlConstruction = () => {changed.run.request = {}; return true;};
  assert.throws(changed.retire, {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(changed.counts.retire, 0); assert.equal(changed.counts.returns, 0);
  assert.equal(changed.run.operationPlan, changed.plan);
});

test('physical Model Content Effect keeps its original Node layout and trusted Scope through retry', () => {
  const f = fixture(), definition = {}, provider = {}, read = {}, view = {}, layout = {}, selectedBounds = {};
  const physical = {nodeInstallation: layout, modelRetainedBytes: 37n, modelExecutionBytes: 41n};
  f.options.model = Object.freeze({...f.model, kind: 'installed-model'});
  f.options.facts = Object.freeze({...f.options.facts, runDefinition: definition});
  let issued = 0, bound = 0, finished = 0, reads = 0, complete = false;
  const sameScope = args => same(args, [f.scope, f.model.compiled, definition, f.model.graph]);
  f.options.modelSelection = Object.freeze({occurrence: f.model.occurrence, graph: f.model.graph,
    selectedBounds, originalReadInstallation: physical,
    bindTrustedRuntimeScope(...args) {sameScope(args); bound++; return view;},
    assertTrustedRuntimeScope(scope, actual, ...args) {
      assert.strictEqual(actual, view); sameScope([scope, ...args]);
    },
    finishTrustedRuntimeScope(scope, actual, ...args) {
      assert.strictEqual(actual, view); sameScope([scope, ...args]); finished++; return complete;
    },
  });
  f.runtime.clientProgramGeneratedInferLocalProvider = occurrence => {
    assert.strictEqual(occurrence, f.model.occurrence); issued++; return provider;
  };
  f.runtime.clientProgramComposedInferLocalProvider = () => assert.fail('generated Content keeps its own provider purpose');
  f.runtime.clientProgramInstalledEffectModelReadWindow = () => [23n, 29n];
  const preparation = {}, cleanup = {};
  f.options.prepareContent = retain => {retain(cleanup); return {preparation};};
  f.options.selection = Object.freeze({prepareManagedPlan(facts, inputs) {
    assert.strictEqual(facts, f.options.facts); assert.strictEqual(inputs.modelDemand, f.demand);
    assert.strictEqual(inputs.contentPreparation, preparation);
    assert.strictEqual(inputs.modelComponents[0], provider); return f.plan;
  }});
  f.options.publicationControl = {
    prepareCheckedClientNodeEffectModelDemand(...args) {
      same(args, [f.prepared, f.model.compiled, f.options.facts.compilation, definition,
        f.model.occurrence, f.model.graph, selectedBounds, physical]); return f.demand;
    },
    finishCheckedClientInferOriginalReadScope() {assert.fail('trusted Scope retires through its actual installation');},
    prepareCheckedClientInferNodeReadLayout(...args) {
      same(args, [f.model.compiled, definition, f.model.graph, f.scope, layout]); reads++; return read;
    },
    stopCheckedClientInferOriginalReadPreparation() {},
    settleCheckedClientInferOriginalReadPreparation() {},
  };
  prepareInstalledEffectManagedPlanRun(f.options);
  const run = readInstalledEffectManagedPlanRun(f.options);
  const original = installedEffectModelPreparation(run, () => ({}), () => {});
  original.assertRuntimeCurrent(); original.retain();
  const prepared = original.prepareRead();
  assert.strictEqual(prepared.read, read); assert.strictEqual(prepared.nodeInstallation, layout);
  assert.strictEqual(prepared.metadataInstallation, physical);
  assert.deepEqual([prepared.modelRetainedBytes, prepared.modelExecutionBytes], [37n, 41n]);
  assert.throws(() => original.prepareRead(), {code: 'ForeignInstalledEffectModelScope'});
  assert.throws(() => finishInstalledEffectModelScope(run, false, checked), {code: 'InstalledEffectModelScopeCleanupPending'});
  assert.equal(finished, 0);
  original.retire();
  assert.throws(() => finishInstalledEffectModelScope(run, true, checked), {code: 'InstalledEffectModelScopeCleanupPending'});
  complete = true; finishInstalledEffectModelScope(run, true, checked);
  finishInstalledEffectModelScope(run, true, checked);
  assert.deepEqual([issued, bound, reads, finished], [1, 1, 1, 2]);
});


test('Model Effect quiesces only original stopped control before Scope and keeps pending primary for retry', () => {
  const f = fixture(), pending = Object.assign(new Error('physical child pending'), {code: 'CleanupPending'});
  let controlStopped = false, childStopped = false, quiesces = 0, controlStops = 0;
  f.runtime.clientProgramInstalledManagedRunQuiesce = function(value) {
    assert.strictEqual(this, f.runtime); assert.strictEqual(value, f.parent);
    quiesces++; assert.equal(controlStopped, true);
    return childStopped ? ok() : {$tag: 0, _0: pending};
  };
  prepareInstalledEffectManagedPlanRun(f.options);
  const run = readInstalledEffectManagedPlanRun(f.options), originalControl = run.controlConstruction;
  // The constructor's actual pending result must precede Core quiescence.
  run.retireControlConstruction = function() {
    assert.strictEqual(this, originalControl); controlStops++;
    assert.throws(() => finishInstalledEffectModelScope(run, true, checked),
      {code: 'InstalledEffectModelScopeCleanupPending'});
    return controlStopped;
  };
  assert.throws(() => finishInstalledEffectModelScope(run, false, checked),
    {code: 'InstalledEffectModelScopeCleanupPending'});
  assert.equal(controlStops, 0); assert.equal(quiesces, 0);
  assert.throws(() => finishInstalledEffectModelScope(run, true, checked),
    {code: 'InstalledEffectControlConstructionCleanupPending'});
  assert.equal(quiesces, 0); assert.equal(run.modelScopeFinished, undefined);
  controlStopped = true;
  assert.throws(() => finishInstalledEffectModelScope(run, true, checked), error => error === pending);
  assert.equal(quiesces, 1); assert.equal(run.modelScopeFinished, undefined);
  childStopped = true; f.settle();
  finishInstalledEffectModelScope(run, true, checked);
  const calls = [controlStops, quiesces];
  finishInstalledEffectModelScope(run, true, checked);
  assert.deepEqual([controlStops, quiesces], calls);
  assert.equal(run.modelScopeFinished, true);
  assert.equal(f.calls.filter(value => value === 'retire-parent').length, 0);
});

test('Model Effect quiescence rejects changed original and preserves thrown undefined without finishing Scope', () => {
  const f = fixture();
  f.runtime.clientProgramInstalledManagedRunQuiesce = () => {throw undefined;};
  prepareInstalledEffectManagedPlanRun(f.options);
  const run = readInstalledEffectManagedPlanRun(f.options);
  let threw = false;
  try {finishInstalledEffectModelScope(run, true, checked);} catch (cause) {threw = true; assert.equal(cause, undefined);}
  assert.equal(threw, true); assert.equal(run.modelScopeFinished, undefined);
  assert.equal(f.calls.includes('finish-scope'), false);
  const changed = fixture();
  changed.runtime.clientProgramInstalledManagedRunQuiesce = () => {
    changed.runs.get(changed.prepared).request = {}; return ok();
  };
  prepareInstalledEffectManagedPlanRun(changed.options);
  assert.throws(() => finishInstalledEffectModelScope(changed.runs.get(changed.prepared), true, checked),
    {code: 'ForeignInstalledEffectModelScope'});
  assert.equal(changed.calls.includes('finish-scope'), false);
});


function coldEffectReadFixture({failure} = {}) {
  const f = fixture(), read = {}, savedScope = {};
  f.options.facts = Object.freeze({...f.options.facts, runDefinition: f.model.definition});
  f.options.selection = Object.freeze({prepareManagedPlan(facts, inputs) {
    assert.strictEqual(facts, f.options.facts); assert.strictEqual(inputs.modelDemand, f.demand); return f.plan;
  }});
  f.runtime.clientProgramInstalledEffectModelReadWindow = () => [23n, 29n];
  let reads = 0, current = true;
  f.options.publicationControl = {
    startCheckedClientOriginalRestoredComposedInferExecution() { assert.fail('selection does not start input'); },
    prepareCheckedClientInferOriginalRead(compiled, definition, graph, scope) {
      same([compiled, definition, graph, scope], [f.model.compiled, f.model.definition, f.model.graph, f.scope]);
      reads++; if (failure) throw failure; return read;
    },
  };
  prepareInstalledEffectManagedPlanRun(f.options);
  const run = readInstalledEffectManagedPlanRun(f.options);
  const view = installedEffectModelPreparation(run, () => ({}), () => {if (!current) throw new Error('OriginalCurrentLost');});
  view.retain();
  return {f, run, view, read, savedScope, reads: () => reads, revoke() { current = false; }};
}

test('Effect Model cold read shares the same original parent scope and one-shot read with fresh preparation', () => {
  const f = coldEffectReadFixture();
  assert.throws(() => f.view.restoreRead({}), {code: 'InstalledEffectModelRuntimeUnavailable'});
  assert.equal(f.reads(), 0);
  const view = f.view.restoreRead({savedScope: f.savedScope});
  assert.strictEqual(view.read, f.read); assert.strictEqual(view.scope, f.f.scope);
  assert.strictEqual(f.run.value, f.f.parent); assert.strictEqual(f.run.modelRead, f.read);
  assert.throws(() => f.view.prepareRead(), {code: 'ForeignInstalledEffectModelScope'});
  assert.throws(() => f.view.restoreRead({savedScope: f.savedScope}), {code: 'ForeignInstalledEffectModelScope'});
  assert.equal(f.reads(), 1);
});

test('Effect Model cold read retains exact failed issuance and refuses lost original current without a replacement', () => {
  const failure = new Error('OriginalReadCleanupPending'), f = coldEffectReadFixture({failure});
  for (let i = 0; i < 2; i++) assert.throws(() => f.view.restoreRead({savedScope: f.savedScope}), error => error === failure);
  assert.strictEqual(f.run.modelReadFailure, failure); assert.equal(f.reads(), 1);
  const other = coldEffectReadFixture(); other.revoke();
  assert.throws(() => other.view.restoreRead({savedScope: other.savedScope}), /OriginalCurrentLost/u);
  assert.equal(other.reads(), 0);
});

function pluralEffectModelFixture({physical = false} = {}) {
  const f = fixture(), definition = {}, compiled = f.model.compiled, finishedScopes = new Set();
  const models = Object.freeze([0, 1].map(() => Object.freeze({kind: physical ? 'installed-model' : 'local-mock', compiled,
    definition: f.model.definition, occurrence: {}, graph: {}})));
  const selections = Object.freeze(models.map(model => Object.freeze({localMock: !physical,
    occurrence: model.occurrence, graph: model.graph, ...(physical ? {originalReadInstallation: {}, selectedBounds: {},
      bindTrustedRuntimeScope() {return {};}, assertTrustedRuntimeScope() {},
      finishTrustedRuntimeScope(scope, view, compiled, definition, selectedGraph) {
        assert(!finishedScopes.has(scope), 'a completed trusted view is retired only once');
        const result = f.options.publicationControl.finishCheckedClientInferOriginalReadScope(compiled, definition, selectedGraph, scope, true);
        if (result) finishedScopes.add(scope); return result;
      }} : {})})));
  const graph = Object.freeze(models.map(model => model.graph)), scopes = [{}, {}], demands = [{}, {}], providers = [{}, {}];
  f.options.model = Object.freeze({compiled, definition: f.model.definition, graph, components: models});
  f.options.modelSelection = Object.freeze({graph, components: selections});
  f.options.facts = Object.freeze({...f.options.facts, runDefinition: definition});
  const calls = [], seen = new Set(); let pending = true, current = true;
  f.runtime.clientProgramComposedInferLocalProvider = occurrence => {
    const index = models.findIndex(model => model.occurrence === occurrence); assert(index >= 0); calls.push(['provider', index]); return providers[index];
  };
  f.options.publicationControl = {
    prepareCheckedClientEffectModelDemand(prepared, c, compilation, d, occurrence, selectedGraph) {
      same([prepared, c, compilation, d], [f.prepared, compiled, f.options.facts.compilation, definition]);
      const index = models.findIndex(model => model.occurrence === occurrence);
      assert(index >= 0); assert.strictEqual(selectedGraph, models[index].graph); calls.push(['demand', index]); return demands[index];
    },
    prepareCheckedClientInferOriginalRead(c, d, selectedGraph, scope) {
      const index = graph.indexOf(selectedGraph); same([c, d, scope], [compiled, definition, scopes[index]]);
      calls.push(['read', index]); return {index};
    },
    stopCheckedClientInferOriginalReadPreparation() {}, settleCheckedClientInferOriginalReadPreparation() {},
    finishCheckedClientInferOriginalReadScope(c, d, selectedGraph, scope, physicalComplete) {
      const index = graph.indexOf(selectedGraph); assert(index >= 0);
      same([c, d, scope], [compiled, definition, scopes[index]]); assert.equal(physicalComplete, true);
      calls.push(['finish', index]); seen.add(index); return !pending && seen.size === models.length;
    },
  };
  f.options.publicationControl.prepareCheckedClientNodeEffectModelDemand = f.options.publicationControl.prepareCheckedClientEffectModelDemand;
  f.runtime.clientProgramInstalledEffectModelsDemandPrepare = originals => {same(originals, demands); calls.push(['compose']); return ok(f.demand);};
  f.runtime.clientProgramInstalledEffectModelReadWindow = original => {assert(demands.includes(original)); return [23n, 29n];};
  f.options.manager.adoptEffectModelPreparation = (prepared, input, identity, plan, run) => {
    same([prepared, input, identity, plan], [f.prepared, f.options.requestInput, f.options.request, f.plan]);
    assert.strictEqual(run.modelScope, undefined); assert.strictEqual(run.modelScopes, undefined);
    run.original = {};
    run.modelScopes = Object.freeze(scopes);
    for (let index = 0; index < scopes.length; index++) run.modelMembers[index].modelScope = scopes[index];
    calls.push(['adopt']); return {original: run.original, operationPlan: plan, value: f.parent};
  };
  f.options.selection = Object.freeze({prepareManagedPlan(facts, inputs) {
    assert.strictEqual(facts, f.options.facts); assert.strictEqual(inputs.modelDemand, f.demand);
    same(inputs.modelComponents, providers); calls.push(['plan']); return f.plan;
  }});
  f.options.assertCurrent = () => {if (!current) throw new Error('OriginalCurrentLost');};
  return {f, calls, graph, scopes, models, settle() {pending = false;}, revoke() {current = false;}};
}

test('plural Effect retains every original provider and Scope before Plan use and finishes the complete pending group', () => {
  const {f, calls, scopes, models, settle} = pluralEffectModelFixture();
  assert.strictEqual(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  const run = readInstalledEffectManagedPlanRun(f.options);
  assert.equal(run.modelScope, undefined); same(run.modelScopes, scopes);
  assert.deepEqual(calls.slice(0, 6), [['demand', 0], ['provider', 0], ['demand', 1], ['provider', 1], ['compose'], ['plan']]);
  const view = installedEffectModelPreparation(run, () => ({}), f.options.assertCurrent);
  assert.equal(view.components.length, 2); view.retain();
  for (let index = 0; index < 2; index++) {
    assert.strictEqual(view.components[index].selection, f.options.modelSelection.components[index]);
    assert.strictEqual(view.components[index].scope, scopes[index]);
    assert.strictEqual(view.components[index].compiled, models[index].compiled);
    view.components[index].prepareRead();
  }
  assert.equal(view.retire(), true);
  assert.throws(() => finishInstalledEffectModelScope(run, true, checked), {code: 'InstalledEffectModelScopeCleanupPending'});
  assert.equal(run.modelScopeFinished, undefined);
  assert.deepEqual(calls.filter(call => call[0] === 'finish').slice(0, 2), [['finish', 0], ['finish', 1]]);
  settle(); finishInstalledEffectModelScope(run, true, checked);
  assert.equal(run.modelScopeFinished, true);
  assert.throws(() => view.components[0].prepareRead(), {code: 'ForeignInstalledEffectModelScope'});
});

test('plural Effect refuses foreign member Scope or lost current before a read and never substitutes its first member', () => {
  const one = pluralEffectModelFixture(); prepareInstalledEffectManagedPlanRun(one.f.options);
  const run = readInstalledEffectManagedPlanRun(one.f.options);
  const view = installedEffectModelPreparation(run, () => ({}), one.f.options.assertCurrent);
  view.retain(); run.modelMembers[1].modelScope = {};
  assert.throws(() => view.components[0].prepareRead(), {code: 'ForeignInstalledEffectModelScope'});
  assert.equal(one.calls.some(call => call[0] === 'read'), false);
  const two = pluralEffectModelFixture(); prepareInstalledEffectManagedPlanRun(two.f.options);
  const currentRun = readInstalledEffectManagedPlanRun(two.f.options);
  const currentView = installedEffectModelPreparation(currentRun, () => ({}), two.f.options.assertCurrent);
  currentView.retain(); two.revoke();
  assert.throws(() => installedEffectModelPreparation(currentRun, () => ({}), two.f.options.assertCurrent), /OriginalCurrentLost/u);
  assert.throws(() => currentView.components[1].prepareRead(), /OriginalCurrentLost/u);
  assert.equal(two.calls.some(call => call[0] === 'read'), false);
});

test('plural Effect keeps a failed second original read including thrown undefined without a replacement', () => {
  const {f, calls, graph} = pluralEffectModelFixture(); let attempts = 0;
  f.options.publicationControl.prepareCheckedClientInferOriginalRead = (compiled, definition, selectedGraph) => {
    assert.strictEqual(selectedGraph, graph[1]); attempts++; throw undefined;
  };
  prepareInstalledEffectManagedPlanRun(f.options);
  const run = readInstalledEffectManagedPlanRun(f.options);
  const view = installedEffectModelPreparation(run, () => ({}), f.options.assertCurrent); view.retain();
  for (let i = 0; i < 2; i++) {
    let failed = false;
    try {view.components[1].prepareRead();} catch (cause) {failed = true; assert.strictEqual(cause, undefined);}
    assert(failed);
  }
  assert(Object.hasOwn(run.modelMembers[1], 'modelReadFailure')); assert.equal(attempts, 1);
  assert.equal(calls.some(call => call[0] === 'read'), false);
});

test('plural restored Effect facade forwards only its same opaque output inventory and native compilation/Definition', () => {
  const source = readFileSync(new URL('../host-common/runtime-core.mjs', import.meta.url), 'utf8');
  let method;
  (function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'openCheckedClientInstalledRestoredModelsEffectHost') method = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  })(parse(source, {ecmaVersion: 'latest', sourceType: 'module'})); assert(method);
  const compiled = Object.freeze({kind: 'infer'}), native = {}, definition = {}, nativeDefinition = {}, parent = {}, bound = {};
  const outputs = [{}, {}], graphs = [{}, {}], sources = [{}], host = {};
  let calls = 0;
  const moon = {clientProgramInstalledEffectManagedRestoredModelsHostOpen(...actual) {
    assert.strictEqual(this, moon); same(actual, [parent, bound, sources, outputs, native, nativeDefinition, graphs]); calls++; return ok(host);
  }};
  const control = Function('moon', 'compiledRunTokens', 'token', 'checked',
    'return ({' + source.slice(method.start, method.end) + '});')(
    moon, new WeakMap([[compiled, native]]), value => {assert.strictEqual(value, definition); return nativeDefinition;}, checked);
  const open = value => control.openCheckedClientInstalledRestoredModelsEffectHost(value, definition,
    parent, bound, sources, outputs, graphs);
  assert.strictEqual(open(compiled), host);
  assert.throws(() => open({...compiled}), /Foreign Client compiled Infer preparation/u);
  assert.throws(() => open(native), /Foreign Client compiled Infer preparation/u);
  assert.equal(calls, 1);
});


test('plural physical Effect finishes each trusted Scope view exactly once while its sibling closes the same group', () => {
  const {f, calls, settle} = pluralEffectModelFixture({physical: true});
  prepareInstalledEffectManagedPlanRun(f.options);
  const run = readInstalledEffectManagedPlanRun(f.options);
  settle(); finishInstalledEffectModelScope(run, true, checked);
  assert.equal(run.modelScopeFinished, true);
  assert(run.modelMembers.every(member => member.modelScopeFinished === true));
  const count = calls.filter(call => call[0] === 'finish').length;
  finishInstalledEffectModelScope(run, true, checked);
  assert.equal(calls.filter(call => call[0] === 'finish').length, count);
});
