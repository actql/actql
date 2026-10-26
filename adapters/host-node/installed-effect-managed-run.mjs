// The existing Host Run inventory retains the selected plan before quote or
// admission. A matching numeric quote, restored DATA or another original cannot
// replace it. This owns no provider work, permission or physical cleanup ACK.
import {types} from 'node:util';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};

export function prepareInstalledEffectManagedPlanRun({runs, liveRuns, runtime, manager,
  prepared, request, selection, facts, inputs, sourceProfile, model, assertCurrent, checked}) {
  assertCurrent();
  const same = run => {
    if (run.failure !== undefined) throw run.failure;
    if (run.closed || run.preparationKind !== 'effect-plan' || run.runtime !== runtime ||
        run.manager !== manager || run.prepared !== prepared || run.request !== request || run.model !== model ||
        run.definitionOriginal === undefined || run.value === undefined || run.selection !== selection || run.sourceProfile !== sourceProfile ||
        ['prepared', 'identity', 'compilation', 'allowed', 'definition', 'queryTimePreparation', 'modelCompiled']
          .some(name => run.definitionOriginal[name] !== facts[name]) ||
        run.value === undefined) fail('ForeignInstalledEffectManagedRun');
    const parent = run.value, operationPlan = run.operationPlan;
    checked(Reflect.apply(run.check, runtime, [parent, prepared, request]));
    if (run.failure !== undefined) throw run.failure;
    if (run.value !== parent) fail('ForeignInstalledEffectManagedRun');
    if (checked(Reflect.apply(run.readPlan, runtime, [parent])) !== operationPlan) {
      fail('ForeignInstalledEffectManagedRun');
    }
    assertCurrent();
    if (runs.get(prepared) !== run || !liveRuns.has(run) || run.closed ||
        run.value !== parent || run.operationPlan !== operationPlan) fail('ForeignInstalledEffectManagedRun');
    if (run.failure !== undefined) throw run.failure;
    return parent;
  };
  const old = runs.get(prepared);
  if (old !== undefined) return same(old);
  if (liveRuns.size >= 4096) fail('InstalledComputeRunLimit');
  const run = {preparationKind: 'effect-plan', runtime, manager, prepared, request, selection, model,
    definitionOriginal: undefined, operationPlan: undefined, sourceProfile, original: undefined, admission: undefined, value: undefined,
    failure: undefined, closed: false, selecting: false};
  runs.set(prepared, run);
  liveRuns.add(run);
  try {
    if (facts?.prepared !== prepared || facts.identity !== request) fail('ForeignInstalledEffectManagedRun');
    run.definitionOriginal = Object.freeze(Object.fromEntries(
      ['prepared', 'identity', 'compilation', 'allowed', 'definition', 'queryTimePreparation', 'modelCompiled']
        .map(name => [name, facts[name]])));
    if (model !== undefined) {
      if (model === null || typeof model !== 'object' || types.isProxy(model) || !Object.isFrozen(model)) {
        fail('ForeignInstalledEffectModelSelection');
      }
      const fields = Object.getOwnPropertyDescriptors(model);
      if (Reflect.ownKeys(fields).length !== 5 ||
          ['kind', 'compiled', 'definition', 'occurrence', 'graph'].some(name =>
            !Object.hasOwn(fields[name] ?? {}, 'value')) ||
          fields.kind.value !== 'local-mock' || fields.compiled.value !== facts.modelCompiled ||
          fields.compiled.value === undefined || fields.definition.value !== facts.definition ||
          fields.occurrence.value === undefined || fields.graph.value === undefined) {
        fail('ForeignInstalledEffectModelSelection');
      }
      run.prepareModelDemand = runtime.clientProgramInstalledEffectModelDemandPrepare;
      if (typeof run.prepareModelDemand !== 'function') fail('InstalledEffectModelRuntimeUnavailable');
      run.modelDemand = checked(Reflect.apply(run.prepareModelDemand, runtime,
        [prepared, model.compiled, facts.compilation, model.definition, model.occurrence, model.graph]));
      if (run.modelDemand === null || typeof run.modelDemand !== 'object') fail('InstalledEffectModelDemandUnavailable');
    }
    const select = Object.getOwnPropertyDescriptor(selection ?? {}, 'prepareManagedPlan')?.value;
    if (typeof select !== 'function') fail('InstalledEffectOperationDemandUnavailable');
    // The installed implementation must supply its complete original demand;
    // absence cannot select an empty inventory or the former scalar route.
    const planInputs = model === undefined ? inputs : Object.freeze({...inputs, modelDemand: run.modelDemand});
    run.operationPlan = Reflect.apply(select, selection, [facts, planInputs]);
    const operationPlan = run.operationPlan;
    if (types.isPromise(operationPlan)) {
      run.selecting = true;
      void operationPlan.then(value => {run.selectionResult = value; run.selecting = false;},
        cause => {run.selectionFailure = cause; run.selecting = false;});
      fail('InstalledEffectPlanUnavailable');
    }
    if (operationPlan === null || typeof operationPlan !== 'object') fail('InstalledEffectPlanUnavailable');
    assertCurrent();
    // Capture cleanup before any constructor. A partial begin remains attached
    // to this same record and can never acquire another admission on retry.
    run.retire = runtime.clientProgramInstalledManagedRunRetire;
    run.cleanup = runtime.clientProgramNodeEffectManagedPlanCleanup;
    run.check = runtime.clientProgramInstalledEffectManagedRunCheck;
    run.readPlan = runtime.clientProgramInstalledEffectManagedOperationPlan;
    run.prepare = model === undefined ? runtime.clientProgramNodeEffectManagedPlanPrepare
      : runtime.clientProgramNodeEffectModelManagedPlanPrepare;
    run.begin = model === undefined ? runtime.clientProgramInstalledEffectManagedPlanBegin
      : runtime.clientProgramInstalledEffectModelManagedPlanBegin;
    run.finishModelScope = model === undefined ? undefined : runtime.clientProgramFinishInferOriginalReadScope;
    const original = model === undefined ? manager.prepareEffectPlanRun : manager.prepareEffectModelPlanRun;
    if (![run.retire, run.cleanup, run.check, run.readPlan, run.prepare, run.begin, original]
      .every(value => typeof value === 'function')) fail('NodeManagedRunRuntimeUnavailable');
    if (model !== undefined && typeof run.finishModelScope !== 'function') fail('InstalledEffectModelRuntimeUnavailable');
    run.original = Reflect.apply(original, manager, [prepared, operationPlan]);
    assertCurrent();
    run.admission = checked(Reflect.apply(run.prepare, runtime, [run.original, operationPlan]));
    const begun = checked(Reflect.apply(run.begin, runtime, [run.admission, prepared, request, operationPlan]));
    run.value = model === undefined ? begun : runtimeField(begun, 0);
    if (model !== undefined) {
      run.modelScope = runtimeField(begun, 1);
      if (run.value === undefined || run.modelScope === undefined) fail('InstalledEffectModelScopeUnavailable');
    }
    return same(run);
  } catch (cause) {run.failure = cause; throw cause;}
}

