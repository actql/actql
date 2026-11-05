// The existing Host Run inventory retains the selected plan before quote or
// admission. A matching numeric quote, restored DATA or another original cannot
// replace it. This owns no provider work, permission or physical cleanup ACK.
import {types} from 'node:util';
import {inferOriginalReadStartupCapacity} from './infer-original-installation.mjs';
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
      const plural = Array.isArray(model.components);
      if (plural && (!Object.isFrozen(model) || types.isProxy(model) ||
          !Object.isFrozen(model.components) || model.components.length < 2 ||
          !Array.isArray(modelSelection?.components) || !Object.isFrozen(modelSelection.components) ||
          modelSelection.components.length !== model.components.length ||
          !Array.isArray(model.graph) || model.graph !== modelSelection.graph ||
          model.components.some((member, index) => member.graph !== model.graph[index]))) {
        fail('ForeignInstalledEffectModelSelection');
      }
      run.publicationControl = publicationControl;
      run.modelRunDefinition = fields.runDefinition?.value;
      const members = plural ? model.components.map((member, index) => ({model: member,
        modelSelection: modelSelection.components[index], modelScope: undefined})) : [run];
      if (plural) run.modelMembers = Object.freeze(members);
      for (const member of members) {
        prepareEffectModelMember(member, run, facts, publicationControl, prepareContent, checked);
      }
      if (plural) {
        const compose = runtime.clientProgramInstalledEffectModelsDemandPrepare;
        if (typeof compose !== 'function') fail('InstalledEffectModelRuntimeUnavailable');
        run.modelDemand = checked(Reflect.apply(compose, runtime, [members.map(member => member.modelDemand)]));
        run.modelComponents = Object.freeze(members.map(member => member.modelComponent.provider));
      }
    }
    if (prepareContent !== undefined) {
      if (typeof prepareContent !== 'function') fail('UnsupportedInstalledContentEffectClosure');
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
    run.quiesce = runtime.clientProgramInstalledManagedRunQuiesce;
    run.readPlan = runtime.clientProgramInstalledEffectManagedOperationPlan;
    run.beginOperations = runtime.clientProgramInstalledEffectOperationControlsRetain;
    const beginOperations = run.beginOperations;
    if (![run.retire, run.readPlan, run.beginOperations, ...(model === undefined ? [] : [run.quiesce])]
        .every(value => typeof value === 'function')) {
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
          run.original === undefined ||
          (run.modelMembers === undefined ? run.modelScope === undefined :
            !Array.isArray(run.modelScopes) || run.modelScopes.length !== run.modelMembers.length ||
              run.modelMembers.some((member, index) => member.modelScope !== run.modelScopes[index])) || adopted.value === undefined) {
        fail('ForeignInstalledEffectManagedRun');
      }
      run.value = adopted.value;
      run.preparationFunded = true;
      for (const member of run.modelMembers ?? [run]) {
        const selected = member.modelSelection;
        if (selected === undefined || selected.localMock === true) continue;
        if (typeof selected.bindTrustedRuntimeScope !== 'function' ||
            typeof selected.assertTrustedRuntimeScope !== 'function' ||
            typeof selected.finishTrustedRuntimeScope !== 'function') fail('InstalledEffectModelRuntimeUnavailable');
        // The WHOLE Scope inventory is retained before a fallible association.
        member.modelRuntimeView = selected.bindTrustedRuntimeScope(
          member.modelScope, member.model.compiled, run.modelRunDefinition, member.model.graph);
      }
      assertCurrent();
    }
    // The original Request/Model adoption above supplies the SAME Ledger.
    // Quote DATA alone cannot back the consumer's later operation controls.
    const parent = run.value, definition = run.definitionOriginal, readPlan = run.readPlan;
    const demand = run.modelDemand, scope = run.modelScope, admission = run.admission, original = run.original;
    const members = run.modelMembers, scopes = run.modelScopes;
    const component = run.modelMembers === undefined ? run.modelComponent : run.modelComponents, sourceInputs = run.sourceInputs, modelControl = run.publicationControl,
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
    modelSelection, component, sourceInputs, modelControl, modelDefinition, members, scopes);
    // Capture the control methods only after that original post-current fence;
    // a replaced Runtime must retain its original Foreign refusal precedence.
    run.selecting = true;
    try {
      run.controlConstruction = prepareInstalledEffectControlConstruction(run);
      run.retireControlConstruction = run.controlConstruction.retire;
    } finally {run.selecting = false;}
    assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, operationPlan, readPlan,
      definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition, members, scopes);
    assertCurrent();
    assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, operationPlan, readPlan,
      definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition, members, scopes);
    return parent;
  } catch (cause) {
    if (!Object.hasOwn(run, 'failure')) run.failure = cause;
    throw run.failure;
  }
}

