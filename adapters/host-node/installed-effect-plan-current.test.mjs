import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledEffectManagedPlanRun as prepare, readInstalledEffectManagedPlanRun as read}
  from './installed-effect-managed-run.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';

// Actual public Node owner with explicit nominal Core/Model/Scope ports.
// Counts here are getter invocations, not actual Core origin.current calls,
// Root funding, provider work, physical cleanup or ordinary acceptance.
const ok = value => ({$tag: 1, _0: value});
const checked = result => {if (result.$tag !== 1) throw result._0; return result._0;};
function fixture(withModel = false) {
  const prepared = {}, request = {}, plan = {}, parent = {}, original = {}, admission = {}, scope = {}, demand = {};
  const model = withModel ? Object.freeze({kind: 'local-mock', compiled: {}, definition: {}, occurrence: {}, graph: {}}) : undefined;
  const facts = {prepared, identity: request, compilation: {}, allowed: {},
    definition: model?.definition ?? {}, modelCompiled: model?.compiled};
  const runs = new WeakMap(), liveRuns = new Set(), inputs = Object.freeze({}), sourceProfile = {};
  const controls = {getters: 0, checks: 0, quotes: 0, selected: 0, demands: 0,
    onRead: undefined, onCurrent: undefined, returnedPlan: plan, failBegin: false};
  const runtime = {
    clientProgramInstalledManagedRunRetire() {return ok();},
    clientProgramNodeEffectManagedPlanCleanup() {return ok();},
    clientProgramInstalledEffectManagedOperationPlan(value, p, r) {
      assert.equal(this, runtime); assert.equal(arguments.length, 3);
      assert.equal(value, parent); assert.equal(p, prepared); assert.equal(r, request);
      controls.getters++; controls.onRead?.(runs.get(prepared)); return ok(controls.returnedPlan);
    },
    clientProgramNodeEffectManagedPlanPrepare(value, selected) {
      assert.equal(value, original); assert.equal(selected, plan); assert(!withModel); return ok(admission);
    },
    clientProgramInstalledEffectManagedPlanBegin(value, p, r, selected) {
      assert.equal(value, admission); assert.equal(p, prepared); assert.equal(r, request); assert.equal(selected, plan);
      assert(!withModel); return controls.failBegin ? {$tag: 0, _0: undefined} : ok(parent);
    },
    clientProgramInstalledEffectModelDemandPrepare(p, compiled, compilation, definition, occurrence, graph) {
      assert(withModel); assert.equal(p, prepared); assert.equal(compiled, model.compiled);
      assert.equal(compilation, facts.compilation); assert.equal(definition, model.definition);
      assert.equal(occurrence, model.occurrence); assert.equal(graph, model.graph);
      controls.demands++; return ok(demand);
    },
    clientProgramNodeEffectModelManagedPlanPrepare(value, selected) {
      assert.equal(value, original); assert.equal(selected, plan); assert(withModel); return ok(admission);
    },
    clientProgramInstalledEffectModelManagedPlanBegin(value, p, r, selected) {
      assert.equal(value, admission); assert.equal(p, prepared); assert.equal(r, request); assert.equal(selected, plan);
      assert(withModel); return controls.failBegin ? {$tag: 0, _0: undefined} : ok({_0: parent, _1: scope});
    },
    clientProgramFinishInferOriginalReadScope() {return ok(false);},
  };
  const quote = function(p, selected) {
    assert.equal(this, manager); assert.equal(p, prepared); assert.equal(selected, plan);
    controls.quotes++; return original;
  };
  const manager = {prepareEffectPlanRun: quote, prepareEffectModelPlanRun: quote};
  const selection = Object.freeze({prepareManagedPlan(f, actualInputs) {
    assert.equal(this, selection); assert.equal(f, facts);
    if (withModel) assert.equal(actualInputs.modelDemand, demand); else assert.equal(actualInputs, inputs);
    controls.selected++; return plan;
  }});
  const options = {runs, liveRuns, runtime, manager, prepared, request, facts, selection, inputs,
    sourceProfile, model, checked, assertCurrent() {controls.onCurrent?.(runs.get(prepared));}};
  return {options, runs, liveRuns, prepared, request, plan, parent, scope, model, demand, admission, original, controls};
}
function thrown(operation) {
  let observed = false, result;
  try {operation();} catch (cause) {observed = true; result = cause;}
  assert(observed, 'the original failure must be thrown'); return result;
}

test('public Record and Model Plan readers use one exact bound getter and no preceding check', () => {
  for (const withModel of [false, true]) {
    const f = fixture(withModel);
    assert.equal(Object.hasOwn(f.options.runtime, 'clientProgramInstalledEffectManagedRunCheck'), false);
    assert.equal(prepare(f.options), f.parent);
    assert.equal(f.controls.getters, 1); assert.equal(f.controls.checks, 0);
    assert.equal(prepare(f.options), f.parent); assert.equal(f.controls.getters, 2);
    const run = read(f.options); assert.equal(run.value, f.parent);
    assert.equal(f.controls.getters, 3); assert.equal(f.controls.checks, 0);
    assert.equal(f.controls.quotes, 1); assert.equal(f.controls.selected, 1);
    assert.equal(f.controls.demands, withModel ? 1 : 0);
    assert.equal(run.model, f.model); assert.equal(run.modelScope, withModel ? f.scope : undefined);
  }
});

