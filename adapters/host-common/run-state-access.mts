// Authorized current-state projection for one durably committed Run.
// MoonBit owns inventory, availability relations, aggregate and next action.
// This adapter only observes current Store and Host-policy facts.
import type {WireRunRef, WireRunState} from '../../packages/client-wire/index.js';

export type RunStateRequest = Readonly<{
  indexKey: WireRunRef;
  principalId: string;
  purpose: string;
}>;
type Awaitable<T> = T | PromiseLike<T>;
type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type CommittedEntry = Readonly<{
  public_index_entry_cid: string;
  publication_attempt_cid: string;
  result_manifest_cid: string;
  run_definition_cid: string;
}>;
type ContractName = 'public_index_entry' | 'result_manifest' | 'run_definition' |
  'result_retention_policy';
type ResultObservation = Readonly<{
  name: string;
  state: 'available' | 'unavailable' | 'unknown';
  reason: string;
  observedAt: string;
}>;
type ClockObservation = Readonly<{failed: true; error: unknown}> |
  Readonly<{failed?: false; at: string}>;
type Store = Readonly<{
  confirmCommittedIndex(key: WireRunRef): Awaitable<CommittedEntry | undefined>;
  readCommittedPublication?(key: WireRunRef):
    Awaitable<Readonly<{entry: CommittedEntry; index: object}> | undefined>;
  readPublicationContract(cid: string, name: ContractName): Awaitable<unknown>;
  latestRecordContract(cid: string): Awaitable<unknown>;
  observeTrustedClock(cid: string, at: string): Awaitable<unknown>;
  sampleTrustedClock?(cid: string, sample: () => string): Awaitable<unknown>;
  withCommittedResult(key: WireRunRef, definitionCid: string, authorize: () => boolean,
    consume: () => Promise<undefined>): Awaitable<unknown>;
  readCommittedResultRetentionExtension(key: WireRunRef, definitionCid: string):
    Awaitable<Readonly<{extension: unknown}> | undefined>;
}>;
type Control = Readonly<{
  manifestResultNames(manifest: unknown, limits: Limits): readonly string[];
  resultReadDefinitionCid(manifest: unknown, name: string): string;
  resultReadRetentionPolicyCid(manifest: unknown, name: string): string;
  resultReadAvailability(manifest: unknown, name: string, retention: unknown,
    observedAt: string): string;
  resultReadExtendedAvailability(manifest: unknown, name: string, retention: unknown,
    extension: unknown, observedAt: string): string;
  resultRetentionClockContractCid(retention: unknown): string;
  runDefinitionRunId(definition: unknown): string;
  projectCommittedPublicationState(record: unknown, index: unknown): string;
  trustedClockNotBefore?(previous: string, observedAt: string): boolean;
  issueSucceededRunState(request: Readonly<{
    runId: string;
    updatedAt: string;
    declaredResults: readonly string[];
    observations: readonly ResultObservation[];
  }>, limits: Limits): string;
}>;
type Context = RunStateRequest & Readonly<{
  entry: CommittedEntry;
  manifest: unknown;
  runDefinition: unknown;
}>;
type AuthorityConfiguration = Readonly<{
  authorizeRunState(facts: (RunStateRequest & Readonly<{stage: 'request'}>) |
    (Context & Readonly<{stage: 'response'; state: WireRunState}>)): Awaitable<boolean>;
  resultPolicyAvailable(facts: Context & Readonly<{
    resultName: string;
    retention: unknown;
    baseRetention: unknown;
    observedAt: string;
  }>): Awaitable<boolean>;
}>;
declare const authorityBrand: unique symbol;
declare const serviceBrand: unique symbol;
type Authority = Readonly<{[authorityBrand]: true}>;
export type RunStateService = Readonly<{[serviceBrand]: true}>;
type ServiceConfiguration = Readonly<{
  store: Store;
  control: Control;
  authority: Authority;
  now: () => unknown;
  limits: Limits;
}>;
type InstalledService = Omit<ServiceConfiguration, 'authority'> & Readonly<{
  authority: AuthorityConfiguration | undefined;
  readCommittedPublication: Store['readCommittedPublication'];
  sampleTrustedClock: Store['sampleTrustedClock'];
  trustedClockNotBefore: Control['trustedClockNotBefore'];
}>;

