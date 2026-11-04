// The existing Host Run inventory retains the selected plan before quote or
// admission. A matching numeric quote, restored DATA or another original cannot
// replace it. This owns no provider work, permission or physical cleanup ACK.
import {types} from 'node:util';
import {prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import {selectAcquiredEffectPlanInputs} from './acquired-effect-sources.mjs';
import {openNodeComposedInferProvider, retireNodeInferOriginalRead} from './infer-operation.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};

export function prepareInstalledEffectManagedPlanRun({runs, liveRuns, runtime, manager,
  prepared, request, requestInput, selection, facts, inputs, sourceProfile, model, modelSelection,
  publicationControl, prepareContent, assertCurrent, checked}) {
  assertCurrent();
  const same = run => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.preparationKind !== 'effect-plan' || run.runtime !== runtime ||
        run.manager !== manager || run.prepared !== prepared || run.request !== request || run.requestInput !== requestInput || run.model !== model || run.modelSelection !== modelSelection ||
        run.definitionOriginal === undefined || run.value === undefined || run.selection !== selection || run.sourceProfile !== sourceProfile ||
        ['prepared', 'identity', 'compilation', 'allowed', 'definition', 'queryTimePreparation', 'modelCompiled']
          .some(name => run.definitionOriginal[name] !== facts[name]) ||
        run.value === undefined) fail('ForeignInstalledEffectManagedRun');
    return readCurrentPlanParent(run, runs, liveRuns, runtime, prepared, request, assertCurrent, checked);
  };
  const old = runs.get(prepared);
  if (old !== undefined) return same(old);
  if (liveRuns.size >= 4096) fail('InstalledComputeRunLimit');
  const run = {preparationKind: 'effect-plan', runtime, manager, prepared, request, requestInput, selection, model, modelSelection,
    definitionOriginal: undefined, operationPlan: undefined, sourceProfile, original: undefined, admission: undefined, value: undefined, modelScope: undefined,
    closed: false, selecting: false, operationsBegun: false};
  runs.set(prepared, run);
  liveRuns.add(run);
  try {
    // The sole installed issuer supplies a frozen own-DATA tuple. Do not move
    // an accessor/reentrant facts read across the original native boundary.
    if (facts === null || typeof facts !== 'object' || types.isProxy(facts) || !Object.isFrozen(facts)) {
      fail('ForeignInstalledEffectManagedRun');
    }
    const fields = Object.getOwnPropertyDescriptors(facts);
    if (['prepared', 'identity', 'compilation', 'allowed', 'definition', 'queryTimePreparation', 'modelCompiled',
      ...(modelSelection === undefined ? [] : ['runDefinition'])]
        .some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('ForeignInstalledEffectManagedRun');
    if (facts.prepared !== prepared || facts.identity !== request) fail('ForeignInstalledEffectManagedRun');
    run.definitionOriginal = Object.freeze(Object.fromEntries(
      ['prepared', 'identity', 'compilation', 'allowed', 'definition', 'queryTimePreparation', 'modelCompiled']
        .map(name => [name, facts[name]])));
    if (model !== undefined) {
      if (model === null || typeof model !== 'object' || types.isProxy(model) || !Object.isFrozen(model)) {
        fail('ForeignInstalledEffectModelSelection');
      }
      const modelFields = Object.getOwnPropertyDescriptors(model);
      if (Reflect.ownKeys(modelFields).length !== 5 ||
          ['kind', 'compiled', 'definition', 'occurrence', 'graph'].some(name =>
            !Object.hasOwn(modelFields[name] ?? {}, 'value')) ||
          modelFields.kind.value !== 'local-mock' || modelFields.compiled.value !== facts.modelCompiled ||
          modelFields.compiled.value === undefined || modelFields.definition.value !== facts.definition ||
          modelFields.occurrence.value === undefined || modelFields.graph.value === undefined) {
        fail('ForeignInstalledEffectModelSelection');
      }
      run.publicationControl = publicationControl;
      run.modelRunDefinition = fields.runDefinition?.value;
      run.prepareModelDemand = modelSelection === undefined ? runtime.clientProgramInstalledEffectModelDemandPrepare
        : publicationControl?.prepareCheckedClientEffectModelDemand;
      if (typeof run.prepareModelDemand !== 'function') fail('InstalledEffectModelRuntimeUnavailable');
      run.modelDemand = modelSelection === undefined ? checked(Reflect.apply(run.prepareModelDemand, runtime,
        [prepared, model.compiled, facts.compilation, model.definition, model.occurrence, model.graph]))
        : Reflect.apply(run.prepareModelDemand, publicationControl,
          [prepared, model.compiled, facts.compilation, facts.runDefinition, model.occurrence, model.graph]);
      if (run.modelDemand === null || typeof run.modelDemand !== 'object') fail('InstalledEffectModelDemandUnavailable');
      if (modelSelection !== undefined) {
        if (modelSelection.localMock !== true || modelSelection.occurrence !== model.occurrence ||
            modelSelection.graph !== model.graph) fail('ForeignInstalledEffectModelSelection');
        // The SAME native component is captured by the Plan configuration now.
        // Its physical context is bound once, after the original Sources have
        // been captured; execution must never construct a replacement provider.
        run.modelComponent = openNodeComposedInferProvider({moon: runtime, selected: modelSelection, deferred: true});
        run.modelComponents = Object.freeze([run.modelComponent.provider]);
      }
    }
    if (prepareContent !== undefined) {
      if (model !== undefined || typeof prepareContent !== 'function') fail('UnsupportedInstalledContentEffectClosure');
      run.contentOriginal = prepareContent(value => {run.contentCleanup = value;});
      if (run.contentOriginal?.preparation === undefined || run.contentCleanup === undefined) {
        fail('InstalledContentRunPreparationUnavailable');
      }
    }
    const select = Object.getOwnPropertyDescriptor(selection ?? {}, 'prepareManagedPlan')?.value;
    if (typeof select !== 'function') fail('InstalledEffectOperationDemandUnavailable');
    // The installed implementation must supply its complete original demand;
    // absence cannot select an empty inventory or the former scalar route.
    if (typeof runtime.clientProgramEffectAcquisitionCount === 'function' &&
        runtime.clientProgramEffectAcquisitionCount(prepared) !== 0) {
      run.sourceInputs = selectAcquiredEffectPlanInputs({moon: runtime, preparedEffect: prepared,
        requestIdentity: request, sourceProfile, queryContract: inputs.queryContract,
        evidenceContract: inputs.evidenceContract});
    }
    const planInputs = model === undefined && run.sourceInputs === undefined && run.contentOriginal === undefined ? inputs
      : Object.freeze({...inputs,
        ...(run.contentOriginal === undefined ? {} : {contentPreparation: run.contentOriginal.preparation}), ...(run.sourceInputs === undefined ? {} : {sourceInputs: run.sourceInputs}),
        ...(model === undefined ? {} : {modelDemand: run.modelDemand,
          ...(run.modelComponents === undefined ? {} : {modelComponents: run.modelComponents})})});
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
    run.beginOperations = runtime.clientProgramInstalledEffectOperationControlsRetain;
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
      run.finishModelScope = modelSelection === undefined ? runtime.clientProgramFinishInferOriginalReadScope
        : publicationControl?.finishCheckedClientInferOriginalReadScope;
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
    const parent = run.value, definition = run.definitionOriginal, readPlan = run.readPlan;
    const demand = run.modelDemand, scope = run.modelScope, admission = run.admission, original = run.original;
    const component = run.modelComponent, sourceInputs = run.sourceInputs, modelControl = run.publicationControl,
      modelDefinition = run.modelRunDefinition;
    const actualPlan = checked(Reflect.apply(beginOperations, runtime, [parent, prepared, request, operationPlan]));
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (actualPlan !== operationPlan || run.value !== parent || run.operationPlan !== operationPlan ||
        run.beginOperations !== beginOperations || run.requestInput !== requestInput ||
        ['prepared', 'identity', 'compilation', 'allowed', 'definition', 'queryTimePreparation', 'modelCompiled']
          .some(name => definition[name] !== facts[name])) fail('ForeignInstalledEffectManagedRun');
    run.operationsBegun = true;
    // Consume the SAME native Plan result immediately. No optional proof or
    // cached current flag escapes; cached/later reads still call their getter.
    assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, operationPlan, readPlan,
      definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition);
    // Capture the control methods only after that original post-current fence;
    // a replaced Runtime must retain its original Foreign refusal precedence.
    run.selecting = true;
    try {
      run.controlConstruction = prepareInstalledEffectControlConstruction(run);
      run.retireControlConstruction = run.controlConstruction.retire;
    } finally {run.selecting = false;}
    assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, operationPlan, readPlan,
      definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition);
    assertCurrent();
    assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, operationPlan, readPlan,
      definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition);
    return parent;
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
  const sameControl = run.publicationControl, sameDefinition = run.modelRunDefinition, sameFinish = run.finishModelScope;
  run.modelScopeFinishing = true;
  try {
    const finished = run.publicationControl === undefined ? checked(Reflect.apply(run.finishModelScope, run.runtime,
      [sameScope, sameModel.compiled, sameModel.definition, sameModel.graph, originalRunCleanupComplete]))
      : Reflect.apply(run.finishModelScope, run.publicationControl,
        [sameModel.compiled, run.modelRunDefinition, sameModel.graph, sameScope, originalRunCleanupComplete]);
    if (run.modelScope !== sameScope || run.value !== sameParent || run.model !== sameModel ||
        run.publicationControl !== sameControl || run.modelRunDefinition !== sameDefinition || run.finishModelScope !== sameFinish) {
      fail('ForeignInstalledEffectModelScope');
    }
    if (finished !== true) fail('InstalledEffectModelScopeCleanupPending');
    run.modelScopeFinished = true;
  } finally {run.modelScopeFinishing = false;}
}