function prepareEffectModelMember(member, run, facts, publicationControl, prepareContent, checked) {
  const {model, modelSelection} = member, runtime = run.runtime, prepared = run.prepared;
  if (model === null || typeof model !== 'object' || types.isProxy(model) || !Object.isFrozen(model)) {
    fail('ForeignInstalledEffectModelSelection');
  }
  const fields = Object.getOwnPropertyDescriptors(model);
  if (Reflect.ownKeys(fields).length !== 5 ||
      ['kind', 'compiled', 'definition', 'occurrence', 'graph'].some(name => !Object.hasOwn(fields[name] ?? {}, 'value')) ||
      model.kind !== (modelSelection !== undefined && modelSelection.localMock !== true ? 'installed-model' : 'local-mock') ||
      model.compiled !== facts.modelCompiled || model.compiled === undefined || model.definition !== facts.definition ||
      model.occurrence === undefined || model.graph === undefined) fail('ForeignInstalledEffectModelSelection');
  const physical = modelSelection !== undefined && modelSelection.localMock !== true;
  if (physical && (modelSelection.originalReadInstallation === undefined || modelSelection.selectedBounds === undefined)) {
    fail('InstalledEffectModelRuntimeUnavailable');
  }
  member.prepareModelDemand = modelSelection === undefined ? runtime.clientProgramInstalledEffectModelDemandPrepare
    : physical ? publicationControl?.prepareCheckedClientNodeEffectModelDemand : publicationControl?.prepareCheckedClientEffectModelDemand;
  if (typeof member.prepareModelDemand !== 'function') fail('InstalledEffectModelRuntimeUnavailable');
  member.modelDemand = modelSelection === undefined ? checked(Reflect.apply(member.prepareModelDemand, runtime,
    [prepared, model.compiled, facts.compilation, model.definition, model.occurrence, model.graph]))
    : Reflect.apply(member.prepareModelDemand, publicationControl,
      [prepared, model.compiled, facts.compilation, facts.runDefinition, model.occurrence, model.graph,
        ...(physical ? [modelSelection.selectedBounds, modelSelection.originalReadInstallation] : [])]);
  if (member.modelDemand === null || typeof member.modelDemand !== 'object') fail('InstalledEffectModelDemandUnavailable');
  if (modelSelection !== undefined) {
    if (modelSelection.occurrence !== model.occurrence || modelSelection.graph !== model.graph) fail('ForeignInstalledEffectModelSelection');
    member.modelComponent = openNodeComposedInferProvider({moon: runtime, selected: modelSelection,
      deferred: true, deferredGeneratedInput: prepareContent !== undefined});
    if (member === run) run.modelComponents = Object.freeze([member.modelComponent.provider]);
  }
}

