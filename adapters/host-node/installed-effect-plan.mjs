// Pure composition inside the existing installed Effect owner. Original
// Core extents/Plan are DATA until the SAME Request completes and adopts them.
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {isEffectPreparationRefusal} from '../host-common/effect-preparation-result.mjs';
import {httpsCredentialResponseWindowBytes, httpsCredentialResponseHeaderByteLimit, httpsCredentialResponseReadQuantum, httpsCredentialAuthorizationPrefix}
  from '../site-node/https-credential-resource.mjs';
import {effectLedgerImplementationBounds} from './effect-ledger-implementation-bounds.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
const NativePromise = Promise;
const nativePromiseThen = Promise.prototype.then;
const fail = code => {throw Object.assign(new Error(code), {code});};
const text = value => typeof value === 'string' && value.length > 0;

// Fixed installed implementation metadata, not caller tuning or a Resource
// allowance. Capture the native method/receiver once; no fallback numeric table
// can silently disagree with the mapper/projector's original implementation.
export function captureInstalledStandardCreateLimits(providerMoon) {
  if (providerMoon === null || !['object', 'function'].includes(typeof providerMoon) ||
      nodeTypes.isProxy(providerMoon)) fail('InstalledStandardCreateRuntimeUnavailable');
  const method = Object.getOwnPropertyDescriptor(providerMoon, 'installedStandardCreateHttpLimits');
  if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function' ||
      nodeTypes.isProxy(method.value) || nodeTypes.isAsyncFunction(method.value)) {
    fail('InstalledStandardCreateRuntimeUnavailable');
  }
  const values = Reflect.apply(method.value, providerMoon, []);
  if (!Array.isArray(values) || nodeTypes.isProxy(values)) fail('InvalidInstalledStandardCreateLimits');
  const fields = Object.getOwnPropertyDescriptors(values);
  if (Reflect.ownKeys(fields).length !== 5 || fields.length?.value !== 4) {
    fail('InvalidInstalledStandardCreateLimits');
  }
  const names = ['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth'];
  const limits = {};
  for (let index = 0; index < names.length; index++) {
    const field = fields[index];
    if (!field || !Object.hasOwn(field, 'value') || !Number.isSafeInteger(field.value) ||
        field.value < 1 || field.value > 2147483647) fail('InvalidInstalledStandardCreateLimits');
    limits[names[index]] = field.value;
  }
  return Object.freeze(limits);
}

// One selected standard implementation recipe from original Native/Host/Site
// constructor facts. This is a private installing-code path, not user tuning,
// a new Provider framework, a Run admission or a replacement cleanup owner.
export function prepareInstalledStandardCreatePlanRecipe({moon, providerMoon, construction, credentialSite, limits,
  resourceTextUnits, requestInput = limits}) {
  if (construction === undefined || construction.check === null ||
      credentialSite?.construction === undefined ||
      !Number.isSafeInteger(resourceTextUnits) || resourceTextUnits < 0) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  const originalMethod = (receiver, name) => {
    if (receiver === null || !['object','function'].includes(typeof receiver) || nodeTypes.isProxy(receiver)) {
      fail('InstalledStandardCreateRuntimeUnavailable');
    }
    const field = Object.getOwnPropertyDescriptor(receiver, name);
    if (!field || !Object.hasOwn(field,'value') || typeof field.value !== 'function' ||
        nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) {
      fail('InstalledStandardCreateRuntimeUnavailable');
    }
    return (...args) => Reflect.apply(field.value, receiver, args);
  };
  const confirmed = construction.confirmation !== undefined;
  if (confirmed !== (construction.finalization !== undefined)) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  const profile = originalMethod(providerMoon, confirmed
    ? 'installedStandardCreateConfirmedConstructionProfile' : 'installedStandardCreateConstructionProfile');
  const captureField = Object.getOwnPropertyDescriptor(providerMoon, 'installedStandardDriverCaptureConstructionCapacity');
  const captureProfile = captureField === undefined ? undefined
    : originalMethod(providerMoon, 'installedStandardDriverCaptureConstructionCapacity');
  if (confirmed && captureProfile !== undefined) fail('InstalledStandardCreateConstructionUnavailable');
  const capacitiesFor = originalMethod(moon, captureProfile === undefined
    ? 'clientProgramInstalledStandardCreateRequestRecipeCapacities' : 'clientProgramInstalledStandardDriverRecipeCapacities');
  const extentFor = originalMethod(moon, 'clientProgramInstalledEffectOperationExtentFromCapacityPrepare');
  const captureFor = originalMethod(moon, captureProfile === undefined
    ? 'clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare' : 'clientProgramInstalledEffectCaptureRecipeExtentPrepare');
  const {write, check} = construction;
  const confirmation = construction.confirmation;
  if (confirmed && (check === undefined || confirmation.maxRequestBytes !== check.maxRequestBytes ||
      confirmation.maxResponseBytes !== check.maxResponseBytes)) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  const secret = credentialSite.construction;
  if (![write.maxRequestBytes,write.maxResponseBytes,limits.maxWireBytes,limits.maxNodes,limits.maxDepth,
    requestInput?.maxWireBytes,requestInput?.maxNodes,requestInput?.maxDepth,
    secret.limits?.maxSecretBytes,httpsCredentialResponseHeaderByteLimit,
    ...(check === undefined ? [] : [check.maxRequestBytes,check.maxResponseBytes])]
    .every(value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  // Immutable original metadata only. The issuer itself retains and consumes
  // these same scope/issuer fields; do not query policy or sample grant time.
  let units = BigInt(construction.metadataTextUnits) + BigInt(resourceTextUnits);
  for (const value of Object.values(secret.scope)) if (typeof value === 'string') units += BigInt(value.length);
  for (const value of Object.values(secret.issuer)) units += BigInt(value.length);
  const capacities = checked(capacitiesFor(profile(requestInput.maxWireBytes, requestInput.maxNodes, requestInput.maxDepth),
    ...(captureProfile === undefined ? [] : [captureProfile(limits.maxWireBytes,limits.maxNodes,limits.maxDepth,
      requestInput.maxWireBytes,requestInput.maxNodes,requestInput.maxDepth)]), limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
    requestInput.maxWireBytes,requestInput.maxNodes,requestInput.maxDepth,
    write.maxRequestBytes, write.maxResponseBytes, check?.maxRequestBytes ?? 0, check?.maxResponseBytes ?? 0,
    check?.beforeSend === true, secret.limits.maxSecretBytes, httpsCredentialAuthorizationPrefix.length,
    httpsCredentialResponseHeaderByteLimit,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    Math.max(effectLedgerImplementationBounds.maxNodes, effectLedgerImplementationBounds.maxOutcomeNodes),
    Math.max(effectLedgerImplementationBounds.maxDepth, effectLedgerImplementationBounds.maxOutcomeDepth),
    units, httpsCredentialResponseReadQuantum));
  if (!Array.isArray(capacities) || capacities.length !== (confirmed ? 8
    : (check === undefined ? 5 : 6) + (captureProfile === undefined ? 0 : 1))) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  const memberOperations = [Object.freeze({operation:write.operation,
    extent:checked(captureProfile === undefined ? captureFor(write.operation,[capacities[0],capacities[1]],
      limits.maxWireBytes,limits.maxNodes,limits.maxDepth) : captureFor(write.operation,capacities))})];
  const rowOperations = [Object.freeze({operation:write.operation,
    extent:checked(extentFor(write.operation,capacities[2],0n,false))})];
  const requestFinalization = confirmed ? Object.freeze({operationIndex: rowOperations.length}) : undefined;
  if (confirmed) rowOperations.push(Object.freeze({operation: write.operation,
    extent: checked(extentFor(write.operation, capacities[6], 0n, false))}));
  const credentialOperations = [];
  const physical = (phase, selected, capacity) => {
    const operationIndex = rowOperations.length;
    const transfer = BigInt(selected.maxRequestBytes) + httpsCredentialResponseWindowBytes(selected.maxResponseBytes);
    rowOperations.push(Object.freeze({operation:selected.operation,
      extent:checked(extentFor(selected.operation,capacity,transfer,true))}));
    credentialOperations.push(Object.freeze({phase,operationIndex,
      maxRequestBytes:selected.maxRequestBytes,maxResponseBytes:selected.maxResponseBytes}));
  };
  if (check !== undefined) {
    for (const phase of ['capture-check','apply-check','resume-check']) physical(phase,check,capacities[5]);
    if (check.beforeSend) physical('write-check',check,capacities[5]);
  }
  physical('write',write,capacities[3]);
  if (confirmed) {
    for (const phase of ['apply-confirm', 'resume-confirm']) physical(phase, confirmation, capacities[7]);
  }
  return captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations:Object.freeze(memberOperations),rowOperations:Object.freeze(rowOperations),
    controlsPerRow:capacities[4],captureConstruction:Object.freeze({operationIndex:0}),
    requestConstruction:Object.freeze({operationIndex:0}),credentialOperations:Object.freeze(credentialOperations),
    ...(requestFinalization === undefined ? {} : {requestFinalization}),
  }), rowOperations.length + memberOperations.length);
}

