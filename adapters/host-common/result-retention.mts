// Common authorization and sequencing for mandatory durable Result deletion.
// MoonBit decides retention state. The Store owns physical reclamation and
// reports when active readers or failed cleanup still retain responsibility.

import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {PublicationContract} from '../store-local/publication-contract-store.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';

type Awaitable<T> = T | PromiseLike<T>;
type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type PublicationStore = Awaited<ReturnType<typeof openLocalPublicationStore>>;
type Entry = NonNullable<Awaited<ReturnType<PublicationStore['confirmCommittedIndex']>>>;
type StoreReads = Pick<PublicationStore,
  'confirmCommittedIndex' | 'readPublicationContract' | 'observeTrustedClock'>;
type ResultRetirementStore = StoreReads & Pick<PublicationStore, 'retireCommittedResult'>;
type MetadataRetirementStore = StoreReads & Pick<PublicationStore, 'retireCommittedPublicationMetadata'>;
type ExtensionStore = StoreReads & Pick<PublicationStore,
  'readCommittedResultRetentionExtension' | 'putCommittedResultRetentionExtension'>;

type RetentionControl = Readonly<{
  resultReadRetentionPolicyCid(manifest: PublicationContract, resultName: string): string;
  resultRetentionClockContractCid(retention: PublicationContract): string;
}>;
type ResultSelectionControl = RetentionControl & Readonly<{
  resultReadDefinitionCid(manifest: PublicationContract, resultName: string): string;
}>;
type ResultRetirementControl = ResultSelectionControl & Readonly<{
  resultReadAvailability(manifest: PublicationContract, resultName: string, retention: PublicationContract,
    observedAt: string): string;
}>;
type MetadataRetirementControl = RetentionControl & Readonly<{
  manifestResultNames(manifest: PublicationContract, limits: Limits): readonly string[];
  resultMetadataRetentionState(retention: PublicationContract, observedAt: string): string;
}>;
type ExtensionControl = ResultSelectionControl & Readonly<{
  issueResultRetentionExtension(base: PublicationContract, availableUntil: string, admittedAt: string,
    limits: Limits): PublicationContract;
  resultReadExtendedAvailability(manifest: PublicationContract, resultName: string, base: PublicationContract,
    extension: PublicationContract, observedAt: string): string;
}>;

type MetadataRequest = Readonly<{indexKey: WireRunRef; reason: string}>;
type ResultRequest = MetadataRequest & Readonly<{resultName: string}>;
type ExtensionRequest = ResultRequest & Readonly<{availableUntil: string}>;
type Observed<Request> = Request & Readonly<{observedAt: string}>;
type Requested<Request> = Observed<Request> & Readonly<{stage: 'request'}>;
type Committed = Readonly<{entry: Entry; manifest: PublicationContract}>;
type ResultDeletionFacts = Observed<ResultRequest> & Committed & Readonly<{
  stage: 'delete';
  retention: PublicationContract;
  resultDefinitionCid: string;
}>;
type MetadataDeletionFacts = Observed<MetadataRequest> & Committed & Readonly<{
  stage: 'delete';
  resultNames: readonly string[];
  retentions: readonly PublicationContract[];
}>;
type ExtensionFacts = Observed<ExtensionRequest> & Committed & Readonly<{
  stage: 'extend';
  base: PublicationContract;
  current: PublicationContract | undefined;
  extension: PublicationContract;
  resultDefinitionCid: string;
}>;
type ResultAuthorityConfiguration = Readonly<{
  authorizeResultDeletion(facts: Requested<ResultRequest> | ResultDeletionFacts): Awaitable<boolean>;
}>;
type MetadataAuthorityConfiguration = Readonly<{
  authorizeMetadataDeletion(facts: Requested<MetadataRequest> | MetadataDeletionFacts): Awaitable<boolean>;
}>;
type ExtensionAuthorityConfiguration = Readonly<{
  authorizeResultExtension(facts: Requested<ExtensionRequest> | ExtensionFacts): Awaitable<boolean>;
}>;

declare const authorityBrand: unique symbol;
declare const serviceBrand: unique symbol;
type Kind = 'result' | 'metadata' | 'extension';
type Authority<Scope extends Kind> = Readonly<{[authorityBrand]: Scope}>;
type Service<Scope extends Kind> = Readonly<{[serviceBrand]: Scope}>;
type ServiceConfiguration<Scope extends Kind, Store, Control> = Readonly<{
  store: Store;
  control: Control;
  authority: Authority<Scope>;
  now: () => unknown;
  limits: Limits;
}>;
type Installed<Config, AuthorityConfiguration> = Omit<Config, 'authority'> &
  Readonly<{authority: AuthorityConfiguration}>;
