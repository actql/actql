// Static ModelTask registration shares the installed checker composition.
// This metadata is neither a provider registration nor an egress grant. The
// common execution owner must separately admit dependencies and authority.
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {retainInferOriginalReadInstallation} from './infer-original-installation.mjs';
import {snapshotModelRawCaptureSelection} from './infer-raw-selection.mjs';
import {openSync, readSync, closeSync} from 'node:fs';

// Physical observation only: the common account reader/evaluator decides
// authority. Bound reads even when the selected file grows during observation.
export function observeInstalledModelAccount(moon, authorization) {
  try {
    let wire = authorization?.accountConfiguration;
    if (authorization?.accountConfig !== undefined) {
      if (wire !== undefined) return moon.executionAuthorizationMissing();
      const fd = openSync(authorization.accountConfig, 'r');
      try {
        const buffer = Buffer.alloc(1000001);
        let used = 0;
        while (used < buffer.length) {
          const read = readSync(fd, buffer, used, buffer.length - used, used);
          if (read === 0) break;
          used += read;
        }
        if (used > 1000000) return moon.executionAuthorizationMissing();
        wire = new TextDecoder('utf-8', {fatal: true}).decode(buffer.subarray(0, used));
      } finally { closeSync(fd); }
    }
    return typeof wire === 'string' && Buffer.byteLength(wire) <= 1000000
      ? moon.executionAuthorizationAdmit(wire)
      : moon.executionAuthorizationMissing();
  } catch { return moon.executionAuthorizationMissing(); }
}

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
          'originalReadInstallation', 'rawCaptureSelection', 'sdkStaticOriginals'].includes(key))) {
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
    const originalReadSource = entry.originalReadInstallation, rawSource = entry.rawCaptureSelection;
    const bindingSource = entry.bindingOriginals, quantitySource = entry.quantityCapacity;
    const sdkStaticOriginals = entry.sdkStaticOriginals;
    let requireOriginalEagerStartup;
    // The Host supplies this private connection, not registration DATA or a
    // packet flag. Missing selected startup is Unavailable, never coverage.
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
    const originalReadInstallation = retainInferOriginalReadInstallation(originalReadSource);
    const rawCaptureSelection = snapshotModelRawCaptureSelection(rawSource);
    // This installation profile connects raw custody only to the existing
    // durable asynchronous caller. It grants no raw capture or send authority.
    if (rawCaptureSelection !== undefined &&
        (entryPersistence !== 'async' || typeof physicalPreflight !== 'function')) {
      throw new TypeError('InstalledInferRawCaptureRequiresAsyncPhysicalPreflight');
    }
    const bindingOriginals = retainProviderBindingOriginals(bindingSource);
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
    const provider = entryPersistence === 'async'
      ? moon.clientProgramInstallAsyncModelProvider(providerId)
      : moon.clientProgramInstallModelProvider(providerId, invoke);
    if (provider === undefined) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    let retained;
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
    const requireEagerSdkStartup = requireOriginalEagerStartup === undefined ? undefined : () => {
      assertTrustedRuntime();
      requireOriginalEagerStartup();
      assertTrustedRuntime();
    };
    retained = Object.freeze({provider, originalReadInstallation, rawCaptureSelection,
      assertTrustedRuntime, assertNewTrustedRuntime, requireEagerSdkStartup,
      bindingOriginals,
      physicalPreflight,
      entryPersistence,
      reconcileResponse,
      quantityCapacity,
      observeEgress: typeof observeEgress !== 'function' ? undefined : () => {
        try { return Reflect.apply(observeEgress, entry, []); }
        catch { return undefined; }
      },
      validatePrompt: (...args) => validatePrompt(...args) === true});
    result.set(providerId, retained);
  }
  return result;
}

export function readInstalledModelDependencies(moon, execution, installation) {
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
      bodies.get(references._0), bodies.get(references._1), bodies.get(references._2),
      media.filter(entry => bodies.has(entry._1)).map(entry =>
        ({_0: entry._0, _1: bodies.get(entry._1)}))));
  }
  return checked(moon.clientProgramReadInferModelDependencies(execution,
    bodies.get(references._0), bodies.get(references._1),
    bodies.get(references._2)));
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
export function admitInstalledModelProviderBinding(moon, providerId, physical) {
  const originals = physical?.bindingOriginals;
  if (originals === undefined) {
    throw Object.assign(new Error('InstalledModelProviderBindingUnavailable'),
      {code: 'InstalledModelProviderBindingUnavailable'});
  }
  if (typeof moon.clientProgramModelProviderBinding !== 'function') {
    throw Object.assign(new Error('InstalledModelProviderBindingRuntimeUnavailable'),
      {code: 'InstalledModelProviderBindingRuntimeUnavailable'});
  }
  const value = checked(moon.clientProgramModelProviderBinding(providerId,
    originals.installationRevision.wire, originals.configurationContract.wire,
    originals.configuration.wire));
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
export function readInstalledModelExecution(moon, prepared, installation,
  occurrence) {
  const step = occurrence === undefined
    ? moon.clientProgramSelectedInferStep(prepared)
    : moon.clientProgramInferOccurrenceCoordinates(occurrence)._2;
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