// The selected Host supplies original typed extents from its actual implementation
// recipe. Names/limits alone cannot select a Plan. Preserve those same opaque
// Core values; this view creates no capacity, admission or permission.
export function captureInstalledEffectPlanRecipe(recipe, maxOperations) {
  if (recipe === undefined) return undefined;
  if (recipe === null || typeof recipe !== 'object' || nodeTypes.isProxy(recipe)) fail('InvalidInstalledEffectPlanRecipe');
  if (!Number.isSafeInteger(maxOperations) || maxOperations < 1) fail('InvalidInstalledEffectPlanRecipe');
  const own = (value, names) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
        !Object.isFrozen(value)) fail('InvalidInstalledEffectPlanRecipe');
    const fields = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(fields).length !== names.length ||
        names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    return fields;
  };
  const fields = own(recipe, ['memberOperations', 'rowOperations',
    ...(Object.hasOwn(recipe, 'controlsPerRow') ? ['controlsPerRow'] : []),
    ...(Object.hasOwn(recipe, 'savedControlCodec') ? ['savedControlCodec'] : []),
    ...(Object.hasOwn(recipe, 'requestConstruction') ? ['requestConstruction'] : []),
    ...(Object.hasOwn(recipe, 'requestFinalization') ? ['requestFinalization'] : []),
    ...(Object.hasOwn(recipe, 'captureConstruction') ? ['captureConstruction'] : []),
    ...(Object.hasOwn(recipe, 'credentialOperations') ? ['credentialOperations'] : []),
    ...(Object.hasOwn(recipe, 'physicalWrite') ? ['physicalWrite'] : [])]);
  const operations = name => {
    const values = fields[name].value;
    if (!Array.isArray(values) || values.length > maxOperations) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const entries = own(values, ['length', ...Array.from({length: values.length}, (_, index) => String(index))]);
    return Object.freeze(Array.from({length: values.length}, (_, index) => {
      const entry = own(entries[String(index)].value, ['operation', 'extent']);
      const operation = entry.operation.value, extent = entry.extent.value;
      if (!text(operation) || extent === null || typeof extent !== 'object' ||
          nodeTypes.isProxy(extent)) fail('InvalidInstalledEffectPlanRecipe');
      return Object.freeze({operation, extent});
    }));
  };
  const memberOperations = operations('memberOperations'), rowOperations = operations('rowOperations');
  const controlsPerRow = fields.controlsPerRow?.value;
  if (fields.controlsPerRow !== undefined && (controlsPerRow === null || typeof controlsPerRow !== 'object' ||
      nodeTypes.isProxy(controlsPerRow))) fail('InvalidInstalledEffectPlanRecipe');
  let savedControlCodec;
  if (fields.savedControlCodec !== undefined) {
    const codec = own(fields.savedControlCodec.value, ['maxEntryBytes', 'fallbackCapacity']);
    const maxEntryBytes = codec.maxEntryBytes.value, fallbackCapacity = codec.fallbackCapacity.value;
    if (controlsPerRow === undefined || !Number.isSafeInteger(maxEntryBytes) || maxEntryBytes < 1 ||
        maxEntryBytes > effectLedgerImplementationBounds.maxEntryBytes || fallbackCapacity === null ||
        typeof fallbackCapacity !== 'object' || nodeTypes.isProxy(fallbackCapacity)) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    savedControlCodec = Object.freeze({maxEntryBytes, fallbackCapacity});
  }
  if (memberOperations.length + rowOperations.length === 0 ||
      memberOperations.length + rowOperations.length > maxOperations) fail('InvalidInstalledEffectPlanRecipe');
  let requestConstruction;
  if (fields.requestConstruction !== undefined) {
    const selected = own(fields.requestConstruction.value, ['operationIndex']);
    const operationIndex = selected.operationIndex.value;
    if (!Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= rowOperations.length) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    requestConstruction = Object.freeze({operationIndex});
  }
  let requestFinalization;
  if (fields.requestFinalization !== undefined) {
    const selected = own(fields.requestFinalization.value, ['operationIndex']);
    const operationIndex = selected.operationIndex.value;
    if (!Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= rowOperations.length ||
        requestConstruction === undefined || operationIndex === requestConstruction.operationIndex) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    requestFinalization = Object.freeze({operationIndex});
  }
  let captureConstruction;
  if (fields.captureConstruction !== undefined) {
    const selected = own(fields.captureConstruction.value, ['operationIndex',
      ...(Object.hasOwn(fields.captureConstruction.value, 'inputExtent') ? ['inputExtent'] : [])]);
    const operationIndex = selected.operationIndex.value;
    if (!Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= memberOperations.length) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const inputExtent = selected.inputExtent?.value;
    if (inputExtent !== undefined && (typeof inputExtent !== 'function' || nodeTypes.isProxy(inputExtent) ||
        nodeTypes.isAsyncFunction(inputExtent))) fail('InvalidInstalledEffectPlanRecipe');
    captureConstruction = Object.freeze({operationIndex, ...(inputExtent === undefined ? {} : {inputExtent})});
  }
  let credentialOperations;
  if (fields.credentialOperations !== undefined) {
    const values = fields.credentialOperations.value;
    // Five existing row phases plus three Describe/three target phases.
    if (!Array.isArray(values) || values.length < 1 || values.length > 11) fail('InvalidInstalledEffectPlanRecipe');
    const entries = own(values, ['length', ...Array.from({length: values.length}, (_, index) => String(index))]);
    const phases = new Set(), indexes = new Set([
      ...(requestConstruction === undefined ? [] : [`row:${requestConstruction.operationIndex}`]),
      ...(requestFinalization === undefined ? [] : [`row:${requestFinalization.operationIndex}`]),
      ...(captureConstruction === undefined ? [] : [`member:${captureConstruction.operationIndex}`]),
    ]);
    credentialOperations = Object.freeze(Array.from({length: values.length}, (_, index) => {
      const original = entries[String(index)].value;
      if (original === null || typeof original !== 'object' || nodeTypes.isProxy(original)) fail('InvalidInstalledEffectPlanRecipe');
      const entry = own(original, ['phase', 'operationIndex', 'maxRequestBytes', 'maxResponseBytes',
        ...(Object.hasOwn(original, 'perRow') ? ['perRow'] : []),
        ...(Object.hasOwn(original, 'responseExtent') ? ['responseExtent'] : [])]);
      const phase = entry.phase.value, operationIndex = entry.operationIndex.value,
        perRow = entry.perRow === undefined ? true : entry.perRow.value,
        maxRequestBytes = entry.maxRequestBytes.value, maxResponseBytes = entry.maxResponseBytes.value;
      const describe = ['capture-describe', 'apply-describe', 'resume-describe'].includes(phase);
      const row = ['capture-check', 'apply-check', 'resume-check', 'write-check', 'write', 'apply-confirm', 'resume-confirm',
        'capture-target', 'apply-target', 'resume-target'].includes(phase);
      const selected = perRow ? rowOperations : memberOperations;
      const key = `${perRow ? 'row' : 'member'}:${operationIndex}`;
      if (typeof perRow !== 'boolean' || (!describe && !row) || describe === perRow || phases.has(phase) ||
          !Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= selected.length ||
          indexes.has(key) || ![maxRequestBytes,maxResponseBytes].every(value =>
            Number.isSafeInteger(value) && value > 0)) {
        fail('InvalidInstalledEffectPlanRecipe');
      }
      const responseExtent = entry.responseExtent?.value;
      if (responseExtent !== undefined && (typeof responseExtent !== 'function' || nodeTypes.isProxy(responseExtent) ||
          nodeTypes.isAsyncFunction(responseExtent))) fail('InvalidInstalledEffectPlanRecipe');
      phases.add(phase); indexes.add(key);
      return Object.freeze({phase, operationIndex, maxRequestBytes, maxResponseBytes,
        ...(entry.perRow === undefined ? {} : {perRow}),
        ...(responseExtent === undefined ? {} : {responseExtent})});
    }));
    if (!phases.has('write')) fail('InvalidInstalledEffectPlanRecipe');
  }
  let physicalWrite;
  if (fields.physicalWrite !== undefined) {
    const selected = own(fields.physicalWrite.value, ['operationIndex', 'transferBytes']);
    const operationIndex = selected.operationIndex.value, transferBytes = selected.transferBytes.value;
    if (credentialOperations !== undefined || !Number.isSafeInteger(operationIndex) || operationIndex < 0 ||
        operationIndex >= rowOperations.length || operationIndex === requestConstruction?.operationIndex ||
        typeof transferBytes !== 'bigint' || transferBytes < 0n) fail('InvalidInstalledEffectPlanRecipe');
    physicalWrite = Object.freeze({operationIndex, transferBytes});
  }
  return Object.freeze({memberOperations, rowOperations,
    ...(savedControlCodec === undefined ? {} : {savedControlCodec}),
    ...(controlsPerRow === undefined ? {} : {controlsPerRow}),
    ...(requestConstruction === undefined ? {} : {requestConstruction}),
    ...(requestFinalization === undefined ? {} : {requestFinalization}),
    ...(captureConstruction === undefined ? {} : {captureConstruction}),
    ...(credentialOperations === undefined ? {} : {credentialOperations}),
    ...(physicalWrite === undefined ? {} : {physicalWrite})});
}