// Only the existing complete dispatch/initialization retirement caller supplies
// this physical-cleanup observation. A terminal Run or settled Promise cannot.
export function finishInstalledEffectModelScope(run, originalRunCleanupComplete, checked) {
  if ((run.modelMembers === undefined ? run.modelScope === undefined : run.modelScopes === undefined) ||
      run.modelScopeFinished === true) return;
  if (run.modelScopeFinishing) fail('InstalledEffectModelScopeCleanupPending');
  const sameMembers = run.modelMembers, sameScopes = run.modelScopes;
  const sameScope = run.modelScope, sameParent = run.value, sameModel = run.model;
  const sameControl = run.publicationControl, sameDefinition = run.modelRunDefinition, sameFinish = run.finishModelScope;
  const sameRuntime = run.runtime, sameQuiesce = run.quiesce, sameRequest = run.request,
    sameOriginal = run.original, sameConstruction = run.controlConstruction, sameRetire = run.retireControlConstruction;
  const original = () => {
    if (run.modelMembers !== sameMembers || run.modelScopes !== sameScopes || run.modelScope !== sameScope || run.value !== sameParent || run.model !== sameModel ||
        run.publicationControl !== sameControl || run.modelRunDefinition !== sameDefinition || run.finishModelScope !== sameFinish ||
        run.runtime !== sameRuntime || run.quiesce !== sameQuiesce || run.request !== sameRequest ||
        run.original !== sameOriginal || run.controlConstruction !== sameConstruction || run.retireControlConstruction !== sameRetire) {
      fail('ForeignInstalledEffectModelScope');
    }
  };
  run.modelScopeFinishing = true;
  try {
    if (originalRunCleanupComplete === true && sameParent !== undefined) {
      // The actual constructor must stop before its SAME Core control backing
      // can settle. Scope census quiescence cannot acknowledge either child.
      if (sameConstruction !== undefined) {
        if (typeof sameRetire !== 'function') fail('InstalledEffectControlConstructionCleanupPending');
        const stopped = Reflect.apply(sameRetire, sameConstruction, []);
        original();
        if (stopped !== true) fail('InstalledEffectControlConstructionCleanupPending');
      }
      if (typeof sameQuiesce !== 'function') fail('InstalledEffectModelRuntimeUnavailable');
      checked(Reflect.apply(sameQuiesce, sameRuntime, [sameParent]));
      original();
    }
    const finishMember = member => {
      if (sameMembers !== undefined && member.modelScopeFinished === true) return true;
      const scope = member.modelScope, model = member.model, selected = member.modelSelection;
      const finished = member.modelRuntimeView !== undefined
        ? originalRunCleanupComplete === true && selected.finishTrustedRuntimeScope(
          scope, member.modelRuntimeView, model.compiled, sameDefinition, model.graph)
        : sameControl === undefined ? checked(Reflect.apply(sameFinish, sameRuntime,
          [scope, model.compiled, model.definition, model.graph, originalRunCleanupComplete]))
          : Reflect.apply(sameFinish, sameControl,
            [model.compiled, sameDefinition, model.graph, scope, originalRunCleanupComplete]);
      original();
      if (sameMembers !== undefined && (member.modelScope !== sameScopes?.[sameMembers.indexOf(member)] ||
          member.model !== sameModel.components[sameMembers.indexOf(member)])) fail('ForeignInstalledEffectModelScope');
      if (sameMembers !== undefined && finished === true) member.modelScopeFinished = true;
      return finished;
    };
    let finished;
    if (sameMembers !== undefined) {
      // Earlier members can remain pending until the last SAME group member
      // finishes; observe all before asking the existing owner for final ACK.
      for (const member of sameMembers) finishMember(member);
      finished = true;
      for (const member of sameMembers) if (finishMember(member) !== true) finished = false;
    } else finished = finishMember(run);
    if (finished !== true) fail('InstalledEffectModelScopeCleanupPending');
    run.modelScopeFinished = true;
  } finally {run.modelScopeFinishing = false;}
}

