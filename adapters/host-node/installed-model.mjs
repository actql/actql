// Static ModelTask registration shares the installed checker composition.
// This metadata is neither a provider registration nor an egress grant. The
// common execution owner must separately admit dependencies and authority.
import {runtimeField, runtimePair} from '../host-common/compiler-binding.generated.mjs';
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {retainInferOriginalReadInstallation, retainInferOriginalReadRecipe} from './infer-original-installation.mjs';
import {snapshotModelRawCaptureSelection} from './infer-raw-selection.mjs';
import {types as nodeTypes} from 'node:util';

const modelExecutionAbsences = new WeakMap();
const originalArrayIterator = Array.prototype[Symbol.iterator];
const originalArrayFind = Array.prototype.find;

// Consume this reader's exact synchronous absence once. A copied exception,
// another Prepared/installation/occurrence or a callback throw is no proof.
export function consumeInstalledModelExecutionAbsence(error, prepared, installation, occurrence) {
  const original = modelExecutionAbsences.get(error);
  modelExecutionAbsences.delete(error);
  return original !== undefined && original.prepared === prepared &&
    original.installation === installation && original.occurrence === occurrence;
}

// These are aliases in the existing installation, not another Provider
// registry. A candidate supplies configuration DATA only; the physical entry
// must later adopt that same original through installModelProviders.
const defaultsPreparations = new WeakMap();
const preparedRegistrations = new WeakMap();
const installedDefaults = new WeakMap();

function checkInstallation(installation) {
  if (installation === null || typeof installation !== 'object' ||
      Array.isArray(installation) ||
      Object.keys(installation).some(key =>
        !['environmentWire', 'executionContracts', 'dependencyBodies'].includes(key)) ||
      typeof installation.environmentWire !== 'string') {
    throw new TypeError('InvalidInstalledModelConfiguration');
  }
  const entries = installation.executionContracts ?? [];
  if (!Array.isArray(entries) || entries.length > 128) {
    throw new TypeError('InvalidInstalledModelExecutionConfiguration');
  }
  const tasks = new Set();
  for (const entry of entries) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join(',') !== 'bodyWire,cid,modelTaskCid' ||
        typeof entry.bodyWire !== 'string' ||
        typeof entry.cid !== 'string' ||
        typeof entry.modelTaskCid !== 'string' ||
        tasks.has(entry.modelTaskCid)) {
      throw new TypeError('InvalidInstalledModelExecutionConfiguration');
    }
    tasks.add(entry.modelTaskCid);
  }
  const bodies = installation.dependencyBodies ?? [];
  if (!Array.isArray(bodies) || bodies.length > 384) {
    throw new TypeError('InvalidInstalledModelDependencyConfiguration');
  }
  const references = new Set();
  for (const entry of bodies) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join(',') !== 'bodyWire,cid' ||
        typeof entry.bodyWire !== 'string' || typeof entry.cid !== 'string' ||
        references.has(entry.cid)) {
      throw new TypeError('InvalidInstalledModelDependencyConfiguration');
    }
    references.add(entry.cid);
  }
  return entries;
}

// Bound physical retention of operator-supplied nonsecret originals. These
// envelope checks do not admit a canonical identity or a provider binding;
// the common Model owner must admit the originals before durable execution.
function retainProviderBindingOriginals(value) {
  if (value === undefined) return undefined;
  const fields = ['configuration', 'configurationContract', 'installationRevision'];
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
  }
  const keys = Object.keys(value).sort();
  if (keys.length !== fields.length || keys.some((key, index) => key !== fields[index])) {
    throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
  }
  const originals = {};
  for (const name of fields) {
    const original = value[name];
    if (original === null || typeof original !== 'object' || Array.isArray(original)) {
      throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
    }
    const originalKeys = Object.keys(original).sort();
    if (originalKeys.length !== 2 || originalKeys[0] !== 'cid' || originalKeys[1] !== 'wire') {
      throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
    }
    const wire = original.wire, cid = original.cid;
    if (typeof wire !== 'string' || wire.length === 0 ||
        Buffer.byteLength(wire) > 256 * 1024 ||
        typeof cid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(cid)) {
      throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
    }
    originals[name] = Object.freeze({wire, cid});
  }
  return Object.freeze(originals);
}

