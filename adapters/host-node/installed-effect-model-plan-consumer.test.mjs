import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledEffectManagedPlanRun, readInstalledEffectManagedPlanRun,
  finishInstalledEffectModelScope} from './installed-effect-managed-run.mjs';

// Actual JS owner; the nominal Common/Root/Model/Scope ports are explicit.
// This does not issue an actual admission, Model permission or cleanup ACK.
const ok = value => ({$tag: 1, _0: value});
const checked = value => {if (value.$tag !== 1) throw value._0; return value._0;};
const same = (actual, expected) => {assert.equal(actual.length, expected.length); actual.forEach((value, i) => assert.equal(value, expected[i]));};
function fixture() {
  const prepared = {}, request = {}, plan = {}, parent = {}, scope = {}, demand = {}, admission = {}, original = {};
  const model = Object.freeze({kind: 'local-mock', compiled: {}, definition: {}, occurrence: {}, graph: {}});
  const facts = {prepared, identity: request, compilation: {}, allowed: {},
    definition: model.definition, modelCompiled: model.compiled};
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
    clientProgramInstalledEffectOperationControlsBegin() {return ok();},
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
  return {options, calls, scope, parent, model, admission, runs, prepared, runtime, plan,
    settle() {pending = false;}, failBegin(cause) {beginFailure = cause;},
    onFinish(fn) {finishCallback = fn;}};
}

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