// Borrow the SAME early Request Scope when Local supplies the actual captured
// inputs. Its original read remains on this Run through failed construction;
// no late Scope, admission, bounds selection or independent Model Root exists.
export function installedEffectModelPreparation(run, publicationCapacity, assertCurrent) {
  if (run.modelMembers === undefined) return installedEffectModelMemberPreparation(run, run, publicationCapacity, assertCurrent);
  const members = run.modelMembers, scopes = run.modelScopes;
  const current = () => {
    assertCurrent();
    if (run.modelMembers !== members || run.modelScopes !== scopes || run.closed || run.modelScopeFinished ||
        !Array.isArray(scopes) || scopes.length !== members.length ||
        members.some((member, index) => member.modelScope !== scopes[index] || member.model !== run.model.components[index] ||
          member.modelSelection !== run.modelSelection.components[index])) fail('ForeignInstalledEffectModelScope');
  };
  current();
  if (run.modelPreparation !== undefined) return run.modelPreparation;
  const components = Object.freeze(members.map(member => Object.freeze({selection: member.modelSelection,
    component: member.modelComponent, ...installedEffectModelMemberPreparation(run, member, publicationCapacity, current)})));
  run.modelPreparation = Object.freeze({components,
    retain() {current(); for (const component of components) component.retain();},
    retire() {current(); for (const component of components) if (component.retire() !== true) return false; return true;}});
  return run.modelPreparation;
}

function installedEffectModelMemberPreparation(run, member, publicationCapacity, assertCurrent) {
  const model = member.model, control = run.publicationControl, definition = run.modelRunDefinition,
    scope = member.modelScope, parent = run.value, demand = member.modelDemand;
  const current = () => {
    assertCurrent();
    if (run.closed || member.model !== model || run.publicationControl !== control ||
        run.modelRunDefinition !== definition || member.modelScope !== scope || run.value !== parent ||
        member.modelDemand !== demand || run.modelScopeFinished || scope === undefined || control === undefined) {
      fail('ForeignInstalledEffectModelScope');
    }
  };
  current();
  if (member.modelPreparation !== undefined) return member.modelPreparation;
  const readWindow = run.runtime.clientProgramInstalledEffectModelReadWindow;
  if (typeof readWindow !== 'function' || typeof publicationCapacity !== 'function') {
    fail('InstalledEffectModelRuntimeUnavailable');
  }
  const window = Reflect.apply(readWindow, run.runtime, [demand]);
  if (!Array.isArray(window) || window.length !== 2 ||
      window.some(value => typeof value !== 'bigint' || value <= 0n)) fail('InvalidHostRuntimeResult');
  const retained = window[0], execution = window[1];
  const physical = member.modelSelection?.originalReadInstallation;
  const startup = physical === undefined ? undefined : inferOriginalReadStartupCapacity(physical);
  const fields = {control, compiled: model.compiled, runDefinition: definition, scope, publicationCapacity,
    readRetainedBytes: retained, readExecutionBytes: execution,
    modelRetainedBytes: startup?.modelRetainedBytes ?? retained,
    modelExecutionBytes: startup?.modelExecutionBytes ?? execution,
    ...(physical === undefined ? {} : {nodeInstallation: physical.nodeInstallation,
      metadataInstallation: physical,
      assertRuntimeCurrent() {
        current();
        member.modelSelection.assertTrustedRuntimeScope(scope, member.modelRuntimeView,
          model.compiled, definition, model.graph);
      }}),
  };
  const prepareRead = () => {
    current();
    if (Object.hasOwn(member, 'modelReadFailure')) throw member.modelReadFailure;
    if (member.modelPreparationRetired || !member.modelPreparationTaken || member.modelReadAttempted) fail('ForeignInstalledEffectModelScope');
    member.modelReadAttempted = true;
    try {
      member.modelRead = physical === undefined
        ? control.prepareCheckedClientInferOriginalRead(model.compiled, definition, model.graph, scope, fields)
        : control.prepareCheckedClientInferNodeReadLayout(
          model.compiled, definition, model.graph, scope, physical.nodeInstallation);
      return Object.freeze({...fields, read: member.modelRead});
    } catch (cause) {member.modelReadFailure = cause; throw cause;}
  };
  const view = Object.freeze({...fields,
    retain() {
      current();
      if (member.modelPreparationRetired || member.modelPreparationTaken || member.modelReadAttempted) fail('ForeignInstalledEffectModelScope');
      member.modelPreparationTaken = true;
    },
    prepareRead,
    restoreRead(input) {
      current();
      // This selects the saved-input constructor, not fresh input permission.
      // Core admits the nominal saved scope against this same Run/occurrence
      // before entering the one original consumer or allocating saved input.
      if (input?.savedScope === undefined ||
          typeof control.startCheckedClientOriginalRestoredComposedInferExecution !== 'function') {
        fail('InstalledEffectModelRuntimeUnavailable');
      }
      return prepareRead();
    },
    retire() {
      current();
      if (member.modelPreparationRetired) return true;
      retireNodeInferOriginalRead({control, compiled: model.compiled, runDefinition: definition,
        graph: model.graph, scope, read: member.modelRead});
      member.modelRead = undefined;
      member.modelPreparationRetired = true;
      return true;
    },
  });
  member.modelPreparation = view;
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
  const members = run.modelMembers, scopes = run.modelScopes;
  const modelSelection = run.modelSelection, component = run.modelMembers === undefined ? run.modelComponent : run.modelComponents, sourceInputs = run.sourceInputs,
    modelControl = run.publicationControl, modelDefinition = run.modelRunDefinition;
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition, members, scopes);
  const actualPlan = checked(Reflect.apply(readPlan, runtime, [parent, prepared, request]));
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition, members, scopes);
  if (actualPlan !== plan) fail('ForeignInstalledEffectManagedRun');
  assertCurrent();
  assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
    definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
    modelSelection, component, sourceInputs, modelControl, modelDefinition, members, scopes);
  return parent;
}