export function prepareInstalledEffectManagedPlan({moon, facts, inputs, unit, members, recipeFor}) {
  if (facts?.prepared === undefined || facts.identity === undefined ||
      inputs?.installedContracts === undefined ||
      typeof inputs.values !== 'string') {
    fail('InstalledEffectOperationDemandUnavailable');
  }
  // The installing Source supplies its original declaration/reader bounds;
  // Core constructs the acquisition once on this same checked Plan. Missing
  // inputs cannot select a zero-Source or ordinary-purpose replacement.
  const count = moon.clientProgramEffectAcquisitionCount(facts.prepared);
  const sources = inputs.sourceInputs;
  if (!Number.isSafeInteger(count) || count < 0 ||
      count !== 0 && sources === undefined || sources !== undefined &&
      (sources === null || typeof sources !== 'object' || !Object.isFrozen(sources) ||
       !['declarations', 'transferBytes', 'executionBytes'].every(name =>
         Array.isArray(sources[name]) && Object.isFrozen(sources[name]) && sources[name].length === count) ||
       sources.providers !== undefined && (!Array.isArray(sources.providers) ||
         !Object.isFrozen(sources.providers) || sources.providers.length !== count) ||
       typeof sources.queryContract !== 'string' || typeof sources.evidenceContract !== 'string' ||
       count !== 0 && (!sources.queryContract || !sources.evidenceContract) ||
       [...sources.transferBytes, ...sources.executionBytes].some(value => typeof value !== 'bigint' || value < 0n))) {
    fail('InstalledEffectPlanInputsUnavailable');
  }
  if (inputs.modelDemand !== undefined && (!Array.isArray(inputs.modelComponents) ||
      !Object.isFrozen(inputs.modelComponents) || inputs.modelComponents.length === 0)) {
    fail('InstalledEffectPlanInputsUnavailable');
  }
  const demands = members.map(member => {
    const recipe = recipeFor(member);
    if (recipe === undefined) fail('InstalledEffectOperationDemandUnavailable');
    const construct = recipe.controlsPerRow === undefined
      ? moon.clientProgramInstalledEffectOperationDemandPrepare
      : moon.clientProgramInstalledEffectOperationDemandWithControlsPrepare;
    if (typeof construct !== 'function') fail('InstalledEffectOperationDemandUnavailable');
    return checked(Reflect.apply(construct, moon, [facts.prepared, unit.stageIndex, member.effectId,
      recipe.memberOperations.map(entry => entry.extent), recipe.rowOperations.map(entry => entry.extent),
      ...(recipe.controlsPerRow === undefined ? [] : [recipe.controlsPerRow])]));
  });
  const model = inputs.modelDemand !== undefined, providers = sources?.providers;
  const content = inputs.contentPreparation;
  if (content !== undefined && (model || providers !== undefined || (sources?.declarations?.length ?? 0) !== 0)) {
    fail('UnsupportedInstalledContentEffectClosure');
  }
  const construct = content !== undefined ? moon.clientProgramInstalledEffectContentManagedPlanPrepare : model ? providers === undefined
    ? moon.clientProgramInstalledEffectModelManagedPlanPrepare
    : moon.clientProgramInstalledEffectModelManagedProviderPlanPrepare
    : providers !== undefined ? facts.queryTimePreparation === undefined
      ? moon.clientProgramInstalledEffectManagedProviderPlanPrepare
      : moon.clientProgramInstalledEffectManagedProviderPlanPrepareAtQueryTime
    : facts.queryTimePreparation === undefined
      ? moon.clientProgramInstalledEffectManagedPlanPrepare
      : moon.clientProgramInstalledEffectManagedPlanPrepareAtQueryTime;
  if (typeof construct !== 'function') fail('InstalledEffectPlanRuntimeUnavailable');
  const original = [facts.prepared, facts.identity,
    ...(content !== undefined || model || facts.queryTimePreparation === undefined ? [] : [facts.queryTimePreparation]),
    sources?.declarations ?? [], ...(providers !== undefined ? [providers] : []),
    sources?.queryContract ?? '', sources?.evidenceContract ?? '',
    sources?.transferBytes ?? [], sources?.executionBytes ?? [], inputs.installedContracts,
    inputs.values, inputs.fragment, inputs.ordered, demands,
    ...(model ? [inputs.modelDemand, inputs.modelComponents, facts.queryTimePreparation] : []),
    ...(content === undefined ? [] : [content, facts.queryTimePreparation])];
  // Empty query/evidence strings are unused arguments only for zero Sources;
  // they issue no query contract. Existing Core validates the checked graph.
  return checked(Reflect.apply(construct, moon, original));
}