// Only the existing complete dispatch/initialization retirement caller supplies
// this physical-cleanup observation. A terminal Run or settled Promise cannot.
export function finishInstalledEffectModelScope(run, originalRunCleanupComplete, checked) {
  if (run.modelScope === undefined || run.modelScopeFinished === true) return;
  if (run.modelScopeFinishing) fail('InstalledEffectModelScopeCleanupPending');
  const sameScope = run.modelScope, sameParent = run.value, sameModel = run.model;
  run.modelScopeFinishing = true;
  try {
    const finished = checked(Reflect.apply(run.finishModelScope, run.runtime,
      [sameScope, sameModel.compiled, sameModel.definition, sameModel.graph, originalRunCleanupComplete]));
    if (run.modelScope !== sameScope || run.value !== sameParent || run.model !== sameModel) {
      fail('ForeignInstalledEffectModelScope');
    }
    if (finished !== true) fail('InstalledEffectModelScopeCleanupPending');
    run.modelScopeFinished = true;
  } finally {run.modelScopeFinishing = false;}
}

export function readInstalledEffectManagedPlanRun({runs, liveRuns, runtime,
  prepared, request, assertCurrent, checked}) {
  assertCurrent();
  const run = runs?.get(prepared);
  if (run === undefined || !liveRuns?.has(run) || run.preparationKind !== 'effect-plan' ||
      run.closed || run.runtime !== runtime || run.prepared !== prepared || run.request !== request) {
    fail('InstalledEffectPlanUnavailable');
  }
  if (run.failure !== undefined) throw run.failure;
  const parent = run.value, plan = run.operationPlan;
  if (parent === undefined || plan === undefined) fail('InstalledEffectPlanUnavailable');
  checked(Reflect.apply(run.check, runtime, [parent, prepared, request]));
  if (run.failure !== undefined) throw run.failure;
  if (run.value !== parent) fail('ForeignInstalledEffectManagedRun');
  if (checked(Reflect.apply(run.readPlan, runtime, [parent])) !== plan) fail('ForeignInstalledEffectManagedRun');
  assertCurrent();
  if (runs.get(prepared) !== run || !liveRuns.has(run) || run.closed ||
      run.value !== parent || run.operationPlan !== plan) fail('ForeignInstalledEffectManagedRun');
  if (run.failure !== undefined) throw run.failure;
  return run;
}