// Retain exactly the values inspected here. Original Host configuration
// getters keep their existing acceptance; neither a second get nor a spread
// after validation may substitute different amounts. This issues no capacity.
function retainModelQuantityCapacity(capacity) {
  if (capacity === undefined) return undefined;
  if (capacity === null || typeof capacity !== 'object') {
    throw new TypeError('InvalidInstalledModelQuantityCapacity');
  }
  const keys = Object.keys(capacity).sort();
  if (keys.length !== 2 || keys[0] !== 'limits' || keys[1] !== 'perAttempt') {
    throw new TypeError('InvalidInstalledModelQuantityCapacity');
  }
  const limitsSource = capacity.limits, perAttemptSource = capacity.perAttempt;
  if ([limitsSource, perAttemptSource].some(amount => {
    if (amount === null || typeof amount !== 'object') return true;
    const amountKeys = Object.keys(amount).sort();
    return amountKeys.length !== 3 || amountKeys[0] !== 'costUnits' ||
      amountKeys[1] !== 'durationMs' || amountKeys[2] !== 'tokens';
  })) {
    throw new TypeError('InvalidInstalledModelQuantityCapacity');
  }
  const limits = {tokens: limitsSource.tokens, costUnits: limitsSource.costUnits,
    durationMs: limitsSource.durationMs};
  const perAttempt = {tokens: perAttemptSource.tokens, costUnits: perAttemptSource.costUnits,
    durationMs: perAttemptSource.durationMs};
  if ([limits, perAttempt].some(amount => Object.values(amount).some(value =>
    typeof value !== 'bigint' || value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER)))) {
    throw new TypeError('InvalidInstalledModelQuantityCapacity');
  }
  return Object.freeze({limits: Object.freeze(limits), perAttempt: Object.freeze(perAttempt)});
}

// These are bounded DATA-reader limits, not a capacity reservation. Snapshot
// before Core calls; a later getter cannot replace the bounds used for the
// same retained configuration. Actual Host startup still owns this workspace.
function retainModelDefaultsLimits(value) {
  const fields = ['maxBytes', 'maxDepth', 'maxMembers', 'maxNodes', 'maxWork'];
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('InvalidInstalledModelDefaultsLimits');
  }
  const keys = Object.keys(value).sort();
  if (keys.length !== fields.length || keys.some((key, index) => key !== fields[index])) {
    throw new TypeError('InvalidInstalledModelDefaultsLimits');
  }
  const snapshot = {};
  for (const key of fields) {
    const amount = value[key];
    if (!Number.isSafeInteger(amount) || amount < 0 || amount > 2147483647) {
      throw new TypeError('InvalidInstalledModelDefaultsLimits');
    }
    snapshot[key] = amount;
  }
  return Object.freeze(snapshot);
}

function modelDefaultsCallbacks(moon) {
  return Object.freeze({reader: moon.clientProgramReadInstalledModelDefaults,
    resolver: moon.clientProgramResolveInstalledModelDefaults,
    bindingReader: moon.clientProgramInstalledModelDefaultsBinding,
    usageReader: moon.clientProgramInstalledModelDefaultsUsage});
}

