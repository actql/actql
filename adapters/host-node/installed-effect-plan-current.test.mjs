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
  const facts = Object.freeze({prepared, identity: request, compilation: {}, allowed: {},
    definition: model?.definition ?? {}, modelCompiled: model?.compiled, queryTimePreparation: undefined});
  const runs = new WeakMap(), liveRuns = new Set(), inputs = Object.freeze({}), sourceProfile = {};
  const controls = {getters: 0, checks: 0, quotes: 0, selected: 0, demands: 0,
    onRead: undefined, onCurrent: undefined, returnedPlan: plan, failBegin: false};
  const runtime = {
    clientProgramInstalledEffectOperationControlConstructionBegin() {return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlConstructionComplete() {return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlsRetain() {return ok(plan);},
    clientProgramInstalledManagedRunRetire() {return ok();},
    clientProgramNodeEffectManagedPlanCleanup() {return ok();},
    clientProgramInstalledEffectManagedOperationPlan(value, p, r) {
      assert.equal(this, runtime); assert.equal(arguments.length, 3);
      assert.equal(value, parent); assert.equal(p, prepared); assert.equal(r, request);
      controls.getters++; controls.onRead?.(runs.get(prepared)); return ok(controls.returnedPlan);
    },
    clientProgramInstalledEffectModelDemandPrepare(p, compiled, compilation, definition, occurrence, graph) {
      assert(withModel); assert.equal(p, prepared); assert.equal(compiled, model.compiled);
      assert.equal(compilation, facts.compilation); assert.equal(definition, model.definition);
      assert.equal(occurrence, model.occurrence); assert.equal(graph, model.graph);
      controls.demands++; return ok(demand);
    },
    clientProgramInstalledEffectPlanMatchesModelDemand(selected, originalDemand) {
      assert(withModel); return selected === plan && originalDemand === demand;
    },
    clientProgramFinishInferOriginalReadScope() {return ok(false);},
  };
  const requestInput = {};
  const manager = {
    adoptEffectModelPreparation(p, actualInput, identity, selected, run) {
      assert.equal(this, manager); assert(withModel); assert.equal(p, prepared);
      assert.equal(actualInput, requestInput); assert.equal(identity, request); assert.equal(selected, plan);
      assert.equal(run, runs.get(prepared)); run.original = original; run.modelScope = scope;
      controls.quotes++; if (controls.failBegin) throw undefined;
      return {original, value: parent, operationPlan: plan};
    },
    adoptEffectPreparation(p, actualInput, identity, selected) {
      assert.equal(this, manager); assert(!withModel); assert.equal(p, prepared);
      assert.equal(actualInput, requestInput); assert.equal(identity, request); assert.equal(selected, plan);
      controls.quotes++;
      if (controls.failBegin) throw undefined;
      return {original, value: parent, operationPlan: plan};
    }};
  const selection = Object.freeze({prepareManagedPlan(f, actualInputs) {
    assert.equal(this, selection); assert.equal(f, facts);
    if (withModel) assert.equal(actualInputs.modelDemand, demand); else assert.equal(actualInputs, inputs);
    controls.selected++; return plan;
  }});
  const options = {runs, liveRuns, runtime, manager, prepared, request, requestInput, facts, selection, inputs,
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
    assert.equal(f.controls.getters, 0); assert.equal(f.controls.checks, 0);
    assert.equal(prepare(f.options), f.parent); assert.equal(f.controls.getters, 1);
    const run = read(f.options); assert.equal(run.value, f.parent);
    assert.equal(f.controls.getters, 2); assert.equal(f.controls.checks, 0);
    assert.equal(f.controls.quotes, 1); assert.equal(f.controls.selected, 1);
    assert.equal(f.controls.demands, withModel ? 1 : 0);
    assert.equal(run.model, f.model); assert.equal(run.modelScope, withModel ? f.scope : undefined);
  }
});

test('public Plan getter cannot replace the original tuple or retained Model Scope', () => {
  for (const withModel of [false, true]) {
    for (const field of ['value', 'prepared', 'request', 'runtime', 'operationPlan', 'readPlan',
      'definitionOriginal', 'manager', 'selection', 'sourceProfile', 'model', 'modelDemand', 'modelScope',
      'modelSelection', 'modelComponent', 'sourceInputs', 'publicationControl', 'modelRunDefinition']) {
      const f = fixture(withModel); prepare(f.options);
      f.controls.onRead = run => {run[field] = {};};
      assert.throws(() => read(f.options), {code: 'ForeignInstalledEffectManagedRun'});
      assert.equal(f.controls.getters, 1); assert.equal(f.controls.checks, 0);
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
      assert.equal(f.controls.getters, 1); assert.equal(f.controls.checks, 0);
    }
  }
});