type ResultConfiguration = ServiceConfiguration<'result', ResultRetirementStore, ResultRetirementControl>;
type MetadataConfiguration = ServiceConfiguration<'metadata', MetadataRetirementStore, MetadataRetirementControl>;
type ExtensionConfiguration = ServiceConfiguration<'extension', ExtensionStore, ExtensionControl>;
type CodedCause = Readonly<{code?: unknown}> | null | undefined;

const authorities = new WeakMap<Authority<'result'>, ResultAuthorityConfiguration>();
const services = new WeakMap<Service<'result'>, Installed<ResultConfiguration, ResultAuthorityConfiguration>>();
const extensionAuthorities = new WeakMap<Authority<'extension'>, ExtensionAuthorityConfiguration>();
const extensionServices = new WeakMap<Service<'extension'>, Installed<ExtensionConfiguration, ExtensionAuthorityConfiguration>>();
const metadataAuthorities = new WeakMap<Authority<'metadata'>, MetadataAuthorityConfiguration>();
const metadataServices = new WeakMap<Service<'metadata'>, Installed<MetadataConfiguration, MetadataAuthorityConfiguration>>();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value: unknown, keys: readonly string[]) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = (value: number) => Number.isSafeInteger(value) && value > 0;

export class ResultRetentionError extends Error {
  declare readonly code: string;
  declare readonly primaryFailure: unknown;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw new ResultRetentionError(code, cause); };

export function installResultRetentionAuthority(configuration: ResultAuthorityConfiguration): Authority<'result'> {
  if (!exactKeys(configuration, ['authorizeResultDeletion']) ||
      typeof configuration.authorizeResultDeletion !== 'function') {
    fail('InvalidResultRetentionAuthority');
  }
  const authority = Object.freeze({}) as Authority<'result'>;
  authorities.set(authority, Object.freeze({
    authorizeResultDeletion: configuration.authorizeResultDeletion,
  }));
  return authority;
}

export function installResultRetentionExtensionAuthority(configuration: ExtensionAuthorityConfiguration): Authority<'extension'> {
  if (!exactKeys(configuration, ['authorizeResultExtension']) ||
      typeof configuration.authorizeResultExtension !== 'function') {
    fail('InvalidResultRetentionExtensionAuthority');
  }
  const authority = Object.freeze({}) as Authority<'extension'>;
  extensionAuthorities.set(authority, Object.freeze({
    authorizeResultExtension: configuration.authorizeResultExtension,
  }));
  return authority;
}

export function installMetadataRetentionAuthority(configuration: MetadataAuthorityConfiguration): Authority<'metadata'> {
  if (!exactKeys(configuration, ['authorizeMetadataDeletion']) ||
      typeof configuration.authorizeMetadataDeletion !== 'function') {
    fail('InvalidMetadataRetentionAuthority');
  }
  const authority = Object.freeze({}) as Authority<'metadata'>;
  metadataAuthorities.set(authority, Object.freeze({
    authorizeMetadataDeletion: configuration.authorizeMetadataDeletion,
  }));
  return authority;
}

export function installResultRetentionService(configuration: ResultConfiguration): Service<'result'> {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.retireCommittedResult !== 'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultReadDefinitionCid !== 'function' ||
      typeof configuration.control.resultReadAvailability !== 'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      !authorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidResultRetentionService');
  }
  const service = Object.freeze({}) as Service<'result'>;
  services.set(service, Object.freeze({
    store: configuration.store,
    control: configuration.control,
    authority: authorities.get(configuration.authority)!,
    now: configuration.now,
    limits: Object.freeze({...configuration.limits}),
  }));
  return service;
}

export function installResultRetentionExtensionService(configuration: ExtensionConfiguration): Service<'extension'> {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.readCommittedResultRetentionExtension !==
        'function' ||
      typeof configuration.store.putCommittedResultRetentionExtension !==
        'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultReadDefinitionCid !== 'function' ||
      typeof configuration.control.issueResultRetentionExtension !==
        'function' ||
      typeof configuration.control.resultReadExtendedAvailability !==
        'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      !extensionAuthorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidResultRetentionExtensionService');
  }
  const service = Object.freeze({}) as Service<'extension'>;
  extensionServices.set(service, Object.freeze({
    store: configuration.store,
    control: configuration.control,
    authority: extensionAuthorities.get(configuration.authority)!,
    now: configuration.now,
    limits: Object.freeze({...configuration.limits}),
  }));
  return service;
}