function modelDefaultsResolver(moon, providerId, bindingOriginals, assertCurrent, receiver,
  {reader, resolver, bindingReader, usageReader} = modelDefaultsCallbacks(moon)) {
  let original, bounds, readFailure;
  return function resolveTaskDefaults(selectedModel, taskMaxOutputTokens, limits) {
    if (this !== receiver()) {
      throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
        {code: 'InstalledModelDefaultsForeignOriginal'});
    }
    if (typeof assertCurrent !== 'function' || bindingOriginals === undefined ||
        ![reader, resolver, bindingReader, usageReader].every(value => typeof value === 'function')) {
      throw Object.assign(new Error('InstalledModelDefaultsUnavailable'),
        {code: 'InstalledModelDefaultsUnavailable'});
    }
    assertCurrent();
    const nextBounds = retainModelDefaultsLimits(limits);
    if (selectedModel !== undefined && typeof selectedModel !== 'string' ||
        taskMaxOutputTokens !== undefined && typeof taskMaxOutputTokens !== 'bigint') {
      throw new TypeError('InvalidInstalledModelDefaultsSelection');
    }
    if (bounds !== undefined && Object.keys(nextBounds).some(key => nextBounds[key] !== bounds[key])) {
      throw Object.assign(new Error('InstalledModelDefaultsLimitsChanged'),
        {code: 'InstalledModelDefaultsLimitsChanged'});
    }
    if (bounds === undefined) {
      bounds = nextBounds;
      try {
        original = checked(Reflect.apply(reader, moon, [providerId,
          bindingOriginals.installationRevision.wire, bindingOriginals.configurationContract.wire,
          bindingOriginals.configuration.wire, bounds.maxBytes, bounds.maxNodes, bounds.maxDepth,
          bounds.maxMembers, bounds.maxWork]));
        if (original === undefined || original === null) {
          throw Object.assign(new Error('InvalidHostRuntimeResult'), {code: 'InvalidHostRuntimeResult'});
        }
      } catch (cause) {
        readFailure = Object.freeze({cause});
      }
    }
    if (readFailure !== undefined) throw readFailure.cause;
    assertCurrent();
    const binding = retainAdmittedProviderBinding(moon, providerId, bindingOriginals,
      Reflect.apply(bindingReader, moon, [original]));
    const resolved = checked(Reflect.apply(resolver, moon,
      [original, selectedModel, taskMaxOutputTokens, bounds.maxWork]));
    const usage = Reflect.apply(usageReader, moon, [original]);
    const readUsage = Object.freeze({bytes: runtimeField(usage, 0),
      nodes: runtimeField(usage, 1), work: runtimeField(usage, 2)});
    assertCurrent();
    return Object.freeze({value: original, resolved, binding, readUsage});
  };
}

// Prepare Task DATA before a Task-specific physical assembler needs its CID.
// No Provider, dummy invoke, resource profile, permission or send is issued.
// The Host supplies the actual original configuration and current predicate.
export function prepareInstalledModelProviderDefaults(moon, providerId, bindingOriginals,
  {assertCurrent} = {}) {
  if (typeof providerId !== 'string' || !providerId || typeof assertCurrent !== 'function') {
    throw new TypeError('InvalidInstalledModelDefaultsPreparation');
  }
  const originals = retainProviderBindingOriginals(bindingOriginals);
  if (originals === undefined) {
    throw Object.assign(new Error('InstalledModelDefaultsUnavailable'),
      {code: 'InstalledModelDefaultsUnavailable'});
  }
  let view, adoptedCurrent, spent = false;
  const check = () => {
    if (assertCurrent() !== undefined) {
      throw new TypeError('InvalidInstalledModelDefaultsCurrentPredicate');
    }
    adoptedCurrent?.();
  };
  check();
  const resolveTaskDefaults = modelDefaultsResolver(moon, providerId, originals, check, () => view);
  const state = {moon, providerId, originals, check,
    adopt(runtime, id, source, current, installationCurrent) {
      check();
      if (runtime !== moon || id !== providerId || source !== originals || spent ||
          typeof current !== 'function' || installationCurrent !== assertCurrent) {
        throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
          {code: 'InstalledModelDefaultsForeignOriginal'});
      }
      // One preparation cannot migrate to another installation after a failed
      // registration. No physical child has been acquired by this DATA stage.
      spent = true;
      adoptedCurrent = current;
    }};
  view = Object.freeze({bindingOriginals: originals, resolveTaskDefaults,
    bindRegistration(entry) {
      if (this !== view || entry === null || typeof entry !== 'object' ||
          entry.providerId !== providerId || entry.bindingOriginals !== originals ||
          preparedRegistrations.has(entry)) {
        throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
          {code: 'InstalledModelDefaultsForeignOriginal'});
      }
      check();
      preparedRegistrations.set(entry, view);
      return entry;
    }});
  defaultsPreparations.set(view, state);
  return view;
}