// An internal child of the EXISTING capture retainer, not a cleanup/permission
// Owner. The selected implementation's native occurrence is debited before the
// constructor. Its output stays charged until the enclosing original route and
// request aliases have actually retired, including failed constructor prefixes.
// A driver may already own a Content-borrowing request child. Retain that
// SAME child under the existing constructor token; do not replace its prepare
// or physical cleanup with a second request or a successful-looking snapshot.
export function prepareInstalledEffectOwnedRequestChild({constructChild, ...options}) {
  if (typeof constructChild !== 'function' || options.construct !== undefined) {
    fail('InstalledEffectConstructorUnavailable');
  }
  let child, methods, retired = false, opening = false, invoking = false, stopping = false, flight;
  const requestsRetired = options.requestsRetired;
  if (typeof requestsRetired !== 'function') fail('InstalledEffectConstructorUnavailable');
  const captureMethods = names => {
    for (const name of names) {
      if (!Object.hasOwn(methods, name)) methods[name] = child[name];
      if (typeof methods[name] !== 'function') fail('InvalidInstalledRowRequestChild');
    }
  };
  const managed = prepareInstalledEffectRequestChild({...options,
    requestsRetired: () => retired && requestsRetired() === true,
    construct() {
      child = constructChild(); // Retain before even a fallible method getter.
      constructChild = undefined;
      if (child === null || !['object', 'function'].includes(typeof child)) {
        fail('InvalidInstalledRowRequestChild');
      }
      methods = {};
      captureMethods(['release', 'retry', 'status', 'prepare']);
      if (typeof Reflect.apply(methods.status, child, [])?.pending !== 'boolean') {
        fail('InvalidInstalledRowRequestChild');
      }
      if (stopping) fail('InstalledEffectRequestChildRetired');
      const result = Reflect.apply(methods.prepare, child, []);
      if (stopping) fail('InstalledEffectRequestChildRetired');
      return result;
    }});
  const drain = retry => {
    stopping = true;
    if (opening || invoking) return false;
    if (flight !== undefined) return flight;
    opening = true;
    try {
      flight = (async () => {
        if (!retired) {
          if (child !== undefined) {
            // Retry only still-unobserved methods on this same retained child;
            // successfully captured cleanup methods can never be replaced.
            if (methods === undefined) fail('InvalidInstalledRowRequestChild');
            captureMethods([retry ? 'retry' : 'release', 'status']);
            const release = retry ? methods.retry : methods.release;
            const result = await Reflect.apply(release, child, []);
            if (result === false || Reflect.apply(methods.status, child, [])?.pending !== false) return false;
          }
          child = methods = constructChild = undefined;
          retired = true;
        }
        return managed.release();
      })().finally(() => {flight = undefined;});
    } finally {opening = false;}
    return flight;
  };
  return Object.freeze({prepare() {
    if (stopping) fail('InstalledEffectRequestChildRetired');
    if (invoking) fail('InstalledEffectRequestChildReentrantPrepare');
    invoking = true;
    try {return managed.prepare();} finally {invoking = false;}
  }, checkOriginal: managed.checkOriginal,
    release: () => drain(false), retry: () => drain(true), status: managed.status});
}

