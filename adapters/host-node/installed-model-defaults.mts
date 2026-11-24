import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

type BoundsField = 'maxBytes' | 'maxDepth' | 'maxMembers' | 'maxNodes' | 'maxWork';
type Bounds = Readonly<Record<BoundsField, number>>;
type Quantity = Readonly<{tokens: bigint; costUnits: bigint; durationMs: bigint}>;
type QuantityCapacity = Readonly<{limits: Quantity; perAttempt: Quantity}>;
type OriginalField = 'configuration' | 'configurationContract' | 'installationRevision';
type WireOriginal = Readonly<{wire: string; cid: string}>;
type BindingOriginals = Readonly<Record<OriginalField, WireOriginal>>;
type ReaderInput = [provider: string, installationWire: string, contractWire: string,
  configurationWire: string, maxBytes: number, maxNodes: number, maxDepth: number, maxMembers: number];
type BindingRuntime = Readonly<{
  strategyRunEvidenceJson(value: unknown): string;
  strategyRunEvidenceIdentity(value: unknown): string;
}>;
type Runtime = BindingRuntime & Readonly<{
  clientProgramReadInstalledModelDefaults?(...input: [...ReaderInput, maxWork: number]): unknown;
  clientProgramResolveInstalledModelDefaults?(original: unknown, model: string | undefined,
    tokens: bigint | undefined, maxWork: number): unknown;
  clientProgramInstalledModelDefaultsBinding?(original: unknown): unknown;
  clientProgramInstalledModelDefaultsUsage?(original: unknown): unknown;
  clientProgramModelProviderDefaultsReadConstructionCapacity?(...input: ReaderInput): unknown;
  clientProgramModelProviderDefaultsRetainedCapacity?(original: unknown): unknown;
  clientProgramModelProviderDefaultsResolutionCapacities?(original: unknown, tokens: bigint | undefined): unknown;
}>;
type Construction = Readonly<{prepareModelTaskInput(projection: object): object}>;
type Current = () => unknown;
type Defaults = Readonly<{
  value: unknown;
  resolved: unknown;
  binding: ReturnType<typeof retainAdmittedProviderBinding>;
  readUsage: Readonly<{bytes: unknown; nodes: unknown; work: unknown}>;
}>;
type ResolveDefaults = (this: unknown, selectedModel: string | undefined, taskMaxOutputTokens: bigint | undefined,
  limits: unknown, construction?: Construction) => Defaults;

// Bound physical retention of operator-supplied nonsecret originals. These
// envelope checks do not admit a canonical identity or a provider binding;
// the common Model owner must admit the originals before durable execution.
export function retainProviderBindingOriginals(value: unknown): BindingOriginals | undefined {
  if (value === undefined) return undefined;
  const fields = ['configuration', 'configurationContract', 'installationRevision'] as const;
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
  }
  const keys = Object.keys(value).sort();
  if (keys.length !== fields.length || keys.some((key, index) => key !== fields[index])) {
    throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
  }
  const originals = {} as Record<OriginalField, WireOriginal>;
  for (const name of fields) {
    const original = (value as Record<string, unknown>)[name];
    if (original === null || typeof original !== 'object' || Array.isArray(original)) {
      throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
    }
    const originalKeys = Object.keys(original).sort();
    if (originalKeys.length !== 2 || originalKeys[0] !== 'cid' || originalKeys[1] !== 'wire') {
      throw new TypeError('InvalidInstalledModelProviderBindingOriginals');
    }
    const wire = (original as Record<string, unknown>).wire, cid = (original as Record<string, unknown>).cid;
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
export function retainModelQuantityCapacity(capacity: unknown): QuantityCapacity | undefined {
  if (capacity === undefined) return undefined;
  if (capacity === null || typeof capacity !== 'object') {
    throw new TypeError('InvalidInstalledModelQuantityCapacity');
  }
  const keys = Object.keys(capacity).sort();
  if (keys.length !== 2 || keys[0] !== 'limits' || keys[1] !== 'perAttempt') {
    throw new TypeError('InvalidInstalledModelQuantityCapacity');
  }
  const limitsSource = (capacity as Record<string, unknown>).limits,
    perAttemptSource = (capacity as Record<string, unknown>).perAttempt;
  if ([limitsSource, perAttemptSource].some(amount => {
    if (amount === null || typeof amount !== 'object') return true;
    const amountKeys = Object.keys(amount).sort();
    return amountKeys.length !== 3 || amountKeys[0] !== 'costUnits' ||
      amountKeys[1] !== 'durationMs' || amountKeys[2] !== 'tokens';
  })) {
    throw new TypeError('InvalidInstalledModelQuantityCapacity');
  }
  const limits = {tokens: (limitsSource as Quantity).tokens, costUnits: (limitsSource as Quantity).costUnits,
    durationMs: (limitsSource as Quantity).durationMs};
  const perAttempt = {tokens: (perAttemptSource as Quantity).tokens, costUnits: (perAttemptSource as Quantity).costUnits,
    durationMs: (perAttemptSource as Quantity).durationMs};
  if ([limits, perAttempt].some(amount => Object.values(amount).some(value =>
    typeof value !== 'bigint' || value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER)))) {
    throw new TypeError('InvalidInstalledModelQuantityCapacity');
  }
  return Object.freeze({limits: Object.freeze(limits), perAttempt: Object.freeze(perAttempt)});
}