export function assertInstalledModelDefaultsPreparation(view, moon, providerId) {
  const original = defaultsPreparations.get(view);
  if (original === undefined || original.moon !== moon || original.providerId !== providerId) {
    throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
      {code: 'InstalledModelDefaultsForeignOriginal'});
  }
  original.check();
}

export function assertInstalledModelDefaultsAdoption(provider, view, moon, providerId) {
  assertInstalledModelDefaultsPreparation(view, moon, providerId);
  if (installedDefaults.get(provider) !== view) {
    throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
      {code: 'InstalledModelDefaultsForeignOriginal'});
  }
  provider.assertNewTrustedRuntime();
}

// Registration remains physical Host capability. The common admission owner
// subsequently binds the selected callback to its exact Task and prompt.
export function installModelProviders(moon, register, assertHostRuntime,
  assertNewHostRuntime = assertHostRuntime, bindSdkStaticOriginals) {
  if (register === undefined) return new Map();
  if (typeof register !== 'function') {
    throw new TypeError('InvalidInstalledModelProviderRegistration');
  }
  if (assertHostRuntime !== undefined) {
    if (typeof assertHostRuntime !== 'function') {
      throw new TypeError('InferTrustedRuntimeViewUnavailable');
    }
    assertHostRuntime();
  }
  const entries = register(moon);
  assertHostRuntime?.();
  if (!Array.isArray(entries) || entries.length > 128) {
    throw new TypeError('InvalidInstalledModelProviderRegistration');
  }
  const result = new Map();
  for (const entry of entries) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).some(key => !['invoke', 'providerId', 'validatePrompt',
          'physicalPreflight', 'quantityCapacity', 'observeEgress',
          'bindingOriginals', 'reconcileResponse', 'entryPersistence',
          'originalReadInstallation', 'originalReadRecipe', 'rawCaptureSelection', 'sdkStaticOriginals'].includes(key))) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    // Static registration values are read once before retention/Core calls.
    // Dynamic current facts still come from the SAME selected callback later.
    const providerId = entry.providerId, entryPersistence = entry.entryPersistence;
    if (entryPersistence !== undefined && entryPersistence !== 'async' ||
        typeof providerId !== 'string' || result.has(providerId) ||
        entryPersistence === 'async' && Object.hasOwn(entry, 'invoke')) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    const invoke = entryPersistence === 'async' ? undefined : entry.invoke;
    const validatePrompt = entry.validatePrompt, reconcileResponse = entry.reconcileResponse;
    const physicalPreflight = entry.physicalPreflight, observeEgress = entry.observeEgress;
    const originalReadSource = entry.originalReadInstallation, originalRecipeSource = entry.originalReadRecipe,
      rawSource = entry.rawCaptureSelection;
    const bindingSource = entry.bindingOriginals, quantitySource = entry.quantityCapacity;
    const sdkStaticOriginals = entry.sdkStaticOriginals;
    const defaultsCallbacks = modelDefaultsCallbacks(moon);
    let requireOriginalEagerStartup;
    // The Host supplies this private same-installation/current connection,
    // not registration DATA or a packet flag. Ordinary platform trust does
    // not imply the optional explicit recipe's eager-startup responsibility.
    if (sdkStaticOriginals !== undefined) {
      if (typeof bindSdkStaticOriginals !== 'function') {
        throw Object.assign(new TypeError('InferTrustedSdkStaticUnavailable'),
          {code: 'InferTrustedSdkStaticUnavailable'});
      }
      const requireEager = bindSdkStaticOriginals(sdkStaticOriginals);
      if (typeof requireEager === 'function') requireOriginalEagerStartup = requireEager;
    }
    if (entryPersistence !== 'async' && typeof invoke !== 'function' ||
        typeof validatePrompt !== 'function' ||
        reconcileResponse !== undefined && typeof reconcileResponse !== 'function') {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    // Installation-time snapshot precedes any provider or original Run start.
    // No default numerical profile is supplied when this declaration is absent.
    if (originalReadSource !== undefined && originalRecipeSource !== undefined) {
      throw new TypeError('InvalidInstalledInferOriginalReadInstallation');
    }
    const originalReadInstallation = retainInferOriginalReadInstallation(originalReadSource);
    const originalReadRecipe = retainInferOriginalReadRecipe(originalRecipeSource);
    const rawCaptureSelection = snapshotModelRawCaptureSelection(rawSource);
    // This installation profile connects raw custody only to the existing
    // durable asynchronous caller. It grants no raw capture or send authority.
    if (rawCaptureSelection !== undefined &&
        (entryPersistence !== 'async' || typeof physicalPreflight !== 'function')) {
      throw new TypeError('InstalledInferRawCaptureRequiresAsyncPhysicalPreflight');
    }
    const preparedDefaults = preparedRegistrations.get(entry);
    const preparedState = preparedDefaults === undefined ? undefined : defaultsPreparations.get(preparedDefaults);
    if (preparedState !== undefined && (preparedState.moon !== moon ||
        preparedState.providerId !== providerId || preparedState.originals !== bindingSource ||
        typeof assertNewHostRuntime !== 'function')) {
      throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
        {code: 'InstalledModelDefaultsForeignOriginal'});
    }
    const bindingOriginals = preparedState === undefined
      ? retainProviderBindingOriginals(bindingSource) : preparedState.originals;
    const quantityCapacity = retainModelQuantityCapacity(quantitySource);
    if (entryPersistence === 'async' &&
        (typeof physicalPreflight !== 'function' || quantityCapacity === undefined ||
          bindingOriginals === undefined || rawCaptureSelection === undefined)) {
      throw new TypeError('InvalidInstalledModelAsyncProviderRegistration');
    }
    if (entryPersistence === 'async' &&
        typeof moon.clientProgramInstallAsyncModelProvider !== 'function') {
      throw new TypeError('InstalledModelAsyncProviderRuntimeUnavailable');
    }
    // Reserve the same candidate for this one actual installation, before
    // creating its Core Provider. Its current closure is used only after the
    // existing map has retained the physical record below.
    let retained;
    if (preparedState !== undefined) {
      preparedState.adopt(moon, providerId, bindingSource, () => {
        if (retained === undefined) {
          throw Object.assign(new Error('InstalledModelDefaultsUnavailable'),
            {code: 'InstalledModelDefaultsUnavailable'});
        }
        retained.assertNewTrustedRuntime();
      }, assertNewHostRuntime);
    }
    const provider = entryPersistence === 'async'
      ? moon.clientProgramInstallAsyncModelProvider(providerId)
      : moon.clientProgramInstallModelProvider(providerId, invoke);
    if (provider === undefined) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    const assertTrustedRuntime = assertHostRuntime === undefined ? undefined : () => {
      assertHostRuntime();
      if (sdkStaticOriginals !== undefined) bindSdkStaticOriginals(sdkStaticOriginals);
      if (result.get(providerId) !== retained || retained.provider !== provider) {
        throw Object.assign(new Error('InferTrustedRuntimeOriginalChanged'),
          {code: 'InferTrustedRuntimeOriginalChanged'});
      }
    };
    const assertNewTrustedRuntime = assertNewHostRuntime === undefined ? undefined : () => {
      assertNewHostRuntime();
      assertTrustedRuntime();
    };
    // The existing Host binder supplies this same-original check, not entry
    // fields or a caller-authored Bool/CID. Preserve static-only registrations.
    const requireEagerSdkStartup = requireOriginalEagerStartup === undefined ||
      assertTrustedRuntime === undefined ? undefined : () => {
      assertTrustedRuntime();
      requireOriginalEagerStartup();
      assertTrustedRuntime();
    };
    const resolveTaskDefaults = preparedDefaults === undefined
      ? modelDefaultsResolver(moon, providerId, bindingOriginals, assertNewTrustedRuntime,
        () => retained, defaultsCallbacks)
      : function (selectedModel, taskMaxOutputTokens, limits) {
        if (this !== retained) {
          throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
            {code: 'InstalledModelDefaultsForeignOriginal'});
        }
        return preparedDefaults.resolveTaskDefaults(selectedModel, taskMaxOutputTokens, limits);
      };
    retained = Object.freeze({provider, originalReadInstallation, originalReadRecipe, rawCaptureSelection,
      assertTrustedRuntime, assertNewTrustedRuntime, requireEagerSdkStartup,
      bindingOriginals,
      physicalPreflight,
      entryPersistence,
      reconcileResponse,
      quantityCapacity,
      resolveTaskDefaults,
      observeEgress: typeof observeEgress !== 'function' ? undefined : () => {
        try { return Reflect.apply(observeEgress, entry, []); }
        catch { return undefined; }
      },
      validatePrompt: (...args) => validatePrompt(...args) === true});
    result.set(providerId, retained);
    if (preparedDefaults !== undefined) installedDefaults.set(retained, preparedDefaults);
  }
  return result;
}