test('public Plan getter cannot replace the original tuple or retained Model Scope', () => {
  for (const withModel of [false, true]) {
    for (const field of ['value', 'prepared', 'request', 'runtime', 'operationPlan', 'readPlan',
      'definitionOriginal', 'manager', 'selection', 'sourceProfile', 'model', 'modelDemand', 'modelScope']) {
      const f = fixture(withModel); prepare(f.options);
      f.controls.onRead = run => {run[field] = {};};
      assert.throws(() => read(f.options), {code: 'ForeignInstalledEffectManagedRun'});
      assert.equal(f.controls.getters, 2); assert.equal(f.controls.checks, 0);
    }
  }
});

test('public Plan getter retains every recorded primary before secondary shape or current failure', () => {
  for (const primary of [new Error('OriginalGetterFailure'), undefined, false, 0]) {
    for (const withModel of [false, true]) {
      const f = fixture(withModel); prepare(f.options); let returned = false;
      f.controls.onRead = run => {run.failure = primary; returned = true;};
      f.controls.returnedPlan = {};
      f.controls.onCurrent = () => {if (returned) throw new Error('SecondaryCurrent');};
      assert.equal(thrown(() => read(f.options)), primary);
      assert.equal(f.controls.getters, 2); assert.equal(f.controls.checks, 0);
    }
  }
});

test('public partial Record and Model Begin retains an undefined primary without reissuing', () => {
  for (const withModel of [false, true]) {
    const f = fixture(withModel); f.controls.failBegin = true;
    assert.equal(thrown(() => prepare(f.options)), undefined);
    const run = f.runs.get(f.prepared);
    assert.equal(run.original, f.original); assert.equal(run.admission, f.admission);
    assert(Object.hasOwn(run, 'failure'));
    assert.equal(thrown(() => prepare(f.options)), undefined);
    assert.equal(f.controls.quotes, 1); assert.equal(f.controls.selected, 1);
    assert.equal(f.controls.getters, 0);
  }
});

test('public Plan post-current fence retains same-parent retirement and Model association', () => {
  for (const action of ['closed', 'map', 'set', 'modelScope']) {
    const f = fixture(true); prepare(f.options); let returned = false;
    f.controls.onRead = () => {returned = true;};
    f.controls.onCurrent = run => {
      if (!returned) return;
      if (action === 'closed') run.closed = true;
      if (action === 'map') f.runs.delete(f.prepared);
      if (action === 'set') f.liveRuns.delete(run);
      if (action === 'modelScope') run.modelScope = {};
    };
    assert.throws(() => read(f.options), {code: 'ForeignInstalledEffectManagedRun'});
    assert.equal(f.controls.getters, 2); assert.equal(f.controls.checks, 0);
  }
});

// Stop after the actual acquired owner's first bound getter. No Source open,
// provider/Content construction or Compute is manufactured by this fixture.
async function acquiredBoundary(change) {
  const prepared = {}, request = {}, parent = {}, plan = {}, acquired = {prepared, requestIdentity: request};
  const primary = new Error('post-getter outer current');
  let returned = false, getters = 0, checks = 0, custody;
  const moon = {clientProgramEffectAcquisitionCount: () => 0,
    clientProgramEffectSerializationOccurrences: () => [{}],
    clientProgramInstalledEffectManagedOperationPlan(value, p, r) {
      assert.equal(this, moon); assert.equal(arguments.length, 3);
      assert.equal(value, parent); assert.equal(p, prepared); assert.equal(r, request);
      getters++; returned = true; if (change) acquired.prepared = {}; return ok(plan);
    },
    clientProgramInstalledEffectManagedHostOpen() {assert.fail('no Compute after boundary refusal');},
  };
  await assert.rejects(openAcquiredEffectComputation({moon, acquired, managedRun: parent,
    retainComputationOwner(value) {custody = value;},
    assertContinuationCurrent() {if (returned && !change) throw primary;},
  }), cause => change ? cause.code === 'ForeignInstalledEffectManagedRun' : cause === primary);
  assert.equal(getters, 1); assert.equal(checks, 0);
  assert.equal(custody.cleanupPending(), true);
  await custody.close(); assert.equal(await custody.cleanup(), true);
}

test('actual public acquired owner uses one bound getter before its next original current boundary', async () => {
  await acquiredBoundary(false);
});

test('actual public acquired owner refuses a prepared identity replaced by its bound getter', async () => {
  await acquiredBoundary(true);
});