// Callback-free fences preserve the original Model Scope and cleanup lineage.
// Failure presence keeps even an original thrown undefined failed on retry.
function assertCurrentPlanRecord(run, runs, liveRuns, runtime, prepared, request, parent, plan, readPlan,
  definition, manager, selection, sourceProfile, model, demand, scope, admission, original, beginOperations,
  modelSelection, component, sourceInputs, modelControl, modelDefinition, members, scopes) {
  if (Object.hasOwn(run, 'failure')) throw run.failure;
  if (runs.get(prepared) !== run || !liveRuns.has(run) || run.closed ||
      run.preparationKind !== 'effect-plan' || run.runtime !== runtime ||
      run.prepared !== prepared || run.request !== request || run.value !== parent ||
      run.operationPlan !== plan || run.readPlan !== readPlan || run.definitionOriginal !== definition ||
      run.manager !== manager || run.selection !== selection || run.sourceProfile !== sourceProfile ||
      run.model !== model || run.modelDemand !== demand || run.modelScope !== scope ||
      run.admission !== admission || run.original !== original || run.beginOperations !== beginOperations ||
      run.operationsBegun !== true || run.modelSelection !== modelSelection || (members === undefined ? run.modelComponent : run.modelComponents) !== component ||
      run.sourceInputs !== sourceInputs || run.publicationControl !== modelControl ||
      run.modelRunDefinition !== modelDefinition || run.modelMembers !== members || run.modelScopes !== scopes ||
      members !== undefined && (!Object.isFrozen(members) || !Object.isFrozen(scopes) || members.length !== scopes.length ||
        members.some((member, index) => member.modelScope !== scopes[index] || member.model !== model.components[index] ||
          member.modelSelection !== modelSelection.components[index] || member.modelComponent?.provider !== component[index]))) fail('ForeignInstalledEffectManagedRun');
}