export function prepareInstalledEffectRequestChild({run, memberIndex, rowIndex,
  operationIndex, operation, perRow = true, construct: originalConstruct, inputExtent: originalInputExtent, requestsRetired}) {
  if (run === undefined || typeof perRow !== 'boolean' || typeof originalConstruct !== 'function' ||
      typeof requestsRetired !== 'function') fail('InstalledEffectConstructorUnavailable');
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run;
  const retain = runtime?.clientProgramInstalledEffectOperationConstructionRetain;
  const begin = runtime?.clientProgramInstalledEffectOperationConstructionBegin;
  const retire = runtime?.clientProgramInstalledEffectOperationRetire;
  const complete = runtime?.clientProgramInstalledEffectOperationConstructionComplete;
  const beginInput = runtime?.clientProgramInstalledEffectOperationInputBegin;
  if (originalInputExtent !== undefined && (typeof originalInputExtent !== 'function' || typeof beginInput !== 'function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  if (![retain, begin, complete, retire, readPlan].every(method => typeof method === 'function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  const originalRecord = () => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.runtime !== runtime || run.value !== parent || run.prepared !== prepared ||
        run.request !== request || run.operationPlan !== plan || run.readPlan !== readPlan) {
      fail('ForeignInstalledEffectManagedRun');
    }
  };
  // Retained input/output backing precedes Source/Preview and its callbacks.
  // Temporary workspace is not reserved while this constructor is only held.
  originalRecord();
  let token = checked(Reflect.apply(retain, runtime,
    [parent, prepared, request, plan, memberIndex, perRow, operationIndex, rowIndex, operation]));
  let construct = originalConstruct, inputExtent = originalInputExtent;
  originalConstruct = originalInputExtent = undefined;
  let state = 'fresh';
  let preparing = false;
  let pendingConstructor;
  const drain = () => {
    if (state === 'retired') return true;
    if (preparing || requestsRetired() !== true) return false;
    // Clear this child's last input/callback references BEFORE the same native
    // body token may settle. The enclosing capture has already severed output.
    construct = inputExtent = undefined;
    if (checked(Reflect.apply(retire, runtime, [token, true])) !== true) return false;
    token = undefined;
    state = 'retired';
    return true;
  };
  return Object.freeze({
    prepare() {
      if (state === 'retired') fail('InstalledEffectRequestChildRetired');
      if (state !== 'fresh') fail('InstalledEffectRequestChildAlreadyPrepared');
      state = 'preparing';
      preparing = true;
      try {
        originalRecord();
        // Atomic Core entry grows this SAME original backing to its captured
        // extent and observes current once, before any constructor allocation.
        if (inputExtent === undefined) checked(Reflect.apply(begin, runtime, [token]));
        else {
          const extent = inputExtent();
          originalRecord();
          checked(Reflect.apply(beginInput, runtime, [token, extent]));
        }
        originalRecord();
        const value = construct();
        if (nodeTypes.isPromise(value)) {
          pendingConstructor = value;
          // Observe the native original before any replaceable public then.
          // Failed species/constructor observation rejects this wrapper, but
          // leaves the SAME unjoined task and its body in this child's custody.
          return new NativePromise((resolve, reject) => {
            const settled = () => {
              pendingConstructor = undefined;
              preparing = false;
              state = 'failed';
              reject(Object.assign(new Error('InstalledEffectConstructorNotSynchronous'),
                {code: 'InstalledEffectConstructorNotSynchronous'}));
            };
            Reflect.apply(nativePromiseThen, value, [settled, settled]);
          });
        }
        if (value !== null && (typeof value === 'object' || typeof value === 'function')) {
          pendingConstructor = value;
          // A foreign thenable or throwing accessor cannot certify settlement.
          // Do not start it merely to manufacture an asynchronous cleanup ACK.
          if (typeof value.then === 'function') fail('InstalledEffectConstructorNotSynchronous');
          pendingConstructor = undefined;
        }
        // Every call now executes its actual constructor. Member capture is
        // retained earlier and prepares only at its real recovery-entry work;
        // no placeholder may return that workspace before Source/Preview.
        originalRecord();
        checked(Reflect.apply(complete, runtime, [token]));
        originalRecord();
        state = 'prepared';
        preparing = false;
        return value;
      } catch (error) {
        if (pendingConstructor === undefined) preparing = false;
        state = 'failed';
        throw error;
      }
    },
    // Callback-free original-record fence after this child was retained.
    // This is not a current observation or an admission proof.
    checkOriginal: originalRecord,
    release: drain, retry: drain,
    status: () => Object.freeze({pending: state !== 'retired'}),
  });
}