const authorities = new WeakMap<Authority, AuthorityConfiguration>();
const services = new WeakMap<RunStateService, InstalledService>();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value: unknown, keys: readonly string[]) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = (value: number) => Number.isSafeInteger(value) && value > 0;

export class RunStateAccessError extends Error {
  declare readonly code: string;
  declare readonly primaryFailure: unknown;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw new RunStateAccessError(code, cause);
};

export function installRunStateAuthority(configuration: AuthorityConfiguration): Authority {
  if (!exactKeys(configuration, [
    'authorizeRunState', 'resultPolicyAvailable',
  ]) || typeof configuration.authorizeRunState !== 'function' ||
      typeof configuration.resultPolicyAvailable !== 'function') {
    fail('InvalidRunStateAuthority');
  }
  const authority = Object.freeze({}) as Authority;
  authorities.set(authority, Object.freeze({...configuration}));
  return authority;
}

export function installRunStateService(configuration: ServiceConfiguration): RunStateService {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.latestRecordContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.withCommittedResult !== 'function' ||
      typeof configuration.store.readCommittedResultRetentionExtension !==
        'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.manifestResultNames !== 'function' ||
      typeof configuration.control.resultReadDefinitionCid !== 'function' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultReadAvailability !== 'function' ||
      typeof configuration.control.resultReadExtendedAvailability !==
        'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      typeof configuration.control.runDefinitionRunId !== 'function' ||
      typeof configuration.control.projectCommittedPublicationState !==
        'function' ||
      typeof configuration.control.issueSucceededRunState !== 'function' ||
      !authorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidRunStateService');
  }
  const readCommittedPublication = configuration.store.readCommittedPublication;
  if (readCommittedPublication !== undefined && typeof readCommittedPublication !== 'function') {
    fail('InvalidRunStateService');
  }
  const sampleTrustedClock = configuration.store.sampleTrustedClock;
  const trustedClockNotBefore = configuration.control.trustedClockNotBefore;
  if (sampleTrustedClock !== undefined && (typeof sampleTrustedClock !== 'function' ||
      typeof trustedClockNotBefore !== 'function')) {
    fail('InvalidRunStateService');
  }
  const service = Object.freeze({}) as RunStateService;
  services.set(service, Object.freeze({
    store: configuration.store,
    readCommittedPublication,
    sampleTrustedClock,
    trustedClockNotBefore,
    control: configuration.control,
    authority: authorities.get(configuration.authority),
    now: configuration.now,
    limits: Object.freeze({...configuration.limits}),
  }));
  return service;
}

// The public Journal-backed observer authorizes before reading its original
// request row. This is the same gate as internal publication inspection.
export async function authorizeRunStateRequest(service: RunStateService, request: RunStateRequest) {
  const installed = services.get(service) ?? fail('ForeignRunStateService');
  validateRequest(request);
  if (await installed.authority!.authorizeRunState(Object.freeze({
    stage: 'request', indexKey: Object.freeze({...request.indexKey}),
    principalId: request.principalId, purpose: request.purpose,
  })) !== true) fail('RunStateAccessDenied');
}

function validateRequest(request: RunStateRequest) {
  if (!exactKeys(request, ['indexKey', 'principalId', 'purpose']) ||
      !exactKeys(request.indexKey, [
        'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
      ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.principalId !== 'string' ||
      request.principalId.length === 0 ||
      typeof request.purpose !== 'string' || request.purpose.length === 0) {
    fail('InvalidRunStateRequest');
  }
}

function observedAt(now: () => unknown) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidRunStateClock');
  }
  return value;
}