// Borrow the SAME early Request Scope when Local supplies the actual captured
// inputs. Its original read remains on this Run through failed construction;
// no late Scope, admission, bounds selection or independent Model Root exists.
export function installedEffectModelPreparation(run, publicationCapacity, assertCurrent) {
  const model = run.model, control = run.publicationControl, definition = run.modelRunDefinition,
    scope = run.modelScope, parent = run.value, demand = run.modelDemand;
  const current = () => {
    assertCurrent();
    if (run.closed || run.model !== model || run.publicationControl !== control ||
        run.modelRunDefinition !== definition || run.modelScope !== scope || run.value !== parent ||
        run.modelDemand !== demand || run.modelScopeFinished || scope === undefined || control === undefined) {
      fail('ForeignInstalledEffectModelScope');
    }
  };
  current();
  if (run.modelPreparation !== undefined) return run.modelPreparation;
  const readWindow = run.runtime.clientProgramInstalledEffectModelReadWindow;
  if (typeof readWindow !== 'function' || typeof publicationCapacity !== 'function') {
    fail('InstalledEffectModelRuntimeUnavailable');
  }
  const window = Reflect.apply(readWindow, run.runtime, [demand]);
  if (!Array.isArray(window) || window.length !== 2 ||
      window.some(value => typeof value !== 'bigint' || value <= 0n)) fail('InvalidHostRuntimeResult');
  const retained = window[0], execution = window[1];
  const fields = {control, compiled: model.compiled, runDefinition: definition, scope, publicationCapacity,
    readRetainedBytes: retained, readExecutionBytes: execution,
    modelRetainedBytes: retained, modelExecutionBytes: execution};
  const view = Object.freeze({...fields,
    retain() {
      current();
      if (run.modelPreparationRetired || run.modelPreparationTaken || run.modelReadAttempted) fail('ForeignInstalledEffectModelScope');
      run.modelPreparationTaken = true;
    },
    prepareRead() {
      current();
      if (Object.hasOwn(run, 'modelReadFailure')) throw run.modelReadFailure;
      if (run.modelPreparationRetired || !run.modelPreparationTaken || run.modelReadAttempted) fail('ForeignInstalledEffectModelScope');
      run.modelReadAttempted = true;
      try {
        run.modelRead = control.prepareCheckedClientInferOriginalRead(
          model.compiled, definition, model.graph, scope, fields);
        return Object.freeze({...fields, read: run.modelRead});
      } catch (cause) {run.modelReadFailure = cause; throw cause;}
    },
    retire() {
      current();
      if (run.modelPreparationRetired) return true;
      retireNodeInferOriginalRead({control, compiled: model.compiled, runDefinition: definition,
        graph: model.graph, scope, read: run.modelRead});
      run.modelRead = undefined;
      run.modelPreparationRetired = true;
      return true;
    },
  });
  run.modelPreparation = view;
  return view;
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
  const modelSelection = run.modelSelection, component = run.modelComponent, sourceInputs = run.sourceInputs,
    modelControl = run.publicationControl, modelDefinition = run.modelRunDefinition;
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition);
  const actualPlan = checked(Reflect.apply(readPlan, runtime, [parent, prepared, request]));
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition);
  if (actualPlan !== plan) fail('ForeignInstalledEffectManagedRun');
  assertCurrent();
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition);
  return parent;
}

// Callback-free fences preserve the original Model Scope and cleanup lineage.
// Failure presence keeps even an original thrown undefined failed on retry.
function assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
  definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
  modelSelection, component, sourceInputs, modelControl, modelDefinition) {
  if (Object.hasOwn(run, 'failure')) throw run.failure;
  if (runs.get(prepared) !== run || !liveRuns.has(run) || run.closed ||
      run.preparationKind !== 'effect-plan' || run.runtime !== runtime ||
      run.prepared !== prepared || run.request !== request || run.value !== parent ||
      run.operationPlan !== plan || run.readPlan !== readPlan || run.definitionOriginal !== definition ||
      run.manager !== manager || run.selection !== selection || run.sourceProfile !== sourceProfile ||
      run.model !== model || run.modelDemand !== demand || run.modelScope !== scope ||
      run.admission !== admission || run.original !== original || run.beginOperations !== beginOperations ||
      run.operationsBegun !== true || run.modelSelection !== modelSelection || run.modelComponent !== component ||
      run.sourceInputs !== sourceInputs || run.publicationControl !== modelControl ||
      run.modelRunDefinition !== modelDefinition) fail('ForeignInstalledEffectManagedRun');
}
