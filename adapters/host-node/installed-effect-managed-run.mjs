// The existing Host Run inventory retains the selected plan before quote or
// admission. A matching numeric quote, restored DATA or another original cannot
// replace it. This owns no provider work, permission or physical cleanup ACK.
import {types} from 'node:util';

const fail = code => {throw Object.assign(new Error(code), {code});};

export function prepareInstalledEffectManagedPlanRun({runs, liveRuns, runtime, manager,
  prepared, request, requestInput, selection, facts, inputs, sourceProfile, model, assertCurrent, checked}) {
  assertCurrent();
  const same = run => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.preparationKind !== 'effect-plan' || run.runtime !== runtime ||
        run.manager !== manager || run.prepared !== prepared || run.request !== request || run.requestInput !== requestInput || run.model !== model ||
        run.definitionOriginal === undefined || run.value === undefined || run.selection !== selection || run.sourceProfile !== sourceProfile ||
        ['prepared', 'identity', 'compilation', 'allowed', 'definition', 'queryTimePreparation', 'modelCompiled']
          .some(name => run.definitionOriginal[name] !== facts[name]) ||
        run.value === undefined) fail('ForeignInstalledEffectManagedRun');
    return readCurrentPlanParent(run, runs, liveRuns, runtime, prepared, request, assertCurrent, checked);
  };
  const old = runs.get(prepared);
  if (old !== undefined) return same(old);
  if (liveRuns.size >= 4096) fail('InstalledComputeRunLimit');
  const run = {preparationKind: 'effect-plan', runtime, manager, prepared, request, requestInput, selection, model,
    definitionOriginal: undefined, operationPlan: undefined, sourceProfile, original: undefined, admission: undefined, value: undefined, modelScope: undefined,
    closed: false, selecting: false, operationsBegun: false};
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
    run.readPlan = runtime.clientProgramInstalledEffectManagedOperationPlan;
    run.beginOperations = runtime.clientProgramInstalledEffectOperationControlsBegin;
    const beginOperations = run.beginOperations;
    if (![run.retire, run.readPlan, run.beginOperations].every(value => typeof value === 'function')) {
      fail('NodeManagedRunRuntimeUnavailable');
    }
    if (model === undefined) {
      // The original Request already paid for this constructor and retains its
      // typed Effect input. Complete/adopt that SAME parent, never quote a new
      // manager Root for the selected Plan.
      const adopt = Object.getOwnPropertyDescriptor(manager, 'adoptEffectPreparation')?.value;
      if (typeof adopt !== 'function' || requestInput === undefined) fail('InstalledEffectRequestPreparationUnavailable');
      const adopted = Reflect.apply(adopt, manager, [prepared, requestInput, request, operationPlan]);
      run.original = adopted.original;
      run.value = adopted.value;
      run.preparationFunded = true;
      if (adopted.operationPlan !== operationPlan || run.original === undefined || run.value === undefined) {
        fail('ForeignInstalledEffectManagedRun');
      }
      assertCurrent();
    } else {
      run.finishModelScope = runtime.clientProgramFinishInferOriginalReadScope;
      const matches = runtime.clientProgramInstalledEffectPlanMatchesModelDemand;
      const adopt = Object.getOwnPropertyDescriptor(manager, 'adoptEffectModelPreparation')?.value;
      if (typeof run.finishModelScope !== 'function' || typeof matches !== 'function') {
        fail('InstalledEffectModelRuntimeUnavailable');
      }
      if (typeof adopt !== 'function' || requestInput === undefined) fail('InstalledEffectRequestPreparationUnavailable');
      if (Reflect.apply(matches, runtime, [operationPlan, run.modelDemand]) !== true) {
        fail('ForeignInstalledEffectModelSelection');
      }
      const adopted = Reflect.apply(adopt, manager, [prepared, requestInput, request, operationPlan, run]);
      if (adopted.original !== run.original || adopted.operationPlan !== operationPlan ||
          run.original === undefined || run.modelScope === undefined || adopted.value === undefined) {
        fail('ForeignInstalledEffectManagedRun');
      }
      run.value = adopted.value;
      run.preparationFunded = true;
      assertCurrent();
    }
    // The original Request/Model adoption above supplies the SAME Ledger.
    // Quote DATA alone cannot back the consumer's later operation controls.
    const parent = run.value;
    checked(Reflect.apply(beginOperations, runtime, [parent, prepared, request, operationPlan]));
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.value !== parent || run.operationPlan !== operationPlan || run.beginOperations !== beginOperations) fail('ForeignInstalledEffectManagedRun');
    run.operationsBegun = true;
    return same(run);
  } catch (cause) {
    if (!Object.hasOwn(run, 'failure')) run.failure = cause;
    throw run.failure;
  }
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
  if (Object.hasOwn(run, 'failure')) throw run.failure;
  const parent = run.value, plan = run.operationPlan;
  if (parent === undefined || plan === undefined) fail('InstalledEffectPlanUnavailable');
  readCurrentPlanParent(run, runs, liveRuns, runtime, prepared, request, assertCurrent, checked);
  return run;
}

// A single bound Core getter owns currentness at this boundary. Fixed locals
// retain the original tuple without a second snapshot object or proof cache.
function readCurrentPlanParent(run, runs, liveRuns, runtime, prepared, request, assertCurrent, checked) {
  const parent = run.value, plan = run.operationPlan, readPlan = run.readPlan;
  const definition = run.definitionOriginal, manager = run.manager, selection = run.selection;
  const sourceProfile = run.sourceProfile, model = run.model, demand = run.modelDemand, scope = run.modelScope;
  const admission = run.admission, original = run.original, beginOperations = run.beginOperations;
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations);
  const actualPlan = checked(Reflect.apply(readPlan, runtime, [parent, prepared, request]));
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations);
  if (actualPlan !== plan) fail('ForeignInstalledEffectManagedRun');
  assertCurrent();
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations);
  return parent;
}

// Callback-free fences preserve the original Model Scope and cleanup lineage.
// Failure presence keeps even an original thrown undefined failed on retry.
function assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
  definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations) {
  if (Object.hasOwn(run, 'failure')) throw run.failure;
  if (runs.get(prepared) !== run || !liveRuns.has(run) || run.closed ||
      run.preparationKind !== 'effect-plan' || run.runtime !== runtime ||
      run.prepared !== prepared || run.request !== request || run.value !== parent ||
      run.operationPlan !== plan || run.readPlan !== readPlan || run.definitionOriginal !== definition ||
      run.manager !== manager || run.selection !== selection || run.sourceProfile !== sourceProfile ||
      run.model !== model || run.modelDemand !== demand || run.modelScope !== scope ||
      run.admission !== admission || run.original !== original || run.beginOperations !== beginOperations ||
      run.operationsBegun !== true) fail('ForeignInstalledEffectManagedRun');
}