export function readInstalledModelDependencies(moon, execution, installation, beforeRead) {
  if (beforeRead !== undefined) {
    const original = originalModelMaterialArrays(installation);
    const references = moon.clientProgramInferDependencyReferences(execution);
    const media = moon.clientProgramInferMediaDependencyReferences(execution);
    const read = media.length !== 0 ? moon.clientProgramReadInferModelDependenciesWithMedia
      : moon.clientProgramReadInferModelDependencies;
    beforeRead(3 + media.length, index => {
      const cid = index < 3 ? runtimeField(references, index) : runtimeField(media[index - 3], 1);
      // Empty is sizing DATA for an absent body only. The actual reader below
      // still receives undefined and keeps its original missing-body refusal.
      return original.bodies.find(entry => entry.cid === cid)?.bodyWire ?? '';
    }, original.executions.length + original.bodies.length);
    checkInstallation(installation);
    const bodies = new Map(original.bodies.map(entry => [entry.cid, entry.bodyWire]));
    if (media.length !== 0) {
      return checked(Reflect.apply(read, moon, [execution,
        bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)), bodies.get(runtimeField(references, 2)),
        media.filter(entry => bodies.has(runtimeField(entry, 1))).map(entry =>
          runtimePair(runtimeField(entry, 0), bodies.get(runtimeField(entry, 1))))]));
    }
    return checked(Reflect.apply(read, moon, [execution,
      bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)),
      bodies.get(runtimeField(references, 2))]));
  }
  return readInstalledModelDependenciesLegacy(moon, execution, installation);
}