// Internal physical sibling of the same capture child. The original Site binds
// an ALREADY-issued read/effect authorization; this never signs another grant.
// One selected HTTP body operation and its binary response reader share one
// native occurrence. Form reads and writes must select separate occurrences.
export function prepareInstalledEffectCredentialChild({run, memberIndex, rowIndex,
  operationIndex, operation, perRow = true, originalSite, originalAuthorization, useId, resource,
  purpose, runInvocationCid, dispatchRequestCid, maxRequestBytes, maxResponseBytes,
  assertCurrent, observeCurrent, requestsRetired, invoke: originalInvoke, responseExtent: originalResponseExtent}) {
  if (run === undefined || typeof perRow !== 'boolean' || ![originalInvoke, assertCurrent, observeCurrent, requestsRetired]
      .every(value => typeof value === 'function') || !text(useId) || !text(resource) ||
      !['read', 'target-read', 'effect'].includes(purpose) || !text(runInvocationCid) || !text(dispatchRequestCid) ||
      ![maxRequestBytes,maxResponseBytes].every(value => Number.isSafeInteger(value) && value > 0)) {
    fail('InvalidInstalledEffectCredentialOperation');
  }
  const own = (value, name) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) fail('InvalidInstalledEffectCredentialOperation');
    const field = Object.getOwnPropertyDescriptor(value,name);
    if (!field || !Object.hasOwn(field,'value')) fail('InvalidInstalledEffectCredentialOperation');
    return field.value;
  };
  const method = (value,name) => {const fn=own(value,name);if(typeof fn!=='function')fail('InstalledEffectCredentialOperationUnavailable');return fn;};
  let site=originalSite,authorization=originalAuthorization,invoke=originalInvoke,responseExtent=originalResponseExtent;
  let bind=method(site,'bindRunAcquisition'),readPurpose=method(site,'authorizationPurpose'),
    referenceCurrent=method(site,'referenceCurrent'),physical=method(site,'callResource');
  originalSite=originalAuthorization=originalInvoke=originalResponseExtent=undefined;
  const {runtime,value:parent,prepared,request,operationPlan:plan,readPlan}=run;
  const select=runtime?.clientProgramInstalledEffectManagedPlanOperation,
    isPhysical=runtime?.clientProgramInstalledEffectOperationExtentPhysical,
    transfer=runtime?.clientProgramInstalledEffectOperationExtentTransfer,
    responseBackingFits=runtime?.clientProgramInstalledEffectOperationResponseBackingFits,
    borrow=runtime?.clientProgramInstalledEffectOperationBorrow,
    start=runtime?.clientProgramInstalledEffectOperationStart,
    beginInput=runtime?.clientProgramInstalledEffectOperationInputBegin,
    charge=runtime?.clientProgramInstalledEffectOperationCharge,
    retire=runtime?.clientProgramInstalledEffectOperationRetire;
  if (![readPlan,select,isPhysical,transfer,responseBackingFits,borrow,start,charge,retire].every(value=>typeof value==='function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  if(responseExtent!==undefined&&(typeof responseExtent!=='function'||typeof beginInput!=='function')){
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  const originalRecord=()=>{
    const same=()=>run.closed!==true && run.runtime===runtime && run.value===parent && run.prepared===prepared &&
      run.request===request && run.operationPlan===plan && run.readPlan===readPlan;
    if(Object.hasOwn(run,'failure'))throw run.failure;
    if(!same())fail('ForeignInstalledEffectManagedRun');
  };
  const nativeCurrent=()=>{
    originalRecord();
    if(checked(Reflect.apply(readPlan,runtime,[parent,prepared,request]))!==plan)fail('ForeignInstalledEffectManagedRun');
    originalRecord();
  };
  originalRecord();
  try {
    // These original extent projections inspect immutable Plan DATA only.
    // The atomic borrow below owns the successful current/reservation boundary.
    const extent=checked(Reflect.apply(select,runtime,[plan,memberIndex,perRow,operationIndex,operation]));
    const declaredTransfer=Reflect.apply(transfer,runtime,[extent]);
    if(Reflect.apply(isPhysical,runtime,[extent])!==true || typeof declaredTransfer!=='bigint' ||
        declaredTransfer<BigInt(maxRequestBytes)+httpsCredentialResponseWindowBytes(maxResponseBytes)) {
      fail('InsufficientInstalledEffectOperationTransfer');
    }
    if(maxResponseBytes>2147483647 || !Number.isSafeInteger(httpsCredentialResponseHeaderByteLimit) ||
        httpsCredentialResponseHeaderByteLimit<1 || httpsCredentialResponseHeaderByteLimit>2147483647 ||
        Reflect.apply(responseBackingFits,runtime,[extent,maxResponseBytes,httpsCredentialResponseHeaderByteLimit,httpsCredentialResponseReadQuantum])!==true) {
      fail('InsufficientInstalledEffectResponseBacking');
    }
  } catch(error) {
    // No borrow follows a metadata refusal. Preserve its original current and
    // Unknown precedence, including an original failure whose value is undefined.
    nativeCurrent();
    throw error;
  }
  originalRecord();
  let token=checked(Reflect.apply(borrow,runtime,[parent,prepared,request,plan,memberIndex,perRow,operationIndex,rowIndex,operation]));
  let state='fresh',preparing=false,closing=false,accountingFailed=false,callStarted=false;
  let acquisition,closeBinding,boundCredential,bindingClosed=false,pendingFence,fenceFlight,pendingClose,closeFlight,physicalFlight;
  const retainFence=value=>{
    if(value===null||!['object','function'].includes(typeof value))return;
    pendingFence=value;
    if(nodeTypes.isPromise(value)){
      fenceFlight=new NativePromise(resolve=>{
        const settled=()=>{pendingFence=undefined;resolve();};
        try{Reflect.apply(nativePromiseThen,value,[settled,settled]);}
        catch{resolve();} // Observation failure is not settlement of the retained task.
      });
    }else if(typeof value.then!=='function')pendingFence=undefined;
  };
  const check=()=>{
    nativeCurrent();
    if(pendingFence!==undefined)fail('InvalidInstalledEffectCurrentFence');
    const returned=assertCurrent();
    if(returned!==undefined){retainFence(returned);fail('InvalidInstalledEffectCurrentFence');}
    const current=Reflect.apply(referenceCurrent,site,[]);
    if(current!==true){retainFence(current);fail('InstalledEffectCredentialNotCurrent');}
    nativeCurrent();
  };
  const observe=async()=>{check();await observeCurrent();check();};
  const chargeBytes=bytes=>{
    try{checked(Reflect.apply(charge,runtime,[token,bytes]));}
    catch(error){accountingFailed=true;throw error;}
  };
  const callResource=options=>{
    if(closing||callStarted)fail('InstalledEffectOperationAlreadyUsed');
    check();
    const scope=authorization.scope;
    if(options.grant!==authorization.grant || options.useId!==useId ||
        credentialInvocationBindingKeys.some(key=>options.scope?.[key]!==scope[key]) ||
        options.scope?.operation!==operation || options.binding!==boundCredential.binding ||
        options.control!==boundCredential.control || options.journal!==boundCredential.journal ||
        options.resolveSecret!==boundCredential.resolveSecret || options.maxRequestBytes!==maxRequestBytes ||
        options.maxResponseBytes!==maxResponseBytes || !(options.operations instanceof Map) ||
        nodeTypes.isProxy(options.operations) || options.operations.size!==1)fail('ForeignInstalledEffectCredentialOperation');
    const selected=Map.prototype.get.call(options.operations,operation);
    if(selected===undefined || !Object.isFrozen(selected) || nodeTypes.isProxy(selected))fail('InvalidInstalledEffectHttpOperation');
    const fields=Object.getOwnPropertyDescriptors(selected);
    if(Reflect.ownKeys(fields).some(name=>!['method','path','body','headers','responseHeaders'].includes(name)||!Object.hasOwn(fields[name],'value'))) {
      fail('UnsupportedInstalledEffectHttpRepresentation');
    }
    const body=fields.body?.value;
    if(body!==undefined&&typeof body!=='string')fail('UnsupportedInstalledEffectHttpRepresentation');
    const bytes=body===undefined?0:Buffer.byteLength(body);
    if(bytes>maxRequestBytes)fail('InstalledEffectRequestByteLimit');
    callStarted=true;
    chargeBytes(BigInt(bytes));
    // Preserve exact original method/path/headers/body/CID semantics. The
    // existing Resource still performs its own current/transport validation.
    const result=Reflect.apply(physical,site,[{...options,operations:new Map([[operation,selected]]),
      observeResponseBytes:bytes=>{chargeBytes(BigInt(bytes));}}]);
    // Join the SAME call even if a provider omits its await or throws after
    // starting it. The envelope keeps rejection handled without discarding it;
    // prepare below still reports it when no earlier failure was thrown.
    // Grow before the SAME response escapes to any provider decoder. The
    // received body remains in this already-retained physical child's custody
    // if quantity selection, current or resize refuses.
    const response = responseExtent === undefined ? result : Promise.resolve(result).then(value=>{
      originalRecord();
      if(!Buffer.isBuffer(value?.body)&&!(value?.body instanceof Uint8Array))fail('InvalidInstalledEffectResponseBody');
      const extent=responseExtent(value.body.byteLength);
      originalRecord();
      checked(Reflect.apply(beginInput,runtime,[token,extent]));
      originalRecord();return value;
    });
    physicalFlight=Promise.resolve(response).then(value=>({ok:true,value}),error=>({ok:false,error}));
    return response;
  };
  const drain=()=>{
    if(state==='retired')return true;
    closing=true;
    if(closeFlight!==undefined)return closeFlight;
    if(pendingFence!==undefined||pendingClose!==undefined)return false;
    if(acquisition!==undefined&&!bindingClosed){
      if(closeBinding===undefined)return false;
      const result=Reflect.apply(closeBinding,acquisition,[]);
      if(result==='closed')bindingClosed=true;
      else if(result!=='pending'){
        if(result!==null&&['object','function'].includes(typeof result))pendingClose=result;
        if(nodeTypes.isPromise(result)){
          closeFlight=new NativePromise(resolve=>{
            const settled=()=>{pendingClose=undefined;closeFlight=undefined;resolve(false);};
            try{Reflect.apply(nativePromiseThen,result,[settled,settled]);}
            catch{resolve(false);} // Keep the unjoined original; never infer a close ACK.
          });
          return closeFlight;
        }
        fail('InvalidInstalledEffectBindingCleanup');
      }
    }
    if(preparing||accountingFailed||(acquisition!==undefined&&!bindingClosed)||requestsRetired()!==true)return false;
    invoke=responseExtent=authorization=acquisition=boundCredential=closeBinding=bind=readPurpose=referenceCurrent=physical=site=physicalFlight=undefined;
    if(checked(Reflect.apply(retire,runtime,[token,true]))!==true)return false;
    token=undefined;state='retired';return true;
  };
  return Object.freeze({
    async prepare(){
      if(state!=='fresh'||closing)fail('InstalledEffectOperationAlreadyPrepared');
      state='preparing';preparing=true;
      let primaryFailed=false;
      try{
        check();
        const originalPurpose=Reflect.apply(readPurpose,site,[authorization]),scope=authorization?.scope;
        if(originalPurpose?.kind!==purpose||originalPurpose.resource!==resource||scope?.operation!==operation||
            scope.runInvocationCid!==runInvocationCid||scope.dispatchRequestCid!==dispatchRequestCid||
            scope.runtimeBundleCid!==site.runtimeBundleCid||scope.connectorRegistration!==site.connectorRegistration||
            scope.connectorRevision!==site.connectorRevision)fail('ForeignInstalledEffectAuthorizationPurpose');
        // The exact issuer's synchronous factory performs no physical request;
        // the existing capture already retained this child before entry.
        acquisition=Reflect.apply(bind,site,[authorization,{assertCurrent:check,observeCurrent:observe}]);
        if(acquisition===null||typeof acquisition!=='object'||nodeTypes.isProxy(acquisition))fail('InvalidInstalledEffectCredentialBinding');
        closeBinding=method(acquisition,'close');
        boundCredential=own(acquisition,'credential');
        if(boundCredential===null||typeof boundCredential!=='object')fail('InvalidInstalledEffectCredentialBinding');
        check();
        checked(Reflect.apply(start,runtime,[token]));
        const result=await invoke({authorization:Object.freeze({...authorization,useId}),credential:boundCredential,callResource});
        if(!callStarted)fail('InstalledEffectPhysicalOperationUnavailable');
        check();state='prepared';return result;
      }catch(error){primaryFailed=true;state='failed';throw error;}
      finally{
        const observed=physicalFlight===undefined?undefined:await physicalFlight;
        if(fenceFlight!==undefined){await fenceFlight;fenceFlight=undefined;}
        preparing=false;
        if(!primaryFailed&&observed?.ok===false){state='failed';throw observed.error;}
      }
    },
    release:drain,retry:drain,status:()=>Object.freeze({pending:state!=='retired'}),
  });
}


// The existing Run owns this synchronous control frame, its original methods
// and any invalid borrowed task. This is not a grant, new owner or caller fee.
export function prepareInstalledEffectControlConstruction(run) {
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run ?? {};
  const begin = runtime?.clientProgramInstalledEffectOperationControlConstructionBegin;
  const complete = runtime?.clientProgramInstalledEffectOperationControlConstructionComplete;
  const beginInput = runtime?.clientProgramInstalledEffectOperationControlInputBegin;
  const codecBegin = runtime?.clientProgramInstalledEffectOperationLedgerCodecBegin;
  const codecComplete = runtime?.clientProgramInstalledEffectOperationLedgerCodecComplete;
  const hasHostInput = runtime?.clientProgramInstalledEffectManagedPlanHasHostInput;
  const retainInventory = runtime?.clientProgramInstalledEffectCapturedInputInventoryRetain;
  const parseJson = JSON.parse;
  const jsonReceiver = JSON;
  if (![begin, complete, readPlan].every(method => typeof method === 'function') || parent === undefined || plan === undefined) {
    fail('InstalledEffectControlRuntimeUnavailable');
  }
  let working = false, codecWorking = false, failed = false, retired = false, primary, pending, work;
  const sameRecord = () => !run.closed && run.runtime === runtime && run.value === parent &&
    run.prepared === prepared && run.request === request && run.operationPlan === plan &&
    run.readPlan === readPlan && run.controlConstruction === work;
  const originalRecord = () => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (!sameRecord()) fail('ForeignInstalledEffectManagedRun');
  };
  const retainInvalid = value => {
    if (value === null || !['object', 'function'].includes(typeof value)) return;
    pending = value;
    const settled = () => {pending = undefined; run.selecting = false;};
    if (nodeTypes.isPromise(value)) {
      // Native original first. A species/join refusal leaves the same task
      // unobserved and the existing Run retirement latch held, never an ACK.
      Reflect.apply(nativePromiseThen, value, [settled, settled]);
      fail('InvalidInstalledEffectControlConstruction');
    }
    const then = value.then;
    if (typeof then !== 'function') {pending = undefined; return;}
    const joined = new NativePromise((yes, no) => Reflect.apply(then, value, [yes, no]));
    Reflect.apply(nativePromiseThen, joined, [settled, settled]);
    fail('InvalidInstalledEffectControlConstruction');
  };
  const invoke = (receiver, method, args, inputWire) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    if (typeof method !== 'function' || !Array.isArray(args)) fail('InvalidInstalledEffectControlConstruction');
    working = true;
    let invoking = false;
    // The existing parent retirement already refuses this latch. Retain it
    // through native-task settlement if an invalid asynchronous result escapes.
    run.selecting = true;
    try {
      originalRecord();
      checked(Reflect.apply(inputWire === undefined ? begin : beginInput, runtime,
        [parent, prepared, request, plan, ...(inputWire === undefined ? [] : [inputWire])]));
      originalRecord();
      invoking = true;
      const value = Reflect.apply(method, receiver, args);
      invoking = false;
      if (failed) throw primary;
      retainInvalid(value);
      originalRecord();
      checked(Reflect.apply(complete, runtime, [parent, prepared, request, plan]));
      originalRecord();
      return value;
    } catch (cause) {
      if (invoking && !failed && pending === undefined && !codecWorking &&
          isEffectPreparationRefusal(cause)) {
        // This observed semantic refusal is the synchronous projector's
        // original DATA result. Its retained output stays on the SAME token;
        // only a successful original completion returns constructor scratch.
        // Keep the error for the existing Ledger/CAS/no-send decision outside
        // this frame. It grants neither a terminal Run nor physical cleanup.
        try {
          originalRecord();
          checked(Reflect.apply(complete, runtime, [parent, prepared, request, plan]));
          originalRecord();
        } catch (completionFailure) {
          // Scratch retirement is a separate result. Preserve even a thrown
          // undefined alongside the original refusal; the aggregate is NOT
          // marked as a completed semantic result and keeps this frame failed.
          failed = true;
          primary = Object.assign(new AggregateError([cause, completionFailure],
            'InstalledEffectControlConstructionPending', {cause}),
          {code: 'InstalledEffectControlConstructionPending',
            primaryFailure: cause, cleanupPending: true});
          throw primary;
        }
        throw cause;
      }
      failed = true; primary = cause;
      // Failed-prefix workspace remains on the SAME Core control reservation.
      throw cause;
    } finally {
      working = false;
      if (pending === undefined) run.selecting = false;
    }
  };
  work = (receiver, method, args) => invoke(receiver, method, args);
  // Only the original Ledger invokes this nested synchronous seam. The outer
  // control frame keeps its full Receipt/Grant/projector allowance and output
  // holders; no Preview one-use identity or physical occurrence is reused.
  const ledgerCodec = (receiver, method, args, wire, nodes = 512, depth = 16) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (!working || !run.selecting || codecWorking) fail('InstalledEffectControlConstructionPending');
    if (typeof method !== 'function' || !Array.isArray(args) ||
        wire !== undefined && typeof wire !== 'string' ||
        !Number.isSafeInteger(nodes) || nodes < 1 || nodes > 4096 ||
        !Number.isSafeInteger(depth) || depth < 1 || depth > 32 ||
        typeof codecBegin !== 'function' || typeof codecComplete !== 'function') {
      fail('InstalledEffectControlRuntimeUnavailable');
    }
    codecWorking = true;
    try {
      originalRecord();
      checked(Reflect.apply(codecBegin, runtime, [parent, prepared, request, plan, wire, nodes, depth]));
      originalRecord();
      const value = Reflect.apply(method, receiver, args);
      if (failed) throw primary;
      retainInvalid(value);
      originalRecord();
      checked(Reflect.apply(codecComplete, runtime, [parent, prepared, request, plan]));
      originalRecord();
      return value;
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally { codecWorking = false; }
  };
  const parsePreview = wire => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    originalRecord();
    if (typeof wire !== 'string' || typeof hasHostInput !== 'function') {
      fail('InstalledEffectControlRuntimeUnavailable');
    }
    // Other installed recipes retain their unchanged fixed parser envelope.
    // Only the typed opted-in Plan can refine this existing control token.
    const selected = Reflect.apply(hasHostInput, runtime, [plan]);
    if (typeof selected !== 'boolean') fail('InvalidHostRuntimeResult');
    if (!selected) {
      originalRecord();
      return Reflect.apply(parseJson, jsonReceiver, [wire]);
    }
    if (typeof beginInput !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    return invoke(jsonReceiver, parseJson, [wire], wire);
  };
  const retainInputs = inputs => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    if (typeof retainInventory !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    working = true;
    run.selecting = true;
    try {
      originalRecord();
      const result = Reflect.apply(retainInventory, runtime, [parent, prepared, request, plan, inputs]);
      retainInvalid(result);
      checked(result);
      originalRecord();
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally {
      working = false;
      if (pending === undefined) run.selecting = false;
    }
  };
  const retire = () => {
    if (retired) return true;
    if (!sameRecord() || run.retireControlConstruction !== retire) fail('ForeignInstalledEffectManagedRun');
    if (working || pending !== undefined || run.selecting) return false;
    // Actual complete dispatch retirement calls this before returning its
    // Core control backing. A retained Error may itself keep a heavy prefix.
    primary = undefined;
    retired = true;
    return true;
  };
  return Object.freeze(Object.assign(work, {retire, parsePreview, ledgerCodec, retainInputs}));
}

// A composed generic owner keeps its original codec and full control quote.
export function installedEffectSavedControlEntryLimit(recipes) {
  return Math.max(...recipes.map(recipe => recipe?.savedControlCodec?.maxEntryBytes ??
    effectLedgerImplementationBounds.maxEntryBytes));
}
export function installedEffectRecipeForControlEntryLimit(recipe, maxEntryBytes) {
  return recipe?.savedControlCodec !== undefined && maxEntryBytes > recipe.savedControlCodec.maxEntryBytes
    ? Object.freeze({...recipe, controlsPerRow: recipe.savedControlCodec.fallbackCapacity}) : recipe;
}