// These are bounded DATA-reader limits, not a capacity reservation. Snapshot
// before Core calls; a later getter cannot replace the bounds used for the
// same retained configuration. Actual Host startup still owns this workspace.
function retainModelDefaultsLimits(value: unknown): Bounds {
  const fields = ['maxBytes', 'maxDepth', 'maxMembers', 'maxNodes', 'maxWork'] as const;
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('InvalidInstalledModelDefaultsLimits');
  }
  const keys = Object.keys(value).sort();
  if (keys.length !== fields.length || keys.some((key, index) => key !== fields[index])) {
    throw new TypeError('InvalidInstalledModelDefaultsLimits');
  }
  const snapshot = {} as Record<BoundsField, number>;
  for (const key of fields) {
    const amount = (value as Record<BoundsField, number>)[key];
    if (!Number.isSafeInteger(amount) || amount < 0 || amount > 2147483647) {
      throw new TypeError('InvalidInstalledModelDefaultsLimits');
    }
    snapshot[key] = amount;
  }
  return Object.freeze(snapshot);
}

export function modelDefaultsCallbacks(moon: Runtime) {
  return Object.freeze({reader: moon.clientProgramReadInstalledModelDefaults,
    resolver: moon.clientProgramResolveInstalledModelDefaults,
    bindingReader: moon.clientProgramInstalledModelDefaultsBinding,
    usageReader: moon.clientProgramInstalledModelDefaultsUsage,
    readCapacity: moon.clientProgramModelProviderDefaultsReadConstructionCapacity,
    retainedCapacity: moon.clientProgramModelProviderDefaultsRetainedCapacity,
    resolutionCapacities: moon.clientProgramModelProviderDefaultsResolutionCapacities});
}

export function modelDefaultsResolver(moon: Runtime, providerId: string, bindingOriginals: BindingOriginals | undefined,
  assertCurrent: Current | undefined, receiver: () => unknown,
  {reader, resolver, bindingReader, usageReader, readCapacity, retainedCapacity, resolutionCapacities} = modelDefaultsCallbacks(moon)): ResolveDefaults {
  let original: unknown;
  let bounds: Bounds | undefined;
  let readFailure: Readonly<{cause: unknown}> | undefined;
  let originalConstruction: Construction | undefined;
  return function resolveTaskDefaults(this: unknown, selectedModel, taskMaxOutputTokens, limits, construction) {
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
    if (bounds !== undefined && (Object.keys(nextBounds) as BoundsField[]).some(key => nextBounds[key] !== bounds![key])) {
      throw Object.assign(new Error('InstalledModelDefaultsLimitsChanged'),
        {code: 'InstalledModelDefaultsLimitsChanged'});
    }
    if (bounds !== undefined && construction !== undefined && originalConstruction !== construction) {
      throw Object.assign(new Error('InstalledModelDefaultsConstructionChanged'),
        {code: 'InstalledModelDefaultsConstructionChanged'});
    }
    if (bounds === undefined) {
      bounds = nextBounds;
      originalConstruction = construction;
      try {
        const project = () => checked(Reflect.apply(reader!, moon, [providerId,
          bindingOriginals.installationRevision.wire, bindingOriginals.configurationContract.wire,
          bindingOriginals.configuration.wire, bounds!.maxBytes, bounds!.maxNodes, bounds!.maxDepth,
          bounds!.maxMembers, bounds!.maxWork]));
        if (construction === undefined) original = project();
        else {
          if (typeof construction.prepareModelTaskInput !== 'function' ||
              ![readCapacity, retainedCapacity, resolutionCapacities].every(value => typeof value === 'function')) {
            throw Object.assign(new Error('InstalledModelDefaultsConstructionUnavailable'),
              {code: 'InstalledModelDefaultsConstructionUnavailable'});
          }
          original = construction.prepareModelTaskInput(Object.freeze({
            capacity: () => Reflect.apply(readCapacity!, moon, [providerId,
              bindingOriginals.installationRevision.wire, bindingOriginals.configurationContract.wire,
              bindingOriginals.configuration.wire, bounds!.maxBytes, bounds!.maxNodes, bounds!.maxDepth, bounds!.maxMembers]),
            project, retained: (value: unknown) => Reflect.apply(retainedCapacity!, moon, [value]),
          }));
        }
        if (original === undefined || original === null) {
          throw Object.assign(new Error('InvalidHostRuntimeResult'), {code: 'InvalidHostRuntimeResult'});
        }
      } catch (cause) {
        readFailure = Object.freeze({cause});
      }
    }
    if (readFailure !== undefined) throw readFailure.cause;
    assertCurrent();
    const project = () => {
      const binding = retainAdmittedProviderBinding(moon, providerId, bindingOriginals,
        Reflect.apply(bindingReader!, moon, [original]));
      const resolved = checked(Reflect.apply(resolver!, moon,
        [original, selectedModel, taskMaxOutputTokens, bounds!.maxWork]));
      const usage = Reflect.apply(usageReader!, moon, [original]);
      const readUsage = Object.freeze({bytes: runtimeField(usage, 0),
        nodes: runtimeField(usage, 1), work: runtimeField(usage, 2)});
      assertCurrent();
      return Object.freeze({value: original, resolved, binding, readUsage});
    };
    if (construction === undefined) return project();
    const quantities = Reflect.apply(resolutionCapacities!, moon, [original, taskMaxOutputTokens]);
    if (!Array.isArray(quantities) || quantities.length !== 2) {
      throw Object.assign(new Error('InstalledModelDefaultsConstructionUnavailable'),
        {code: 'InstalledModelDefaultsConstructionUnavailable'});
    }
    return construction.prepareModelTaskInput(Object.freeze({
      capacity: () => quantities[0], project,
      retained: () => quantities[1],
    })) as Defaults;
  };
}

export function retainAdmittedProviderBinding(moon: BindingRuntime, providerId: string, originals: BindingOriginals, value: unknown) {
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