function readInstalledModelDependenciesLegacy(moon, execution, installation) {
  checkInstallation(installation);
  const references = moon.clientProgramInferDependencyReferences(execution);
  const bodies = new Map((installation.dependencyBodies ?? [])
    .map(entry => [entry.cid, entry.bodyWire]));
  const media = moon.clientProgramInferMediaDependencyReferences(execution);
  if (media.length !== 0) {
    // Preserve the checked role-to-CID relation. Missing bodies are reported
    // by the common dependency owner; another role or a provider callback
    // cannot manufacture admission from a symbolic contract reference.
    return checked(moon.clientProgramReadInferModelDependenciesWithMedia(execution,
      bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)), bodies.get(runtimeField(references, 2)),
      media.filter(entry => bodies.has(runtimeField(entry, 1))).map(entry =>
        (runtimePair(runtimeField(entry, 0), bodies.get(runtimeField(entry, 1)))))));
  }
  return checked(moon.clientProgramReadInferModelDependencies(execution,
    bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)),
    bodies.get(runtimeField(references, 2))));
}

export function admitInstalledModelProvider(moon, execution, dependencies,
  providers) {
  const selected = providers.get(moon.clientProgramInferProviderId(execution));
  if (selected === undefined) {
    throw Object.assign(new Error('InstalledInferModelProviderUnavailable'),
      {code: 'InstalledInferModelProviderUnavailable'});
  }
  return checked(moon.clientProgramAdmitModelProvider(selected.provider,
    execution, dependencies, selected.validatePrompt));
}