function unavailableFrom(error: unknown, at: string): Omit<ResultObservation, 'name'> {
  switch ((error as {code?: unknown} | null)?.code) {
    case 'PublicationObjectMissing':
      return {state: 'unavailable', reason: 'deleted', observedAt: at};
    case 'PublicationObjectCorrupt':
    case 'PublicationDurableBindingMismatch':
    case 'PublicationContractCorrupt':
    case 'InvalidPublicationStoreObject':
      return {
        state: 'unavailable', reason: 'integrity_failed', observedAt: at,
      };
    case 'PublicationClockUncertain':
      return {state: 'unknown', reason: 'clock_uncertain', observedAt: at};
    default:
      return {state: 'unknown', reason: 'store_query_failed', observedAt: at};
  }
}

async function observeResult(installed: InstalledService, context: Context,
  resultName: string, clocks: Map<string, ClockObservation>): Promise<ResultObservation> {
  const retentionCid = installed.control.resultReadRetentionPolicyCid(
    context.manifest, resultName,
  );
  let retention;
  try {
    retention = await installed.store.readPublicationContract(
      retentionCid, 'result_retention_policy',
    );
  } catch (error) {
    return {name: resultName,
      ...unavailableFrom(error, observedAt(installed.now))};
  }
  const clockCid = installed.control.resultRetentionClockContractCid(
    retention,
  );
  let at: string | undefined;
  try {
    if (installed.sampleTrustedClock === undefined) {
      // Compatibility with Stores that only accept an explicit observation.
      // Do not sample before the original retention read finishes.
      at = observedAt(installed.now);
      await installed.store.observeTrustedClock(clockCid, at);
    } else {
      const original = clocks.get(clockCid);
      if (original?.failed) throw original.error;
      if (original === undefined) {
        const acceptedAt = await Reflect.apply(installed.sampleTrustedClock, installed.store,
          [clockCid, () => (at = observedAt(installed.now))]);
        if (at === undefined || typeof acceptedAt !== 'string' ||
            Reflect.apply(installed.trustedClockNotBefore!, installed.control, [at, acceptedAt]) !== true) {
          fail('PublicationClockUncertain');
        }
        at = acceptedAt;
      } else {
        // Internal retention reads do not start another public operation.
        // Reuse its real accepted floor, but evaluate expiry and rollback at
        // this Result's current sample without claiming it was persisted.
        at = observedAt(installed.now);
        if (Reflect.apply(installed.trustedClockNotBefore!, installed.control, [original.at, at]) !== true) {
          fail('PublicationClockUncertain');
        }
      }
      clocks.set(clockCid, {at});
    }
  } catch (error) {
    if (installed.sampleTrustedClock !== undefined) clocks.set(clockCid, {failed: true, error});
    return {name: resultName, ...unavailableFrom(error, at ?? observedAt(installed.now))};
  }
  const definitionCid = installed.control.resultReadDefinitionCid(
    context.manifest, resultName,
  );
  let retained;
  try {
    retained =
      await installed.store.readCommittedResultRetentionExtension(
        context.indexKey, definitionCid,
      );
  } catch (error) {
    return {name: resultName, ...unavailableFrom(error, at)};
  }
  const retentionState = retained === undefined
    ? installed.control.resultReadAvailability(
      context.manifest, resultName, retention, at,
    )
    : installed.control.resultReadExtendedAvailability(
      context.manifest,
      resultName,
      retention,
      retained.extension,
      at,
    );
  if (retentionState === 'delete_due') {
    try {
      await installed.store.withCommittedResult(
        context.indexKey,
        definitionCid,
        () => true,
        async () => undefined,
      );
      return {
        name: resultName,
        state: 'unavailable',
        reason: 'retention_expired',
        observedAt: at,
      };
    } catch (error) {
      return {name: resultName, ...unavailableFrom(error, at)};
    }
  }
  if (retentionState === 'retention_expired') {
    return {
      name: resultName,
      state: 'unavailable',
      reason: 'retention_expired',
      observedAt: at,
    };
  }
  if (retentionState !== 'available') {
    return {
      name: resultName,
      state: 'unknown',
      reason: 'store_query_failed',
      observedAt: at,
    };
  }
  let policyAvailable;
  try {
    policyAvailable = await installed.authority!.resultPolicyAvailable(
      Object.freeze({
        ...context,
        resultName,
        retention: retained?.extension ?? retention,
        baseRetention: retention,
        observedAt: at,
      }),
    );
  } catch (error) {
    return {name: resultName, ...unavailableFrom(error, at)};
  }
  if (policyAvailable !== true) {
    return {
      name: resultName,
      state: 'unavailable',
      reason: 'policy_unavailable',
      observedAt: at,
    };
  }
  try {
    await installed.store.withCommittedResult(
      context.indexKey,
      definitionCid,
      () => true,
      async () => undefined,
    );
    return {
      name: resultName,
      state: 'available',
      reason: 'confirmed_present',
      observedAt: at,
    };
  } catch (error) {
    return {name: resultName, ...unavailableFrom(error, at)};
  }
}

