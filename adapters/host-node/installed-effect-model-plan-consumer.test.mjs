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
    clientProgramInstalledEffectOperationControlsBegin() {return ok(plan);},
    clientProgramInstalledManagedRunRetire() {calls.push('retire-parent'); return ok();},
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