// Bind the actual Host-selected provider to its nonsecret installation and
// configuration originals. MoonBit owns their canonical admission and all
// resulting identities; callback text and display names are not revisions.
export function admitInstalledModelProviderBinding(moon, providerId, physical, constructOriginal) {
  const originals = physical?.bindingOriginals;
  if (originals === undefined) {
    throw Object.assign(new Error('InstalledModelProviderBindingUnavailable'),
      {code: 'InstalledModelProviderBindingUnavailable'});
  }
  if (typeof moon.clientProgramModelProviderBinding !== 'function') {
    throw Object.assign(new Error('InstalledModelProviderBindingRuntimeUnavailable'),
      {code: 'InstalledModelProviderBindingRuntimeUnavailable'});
  }
  const value = constructOriginal === undefined
    ? checked(moon.clientProgramModelProviderBinding(providerId,
      originals.installationRevision.wire, originals.configurationContract.wire,
      originals.configuration.wire))
    : constructOriginal(providerId, originals.installationRevision.wire,
      originals.configurationContract.wire, originals.configuration.wire);
  return retainAdmittedProviderBinding(moon, providerId, originals, value);
}

function retainAdmittedProviderBinding(moon, providerId, originals, value) {
  const wire = moon.strategyRunEvidenceJson(value);
  const identity = moon.strategyRunEvidenceIdentity(value);
  const body = JSON.parse(wire);
  if (body.provider_id !== providerId || body.self_cid !== identity ||
      body.installation_revision_cid !== originals.installationRevision.cid ||
      body.configuration_contract_cid !== originals.configurationContract.cid ||
      body.configuration_cid !== originals.configuration.cid) {
    throw Object.assign(new Error('InstalledModelProviderBindingMismatch'),
      {code: 'InstalledModelProviderBindingMismatch'});
  }
  return Object.freeze({value, wire, identity, originals});
}

export function installedModelEnvironment(moon, baseWire, currentWire,
  installation) {
  if (installation === undefined) return currentWire;
  checkInstallation(installation);
  // Both full documents are independently admitted by the common checker;
  // selectors and capacities retain the existing conflict checks.
  return composeInstalledCheckEnvironment(moon, baseWire, currentWire,
    installation.environmentWire);
}

// Normal submit uses its original prepared owner. The metadata lookup does
// not admit a body: MoonBit checks canonical bytes, self-CID, exact Task and
// ceilings. Returning this contract does not admit prompt/retry/egress policy.
export function readInstalledModelExecution(moon, prepared, installation, occurrence, beforeRead) {
  if (beforeRead !== undefined) {
    const original = originalModelMaterialArrays(installation);
    const step = occurrence === undefined ? moon.clientProgramSelectedInferStep(prepared)
      : runtimeField(moon.clientProgramInferOccurrenceCoordinates(occurrence), 2);
    if (step === undefined) return undefined;
    if (original.emptyOriginal === true) {
      const error = Object.assign(new Error('InstalledInferModelExecutionUnavailable'),
        {code: 'InstalledInferModelExecutionUnavailable'});
      modelExecutionAbsences.set(error, {prepared, installation, occurrence});
      throw error;
    }
    const taskCid = occurrence === undefined ? moon.clientProgramInferModelTaskCid(prepared, step)
      : moon.clientProgramInferOccurrenceModelTaskCid(occurrence);
    const entry = original.executions.find(item => item.modelTaskCid === taskCid);
    if (entry === undefined) {
      throw Object.assign(new Error('InstalledInferModelExecutionUnavailable'),
        {code: 'InstalledInferModelExecutionUnavailable'});
    }
    const wire = entry.bodyWire, cid = entry.cid;
    const read = occurrence === undefined ? moon.clientProgramReadInferModelExecution
      : moon.clientProgramReadComposedInferModelExecution;
    beforeRead(1, () => wire, original.executions.length + original.bodies.length);
    checkInstallation(installation);
    return Object.freeze({step, execution: checked(Reflect.apply(read, moon,
      occurrence === undefined ? [prepared, step, wire, cid] : [occurrence, wire, cid]))});
  }
  return readInstalledModelExecutionLegacy(moon, prepared, installation, occurrence);
}