// Optional publication observation is only for the existing Local observer's
// committed/unpublished branch. Denial and physical failure are never absence.
export async function observeAuthorizedRunState(service: RunStateService, request: RunStateRequest) {
  const installed = services.get(service) ?? fail('ForeignRunStateService');
  validateRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const requestFacts = Object.freeze({
    stage: 'request',
    indexKey,
    principalId: request.principalId,
    purpose: request.purpose,
  });
  if (await installed.authority!.authorizeRunState(requestFacts) !== true) {
    fail('RunStateAccessDenied');
  }
  let entry: CommittedEntry | undefined, selectedIndex: object | undefined;
  if (installed.readCommittedPublication !== undefined) {
    const selected = await Reflect.apply(installed.readCommittedPublication, installed.store, [indexKey]);
    if (selected === undefined) return undefined;
    if (!exactKeys(selected, ['entry', 'index']) || selected.entry === null ||
        typeof selected.entry !== 'object' || selected.index === null || typeof selected.index !== 'object') {
      fail('InvalidCommittedPublicationState');
    }
    entry = selected.entry;
    selectedIndex = selected.index;
  } else {
    entry = await installed.store.confirmCommittedIndex(indexKey);
    if (entry === undefined) return undefined;
  }
  const [index, record] = await Promise.all([
    selectedIndex ?? installed.store.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry'),
    installed.store.latestRecordContract(entry.publication_attempt_cid),
  ]);
  try {
    if (installed.control.projectCommittedPublicationState(record, index) !==
        'succeeded') {
      fail('InvalidCommittedPublicationState');
    }
  } catch (error) {
    if (error instanceof RunStateAccessError) throw error;
    fail('InvalidCommittedPublicationState', error);
  }
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const runDefinition = await installed.store.readPublicationContract(
    entry.run_definition_cid, 'run_definition',
  );
  const names = installed.control.manifestResultNames(
    manifest, installed.limits,
  );
  const context = Object.freeze({
    indexKey,
    entry,
    manifest,
    runDefinition,
    principalId: request.principalId,
    purpose: request.purpose,
  });
  const observations: ResultObservation[] = [];
  const clocks = new Map<string, ClockObservation>();
  for (const name of names) {
    observations.push(await observeResult(installed, context, name, clocks));
  }
  // Each Result carries its own checked observation sample, not a claim of
  // another durable floor. The aggregate uses the last observation without
  // clamping or hiding rollback. An empty inventory still has a read timestamp.
  const at = observations.length === 0 ? observedAt(installed.now)
    : observations.at(-1)!.observedAt;
  const wire = installed.control.issueSucceededRunState({
    runId: installed.control.runDefinitionRunId(runDefinition),
    updatedAt: at,
    declaredResults: names,
    observations,
  }, installed.limits);
  let state: WireRunState;
  try { state = JSON.parse(wire); }
  catch (error) { fail('InvalidRunStateControlResult', error); }
  if (await installed.authority!.authorizeRunState(Object.freeze({
    ...context,
    stage: 'response',
    state,
  })) !== true) {
    fail('RunStateAccessDenied');
  }
  return Object.freeze(state);
}

export async function inspectAuthorizedRunState(service: RunStateService, request: RunStateRequest) {
  const state = await observeAuthorizedRunState(service, request);
  if (state === undefined) fail('RunStateAccessDenied');
  return state;
}