test('public partial Record and Model Begin retains an undefined primary without reissuing', () => {
  for (const withModel of [false, true]) {
    const f = fixture(withModel); f.controls.failBegin = true;
    assert.equal(thrown(() => prepare(f.options)), undefined);
    const run = f.runs.get(f.prepared);
    assert.equal(run.original, withModel ? f.original : undefined);
    assert.equal(run.admission, undefined);
    assert.equal(run.modelScope, withModel ? f.scope : undefined);
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
    assert.equal(f.controls.getters, 1); assert.equal(f.controls.checks, 0);
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

test('original Effect control debit follows Request adoption once before a consumer getter',()=>{
  for(const withModel of [false,true]){
    const f=fixture(withModel);let debits=0;
    f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=function(owner,prepared,request,plan){
      assert.equal(this,f.options.runtime);assert.equal(owner,f.parent);assert.equal(prepared,f.prepared);assert.equal(request,f.request);assert.equal(plan,f.plan);
      assert.equal(f.runs.get(f.prepared).value,f.parent);assert.equal(f.controls.quotes,1);debits++;return ok(plan);
    };
    f.controls.onRead=()=>assert.equal(debits,1);
    assert.equal(prepare(f.options),f.parent);assert.equal(prepare(f.options),f.parent);read(f.options);
    assert.equal(debits,1);assert.equal(f.runs.get(f.prepared).operationsBegun,true);
  }
});

test('failed original Effect control debit remains attached to its same adopted Request',()=>{
  for(const failure of [undefined,false,new Error('original control capacity refusal')]){
    const f=fixture();let debits=0;
    f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=()=>{debits++;throw failure;};
    assert.equal(thrown(()=>prepare(f.options)),failure);
    const original=f.runs.get(f.prepared);
    assert.equal(original.value,f.parent);assert.equal(original.operationsBegun,false);assert.equal(original.failure,failure);
    assert.equal(thrown(()=>prepare(f.options)),failure);assert.equal(thrown(()=>read(f.options)),failure);
    assert.equal(debits,1);assert.equal(f.controls.quotes,1);assert.equal(f.controls.selected,1);
  }
});

test('control Begin preserves a recorded primary before its secondary native refusal',()=>{
  for(const primary of [undefined,false,new Error('original current failure')]){
    const f=fixture(),secondary=new Error('secondary native refusal');
    f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=()=>{f.runs.get(f.prepared).failure=primary;return {$tag:0,_0:secondary};};
    assert.equal(thrown(()=>prepare(f.options)),primary);
    assert.equal(thrown(()=>read(f.options)),primary);
    assert.equal(f.controls.quotes,1);
  }
});


test('initial Effect controls return the same original Plan without another getter; later reads stay current',()=>{
  for(const withModel of [false,true]){
    const f=fixture(withModel);let begun=false,after=0;
    f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=function(parent,prepared,request,plan){
      assert.equal(this,f.options.runtime);assert.equal(parent,f.parent);assert.equal(prepared,f.prepared);
      assert.equal(request,f.request);assert.equal(plan,f.plan);begun=true;return ok(plan);
    };
    f.controls.onCurrent=()=>{if(begun)after++;};
    assert.equal(prepare(f.options),f.parent);assert.equal(f.controls.getters,0);assert.equal(after,1);
    assert.equal(prepare(f.options),f.parent);assert.equal(f.controls.getters,1);
    assert.equal(read(f.options).operationPlan,f.plan);assert.equal(f.controls.getters,2);
  }
});

test('initial Effect controls refuse a Unit or foreign returned Plan on the same adopted parent',()=>{
  for(const returned of [undefined,{},null]){
    const f=fixture();let calls=0;
    f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=()=>{calls++;return ok(returned);};
    const cause=thrown(()=>prepare(f.options));assert.equal(cause.code,'ForeignInstalledEffectManagedRun');
    assert.equal(f.runs.get(f.prepared).value,f.parent);assert.equal(f.controls.getters,0);
    assert.equal(thrown(()=>prepare(f.options)),cause);assert.equal(calls,1);
  }
});


test('initial Effect facts must be the actual frozen own DATA shape before native entry',()=>{
  for(const kind of ['mutable','accessor','proxy','missing']){
    const f=fixture();let getters=0,begins=0;const copy={...f.options.facts};let facts;
    if(kind==='mutable')facts=copy;
    if(kind==='accessor'){Object.defineProperty(copy,'prepared',{get(){getters++;return f.prepared;},enumerable:true});facts=Object.freeze(copy);}
    if(kind==='proxy')facts=new Proxy(f.options.facts,{get(){getters++;throw new Error('No proxy operation');}});
    if(kind==='missing'){delete copy.queryTimePreparation;facts=Object.freeze(copy);}
    f.options.facts=facts;f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=()=>{begins++;return ok(f.plan);};
    const cause=thrown(()=>prepare(f.options));assert.equal(cause.code,'ForeignInstalledEffectManagedRun');
    assert.equal(thrown(()=>prepare(f.options)),cause);assert.equal(getters,0);assert.equal(begins,0);
    assert.equal(f.controls.selected,0);assert.equal(f.controls.quotes,0);
  }
});

test('initial Effect Plan result preserves original primary and Model post-callback fences',()=>{
  for(const field of ['value','prepared','request','runtime','operationPlan','readPlan','definitionOriginal',
    'manager','selection','sourceProfile','model','modelDemand','modelScope','admission','original','requestInput','closed','map','set']){
    const f=fixture(true);
    f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=()=>{
      const run=f.runs.get(f.prepared);
      if(field==='map')f.runs.delete(f.prepared);else if(field==='set')f.liveRuns.delete(run);
      else run[field]=field==='closed'?true:{};
      return ok(f.plan);
    };
    assert.throws(()=>prepare(f.options),{code:'ForeignInstalledEffectManagedRun'});assert.equal(f.controls.getters,0);
  }
  for(const primary of [undefined,false,new Error('Original controls primary')]){
    const f=fixture(true);f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=()=>{
      f.runs.get(f.prepared).failure=primary;return ok({});
    };
    assert.equal(thrown(()=>prepare(f.options)),primary);assert.equal(thrown(()=>read(f.options)),primary);
    assert.equal(f.controls.getters,0);
  }
  const f=fixture(true);let begun=false;
  f.options.runtime.clientProgramInstalledEffectOperationControlsRetain=()=>{begun=true;return ok(f.plan);};
  f.controls.onCurrent=run=>{if(begun)run.modelScope={};};
  assert.throws(()=>prepare(f.options),{code:'ForeignInstalledEffectManagedRun'});assert.equal(f.controls.getters,0);
});