function readInstalledModelExecutionLegacy(moon, prepared, installation, occurrence) {
  const step = occurrence === undefined
    ? moon.clientProgramSelectedInferStep(prepared)
    : runtimeField(moon.clientProgramInferOccurrenceCoordinates(occurrence), 2);
  if (step === undefined) return undefined;
  const taskCid = occurrence === undefined
    ? moon.clientProgramInferModelTaskCid(prepared, step)
    : moon.clientProgramInferOccurrenceModelTaskCid(occurrence);
  const entry = installation === undefined ? undefined :
    checkInstallation(installation).find(item => item.modelTaskCid === taskCid);
  if (entry === undefined) {
    throw Object.assign(new Error('InstalledInferModelExecutionUnavailable'),
      {code: 'InstalledInferModelExecutionUnavailable'});
  }
  return Object.freeze({step, execution: checked(occurrence === undefined
    ? moon.clientProgramReadInferModelExecution(prepared, step, entry.bodyWire,
      entry.cid)
    : moon.clientProgramReadComposedInferModelExecution(occurrence,
      entry.bodyWire, entry.cid))});
}

// Only the actual normal Mock factory's frozen DATA envelope enters the
// funded Request path. This captures original arrays, not another registry,
// contract validator, canonical reader or Provider/Account permission.
function originalModelMaterialArrays(installation) {
  if (installation === null || typeof installation !== 'object' || !Object.isFrozen(installation)) {
    throw new TypeError('InstalledModelMaterialOriginalUnavailable');
  }
  const executions = Object.getOwnPropertyDescriptor(installation, 'executionContracts');
  const bodies = Object.getOwnPropertyDescriptor(installation, 'dependencyBodies');
  if (!executions || !Object.hasOwn(executions, 'value') ||
      !bodies || !Object.hasOwn(bodies, 'value') ||
      !Array.isArray(executions.value) || !Array.isArray(bodies.value) ||
      !Object.isFrozen(executions.value) || !Object.isFrozen(bodies.value)) {
    throw new TypeError('InstalledModelMaterialOriginalUnavailable');
  }
  // Only ordinary immutable empty DATA can establish absence without running
  // an iterator, element getter, replacement find or the funded read callback.
  // Other accepted originals keep their existing reader and Unknown behavior.
  if (!nodeTypes.isProxy(installation) &&
      [executions.value, bodies.value].every(entries => !nodeTypes.isProxy(entries) &&
        Object.getPrototypeOf(entries) === Array.prototype && entries.length === 0 &&
        Object.getOwnPropertyDescriptor(entries, Symbol.iterator) === undefined &&
        Object.getOwnPropertyDescriptor(entries, 'find') === undefined) &&
      Object.getOwnPropertyDescriptor(Array.prototype, Symbol.iterator)?.value === originalArrayIterator &&
      Object.getOwnPropertyDescriptor(Array.prototype, 'find')?.value === originalArrayFind) {
    return {executions: executions.value, bodies: bodies.value, emptyOriginal: true};
  }
  const ownString = (entry, key) => {
    if (entry === null || typeof entry !== 'object' || !Object.isFrozen(entry)) {
      throw new TypeError('InstalledModelMaterialOriginalUnavailable');
    }
    const field = Object.getOwnPropertyDescriptor(entry, key);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') {
      throw new TypeError('InstalledModelMaterialOriginalUnavailable');
    }
  };
  for (const entry of executions.value) {
    ownString(entry, 'modelTaskCid'); ownString(entry, 'bodyWire'); ownString(entry, 'cid');
  }
  for (const entry of bodies.value) {ownString(entry, 'bodyWire'); ownString(entry, 'cid');}
  return {executions: executions.value, bodies: bodies.value};
}