export function installMetadataRetentionService(configuration: MetadataConfiguration): Service<'metadata'> {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.retireCommittedPublicationMetadata !==
        'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.manifestResultNames !== 'function' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultMetadataRetentionState !==
        'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      !metadataAuthorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidMetadataRetentionService');
  }
  const service = Object.freeze({}) as Service<'metadata'>;
  metadataServices.set(service, Object.freeze({
    store: configuration.store,
    control: configuration.control,
    authority: metadataAuthorities.get(configuration.authority)!,
    now: configuration.now,
    limits: Object.freeze({...configuration.limits}),
  }));
  return service;
}

function validateRequest(request: ResultRequest) {
  if (!exactKeys(request, [
    'indexKey', 'resultName', 'reason',
  ]) || !exactKeys(request.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.resultName !== 'string' ||
      request.resultName.length === 0 ||
      typeof request.reason !== 'string' || request.reason.length === 0) {
    fail('InvalidResultRetentionRequest');
  }
}

function observedAt(now: () => unknown) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidResultRetentionClock');
  }
  return value;
}

export async function retireExpiredResult(service: Service<'result'>, request: ResultRequest) {
  const installed = services.get(service) ??
    fail('ForeignResultRetentionService');
  validateRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const requestedAt = observedAt(installed.now);
  const requestFacts: Requested<ResultRequest> = Object.freeze({
    stage: 'request',
    indexKey,
    resultName: request.resultName,
    reason: request.reason,
    observedAt: requestedAt,
  });
  if (await installed.authority.authorizeResultDeletion(requestFacts) !==
      true) {
    fail('ResultRetentionDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('ResultRetentionDenied');
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const retentionCid =
    installed.control.resultReadRetentionPolicyCid(
      manifest, request.resultName,
    );
  const retention = await installed.store.readPublicationContract(
    retentionCid, 'result_retention_policy',
  );
  const clockCid = installed.control.resultRetentionClockContractCid(
    retention,
  );
  await installed.store.observeTrustedClock(clockCid, requestedAt);
  if (installed.control.resultReadAvailability(
    manifest, request.resultName, retention, requestedAt,
  ) !== 'delete_due') {
    fail('ResultDeletionNotDue');
  }
  const resultDefinitionCid =
    installed.control.resultReadDefinitionCid(
      manifest, request.resultName,
    );
  if (await installed.authority.authorizeResultDeletion(Object.freeze({
    ...requestFacts,
    stage: 'delete',
    entry,
    manifest,
    retention,
    resultDefinitionCid,
  })) !== true) {
    fail('ResultRetentionDenied');
  }
  const retired = await installed.store.retireCommittedResult(
    indexKey, resultDefinitionCid,
  );
  return Object.freeze({
    resultName: request.resultName,
    resultDefinitionCid,
    observedAt: requestedAt,
    cleanupPending: retired.cleanup.status().pending,
    cleanupHandle: retired.cleanup,
  });
}

function validateMetadataRequest(request: MetadataRequest) {
  if (!exactKeys(request, ['indexKey', 'reason']) ||
      !exactKeys(request.indexKey, [
        'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
      ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.reason !== 'string' || request.reason.length === 0) {
    fail('InvalidMetadataRetentionRequest');
  }
}

export async function retireExpiredPublicationMetadata(service: Service<'metadata'>, request: MetadataRequest) {
  const installed = metadataServices.get(service) ??
    fail('ForeignMetadataRetentionService');
  validateMetadataRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const observed = observedAt(installed.now);
  const requestFacts: Requested<MetadataRequest> = Object.freeze({
    stage: 'request',
    indexKey,
    reason: request.reason,
    observedAt: observed,
  });
  if (await installed.authority.authorizeMetadataDeletion(requestFacts) !==
      true) {
    fail('MetadataRetentionDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('MetadataRetentionDenied');
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const names = installed.control.manifestResultNames(
    manifest, installed.limits,
  );
  if (!Array.isArray(names) || names.length === 0) {
    fail('InvalidMetadataRetentionInventory');
  }
  const retentions: PublicationContract[] = [];
  for (const resultName of names) {
    const retentionCid = installed.control.resultReadRetentionPolicyCid(
      manifest, resultName,
    );
    const retention = await installed.store.readPublicationContract(
      retentionCid, 'result_retention_policy',
    );
    const clockCid = installed.control.resultRetentionClockContractCid(
      retention,
    );
    await installed.store.observeTrustedClock(clockCid, observed);
    if (installed.control.resultMetadataRetentionState(
      retention, observed,
    ) !== 'delete_due') {
      fail('MetadataDeletionNotDue');
    }
    retentions.push(retention);
  }
  if (await installed.authority.authorizeMetadataDeletion(Object.freeze({
    ...requestFacts,
    stage: 'delete',
    entry,
    manifest,
    resultNames: Object.freeze([...names]),
    retentions: Object.freeze(retentions),
  })) !== true) {
    fail('MetadataRetentionDenied');
  }
  const retired = await installed.store.retireCommittedPublicationMetadata(
    indexKey, observed,
  );
  return Object.freeze({
    observedAt: observed,
    cleanupPending: retired.cleanup.status().pending,
    cleanupHandle: retired.cleanup,
  });
}

function validateExtensionRequest(request: ExtensionRequest) {
  if (!exactKeys(request, [
    'indexKey', 'resultName', 'availableUntil', 'reason',
  ]) || !exactKeys(request.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.resultName !== 'string' ||
      request.resultName.length === 0 ||
      typeof request.availableUntil !== 'string' ||
      request.availableUntil.length === 0 ||
      typeof request.reason !== 'string' || request.reason.length === 0) {
    fail('InvalidResultRetentionExtensionRequest');
  }
}

export async function extendResultRetention(service: Service<'extension'>, request: ExtensionRequest) {
  const installed = extensionServices.get(service) ??
    fail('ForeignResultRetentionExtensionService');
  validateExtensionRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const admittedAt = observedAt(installed.now);
  const requestFacts: Requested<ExtensionRequest> = Object.freeze({
    stage: 'request',
    indexKey,
    resultName: request.resultName,
    availableUntil: request.availableUntil,
    reason: request.reason,
    observedAt: admittedAt,
  });
  if (await installed.authority.authorizeResultExtension(requestFacts) !==
      true) {
    fail('ResultRetentionExtensionDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('ResultRetentionExtensionDenied');
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const baseCid = installed.control.resultReadRetentionPolicyCid(
    manifest, request.resultName,
  );
  const base = await installed.store.readPublicationContract(
    baseCid, 'result_retention_policy',
  );
  const resultDefinitionCid = installed.control.resultReadDefinitionCid(
    manifest, request.resultName,
  );
  const clockCid = installed.control.resultRetentionClockContractCid(base);
  await installed.store.observeTrustedClock(clockCid, admittedAt);
  for (let attempt = 0; attempt < 3; attempt++) {
    let current;
    try {
      current = await installed.store.readCommittedResultRetentionExtension(
        indexKey, resultDefinitionCid,
      );
    } catch (error) {
      if ((error as CodedCause)?.code === 'PublicationObjectMissing') {
        fail('ResultRetentionExtensionUnavailable', error);
      }
      throw error;
    }
    const effective = current?.extension ?? base;
    if (current !== undefined) {
      installed.control.resultReadExtendedAvailability(
        manifest, request.resultName, base, effective, admittedAt,
      );
    }
    let extension;
    try {
      extension = installed.control.issueResultRetentionExtension(
        effective,
        request.availableUntil,
        admittedAt,
        installed.limits,
      );
      if (installed.control.resultReadExtendedAvailability(
        manifest, request.resultName, base, extension, admittedAt,
      ) !== 'available') {
        fail('ResultRetentionExtensionNotAvailable');
      }
    } catch (error) {
      fail('ResultRetentionExtensionNotAllowed', error);
    }
    if (await installed.authority.authorizeResultExtension(Object.freeze({
      ...requestFacts,
      stage: 'extend',
      entry,
      manifest,
      base,
      current: current?.extension,
      extension,
      resultDefinitionCid,
    })) !== true) {
      fail('ResultRetentionExtensionDenied');
    }
    try {
      const stored =
        await installed.store.putCommittedResultRetentionExtension(
          indexKey,
          resultDefinitionCid,
          current?.extension?.identity,
          extension,
          admittedAt,
        );
      return Object.freeze({
        resultName: request.resultName,
        resultDefinitionCid,
        admittedAt,
        extension: stored.extension,
        idempotent: stored.idempotent,
      });
    } catch (error) {
      if ((error as CodedCause)?.code !== 'PublicationRetentionExtensionConflict' ||
          attempt === 2) throw error;
    }
  }
  fail('ResultRetentionExtensionConflict');
}
