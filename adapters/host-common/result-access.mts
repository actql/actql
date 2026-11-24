// Installed Host authority for current Result read and egress admission.
// MoonBit owns grant and delivery semantics. This module keeps caller input
// separate from Host-owned authorization and delegates physical effects.
import {deliverPublishedResult} from './result-delivery.mjs';
import {validDeliveryAttemptLookup, validResultDescription,
  withinResultDescriptionLimits, resultDescriptionLimits} from
  '../../packages/client-wire/index.mjs';

import type {WireDeliveryAttemptLookup, WireResultDescription} from '../../packages/client-wire/index.js';
import type {ResultAccessAuthority, ResultAccessRequest, ResultAccessService} from '../../packages/run-host-core/result-access-public.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import type {PublicationContract} from '../store-local/publication-contract-store.mjs';
import type {publicationProgressControl} from './publication-progress-control.mjs';

type Awaitable<T> = T | PromiseLike<T>;
type ReadRequest = ResultAccessRequest;
type LookupRequest = Omit<ReadRequest, 'format'>;
type Limits = typeof resultDescriptionLimits;
type DescriptionRequest = ReadRequest & Limits;
type Delivery = Parameters<typeof deliverPublishedResult>[0];
type DeliveryWorkspace = NonNullable<Parameters<typeof deliverPublishedResult>[2]>;
type ReadDemand = DeliveryWorkspace['metadata'];
type RowAdmission = Awaited<ReturnType<DeliveryWorkspace['row']>>;
type AccessProgress = Pick<ReturnType<typeof publicationProgressControl>,
  'beginResultAccessProgress' | 'resultAccessProgressAction' |
  'recordResultAccessRequestAuthorization' | 'recordResultAccessResolution' |
  'recordResultAccessInitialAvailability' | 'recordResultAccessReadAdmission' |
  'recordResultAccessGrant'>;
type LocalStore = Awaited<ReturnType<typeof openLocalPublicationStore>>;
type Store = Pick<Delivery['store'], 'confirmCommittedIndex' | 'readPublicationContract'> &
  Partial<Delivery['store']> &
  Pick<LocalStore, 'readCommittedResultRetentionExtension' | 'observeTrustedClock'> &
  Partial<Pick<LocalStore, 'readCommittedPublication' | 'sampleTrustedClock' | 'lookupDeliveryAttempt' |
    'readCommittedResultDescriptionEvidence' | 'consumeManifestReadGrant'>>;
type SelectedPublication = NonNullable<Awaited<ReturnType<NonNullable<Store['readCommittedPublication']>>>>;
type Entry = SelectedPublication['entry'];
type RetentionExtension = Awaited<ReturnType<Store['readCommittedResultRetentionExtension']>>;
type Admission = Readonly<{
  authorizationContextCid: string;
  dataCeilingCid: string;
  egressAdmissionCid: string;
  expiresAt: string;
  maxBytes: number;
  maxUses: number;
}>;
type ReadGrantInput = Admission & Pick<ReadRequest, 'principalId' | 'purpose'> &
  Readonly<{resultNames: readonly string[]; formats: readonly ReadRequest['format'][]}>;
type ManifestGrantInput = Omit<Admission, 'egressAdmissionCid'> & Pick<ReadRequest, 'principalId' | 'purpose'>;
type Control = AccessProgress & Pick<Delivery['control'], 'resultReadGrantValidAt'> & Partial<Delivery['control']> &
  Readonly<{
    issueResultReadGrant(index: PublicationContract, manifest: PublicationContract,
      request: ReadGrantInput, limits: Limits): PublicationContract;
    resultReadRetentionPolicyCid(manifest: PublicationContract, resultName: string): string;
    resultReadDefinitionCid(manifest: PublicationContract, resultName: string): string;
    resultReadAvailability(manifest: PublicationContract, resultName: string,
      retention: PublicationContract, at: string): string;
    resultReadExtendedAvailability(manifest: PublicationContract, resultName: string,
      base: PublicationContract, extension: PublicationContract, at: string): string;
    resultRetentionClockContractCid(retention: PublicationContract): string;
    trustedClockNotBefore?(previous: string | undefined, observedAt: string): boolean;
    resultMetadataRetentionState?(retention: PublicationContract, at: string): string;
    describeCommittedResult?(index: PublicationContract, manifest: PublicationContract,
      resultName: string, bindings: readonly PublicationContract[], definition: PublicationContract,
      schema: string, format: ReadRequest['format'], limits: Limits): Omit<WireResultDescription, 'ref'>;
    issueManifestReadGrant?(index: PublicationContract, manifest: PublicationContract,
      request: ManifestGrantInput, limits: Limits): PublicationContract;
    manifestReadGrantAllowsBytes?(grant: PublicationContract, bytes: number): boolean;
    manifestReadGrantValidAt?(grant: PublicationContract, at: string): boolean;
  }>;
type DescriptionFacts = ReadRequest & Readonly<{
  index: PublicationContract; manifest: PublicationContract;
  retention: PublicationContract; observedAt: string;
}>;
type ReadFacts = DescriptionFacts & Readonly<{baseRetention: PublicationContract}>;
type AuthorizedFacts = Readonly<{
  grant: PublicationContract; authorizationContextCid: string; egressAdmissionCid: string;
}>;
type DeliveryFacts = Parameters<Delivery['authorize']>[0];
type DescriptionAuthorization = (facts: (ReadRequest & Readonly<{stage: 'request'}>) |
  (DescriptionFacts & AuthorizedFacts & Readonly<{stage: 'read' | 'response'}>),
  request: ReadRequest) => Awaitable<boolean>;
type AuthorityConfiguration = Readonly<{
  authorizeResultReadRequest(facts: ReadRequest, request: ReadRequest): Awaitable<boolean>;
  admitResultRead(facts: ReadFacts, request: ReadRequest): Awaitable<Admission>;
  authorizeResultRead(facts: ReadFacts & AuthorizedFacts & Readonly<{delivery: DeliveryFacts}>,
    request: ReadRequest): Awaitable<boolean>;
  authorizeDeliveryAttemptLookup?(facts: LookupRequest, request: LookupRequest): Awaitable<boolean>;
  authorizeResultDescription?: DescriptionAuthorization;
  admitResultDescription?(facts: DescriptionFacts, request: ReadRequest): Awaitable<Admission>;
}>;
type ReadWorkspace = Readonly<{
  begin(request: ReadRequest, control: Control): unknown;
  prepare(request: ReadRequest, metadata: Parameters<DeliveryWorkspace['prepare']>[0],
    limits: Limits, frameLimits: Delivery['frameLimits']): number;
  row<Unit extends number | string>(request: ReadRequest, units: Unit):
    Unit extends number ? RowAdmission : Awaitable<RowAdmission>;
  close(request: ReadRequest, failure: unknown): unknown;
  metadata(request: ReadRequest, ...args: Parameters<ReadDemand>): ReturnType<ReadDemand>;
  metadataRetain(request: ReadRequest, ...args: Parameters<ReadDemand['retain']>): unknown;
  metadataData(request: ReadRequest, ...args: Parameters<ReadDemand['data']>): unknown;
  metadataRelease(request: ReadRequest, ...args: Parameters<ReadDemand['release']>): unknown;
  metadataFinish(request: ReadRequest): unknown;
  serializer(request: ReadRequest, value: unknown): unknown;
}>;
type ServiceConfiguration = Readonly<{
  store: Store;
  control: Control;
  authority: ResultAccessAuthority;
  now: Delivery['now'];
  createDigest: Delivery['createDigest'];
  limits: Limits;
  frameLimits: Delivery['frameLimits'];
  readWorkspace?: ReadWorkspace;
}>;
type Installed = Omit<ServiceConfiguration, 'authority'> & Readonly<{
  authority: AuthorityConfiguration;
  readCommittedPublication: Store['readCommittedPublication'];
}>;
type CodedCause = Readonly<{code?: unknown}> | null | undefined;

const authorities = new WeakMap<ResultAccessAuthority, AuthorityConfiguration>();
const services = new WeakMap<ResultAccessService, Installed>();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value: unknown, keys: readonly string[]) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = (value: number) => Number.isSafeInteger(value) && value > 0;
const indexKeyFields = [
  'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
];

function ownedResultRequest(input: ReadRequest, delivery: true): ReadRequest;
function ownedResultRequest(input: LookupRequest, delivery: false): LookupRequest;
// Copy only the typed request fields before any authorization or Store await.
// This leaves in-process grants and MoonBit handles on their original owners.
function ownedResultRequest(input: ReadRequest | LookupRequest, delivery: boolean) {
  const fields = [
    'indexKey', 'principalId', 'purpose', 'resultName', 'attemptId',
    ...(delivery ? ['format'] : []),
  ];
  if (!exactKeys(input, fields) ||
      !exactKeys(input.indexKey, indexKeyFields)) {
    fail('InvalidResultAccessRequest');
  }
  const sourceKey = input.indexKey;
  const indexKey = Object.freeze({
    namespaceId: sourceKey.namespaceId,
    authorityScopeCid: sourceKey.authorityScopeCid,
    runDefinitionCid: sourceKey.runDefinitionCid,
  });
  return Object.freeze({
    indexKey,
    principalId: input.principalId,
    purpose: input.purpose,
    resultName: input.resultName,
    attemptId: input.attemptId,
    ...(delivery ? {format: (input as ReadRequest).format} : {}),
  });
}

export class ResultAccessError extends Error {
  declare readonly code: string;
  declare readonly primaryFailure: unknown;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw new ResultAccessError(code, cause); };

function validateAuthority(configuration: AuthorityConfiguration) {
  const {authorizeResultDescription, admitResultDescription, ...reads} =
    configuration ?? {};
  if ((authorizeResultDescription !== undefined ||
      admitResultDescription !== undefined) &&
      (typeof authorizeResultDescription !== 'function' ||
       typeof admitResultDescription !== 'function')) {
    fail('InvalidResultAccessAuthority');
  }
  if (!(exactKeys(reads, [
    'authorizeResultReadRequest', 'admitResultRead',
    'authorizeResultRead',
  ]) || exactKeys(reads, [
    'authorizeResultReadRequest', 'admitResultRead',
    'authorizeResultRead', 'authorizeDeliveryAttemptLookup',
  ])) || typeof configuration.authorizeResultReadRequest !== 'function' ||
      typeof configuration.admitResultRead !== 'function' ||
      typeof configuration.authorizeResultRead !== 'function' ||
      configuration.authorizeDeliveryAttemptLookup !== undefined &&
        typeof configuration.authorizeDeliveryAttemptLookup !== 'function') {
    fail('InvalidResultAccessAuthority');
  }
}

export function installResultAccessAuthority(configuration: AuthorityConfiguration): ResultAccessAuthority {
  validateAuthority(configuration);
  const authority = Object.freeze({}) as ResultAccessAuthority;
  authorities.set(authority, Object.freeze({
    authorizeResultReadRequest: configuration.authorizeResultReadRequest,
    admitResultRead: configuration.admitResultRead,
    authorizeResultRead: configuration.authorizeResultRead,
    authorizeDeliveryAttemptLookup:
      configuration.authorizeDeliveryAttemptLookup,
    authorizeResultDescription: configuration.authorizeResultDescription,
    admitResultDescription: configuration.admitResultDescription,
  }));
  return authority;
}

export async function describeAuthorizedResult(
  service: ResultAccessService, input: DescriptionRequest, signal?: AbortSignal,
): Promise<WireResultDescription> {
  const installed = services.get(service) ?? fail('ForeignResultAccessService');
  const {maxWireBytes, maxNodes, maxDepth, ...readInput} = input ?? {};
  const request = ownedResultRequest(readInput, true);
  validateRequest(request);
  const limits = Object.freeze({maxWireBytes, maxNodes, maxDepth});
  if (!(Object.keys(resultDescriptionLimits) as (keyof Limits)[]).every(key =>
    positive(limits[key]) && limits[key] <= resultDescriptionLimits[key])) {
    fail('InvalidResultAccessRequest');
  }
  const {store, control, authority} = installed;
  if (typeof authority.authorizeResultDescription !== 'function' ||
      typeof authority.admitResultDescription !== 'function' ||
      typeof store.readCommittedResultDescriptionEvidence !== 'function' ||
      typeof store.consumeManifestReadGrant !== 'function' ||
      ['describeCommittedResult', 'resultMetadataRetentionState',
        'issueManifestReadGrant', 'manifestReadGrantAllowsBytes',
        'manifestReadGrantValidAt'].some(name =>
        typeof control[name as keyof Control] !== 'function')) {
    fail('ClientOperationUnavailable');
  }
  signal?.throwIfAborted();
  const authorize = async (facts: Parameters<DescriptionAuthorization>[0]) => {
    let allowed;
    try { allowed = await authority.authorizeResultDescription!(facts, request); }
    catch { fail('ResultAccessDenied'); }
    if (allowed !== true) fail('ResultAccessDenied');
    signal?.throwIfAborted();
  };
  await authorize(Object.freeze({...request, stage: 'request'}));
  let entry, index, manifest, retention, evidence;
  try {
    const selected = await readSelectedPublication(installed, request.indexKey);
    if (selected === undefined) fail('ResultAccessDenied');
    ({entry, index} = selected);
    manifest = await store.readPublicationContract(
      entry.result_manifest_cid, 'result_manifest');
    const definitionCid = control.resultReadDefinitionCid(
      manifest, request.resultName);
    retention = await store.readPublicationContract(
      control.resultReadRetentionPolicyCid(manifest, request.resultName),
      'result_retention_policy');
    evidence = installed.readCommittedPublication === undefined
      ? await store.readCommittedResultDescriptionEvidence(request.indexKey, definitionCid)
      : await store.readCommittedResultDescriptionEvidence(request.indexKey, definitionCid, selected);
  } catch (error) {
    if ((error as CodedCause)?.code === 'PublicationLookupDenied') fail('ResultAccessDenied');
    if ((['PublicationObjectMissing', 'PublicationContractMissing'] as readonly unknown[])
      .includes((error as CodedCause)?.code)) {
      fail('ResultDescriptionUnavailable', error);
    }
    throw error;
  }
  const effectiveRetention = evidence.retained?.extension ?? retention;
  const clockCid = control.resultRetentionClockContractCid(retention);
  let checkedAt = await sampleTrustedClock(installed, clockCid);
  const checkRetained = async () => {
    // Trusted internal reads/awaits consume this operation's one accepted
    // durable floor. Expiry and rollback remain cheap local time checks.
    const at = observedAt(installed.now);
    if (typeof control.trustedClockNotBefore === 'function' &&
        !control.trustedClockNotBefore(checkedAt, at)) {
      fail('InvalidResultAccessClock');
    }
    checkedAt = at;
    // Validate the stored extension's exact base binding using its owner.
    if (evidence.retained !== undefined) {
      control.resultReadExtendedAvailability(manifest, request.resultName,
        retention, effectiveRetention, at);
    }
    if (control.resultMetadataRetentionState!(effectiveRetention, at) !==
        'retained') fail('ResultDescriptionUnavailable');
    return at;
  };
  const at = await checkRetained();
  const facts = Object.freeze({...request, index, manifest,
    retention: effectiveRetention, observedAt: at});
  const admission = await authority.admitResultDescription(facts, request);
  validateAdmission(admission);
  // Metadata consumes the existing Manifest grant, not a payload delivery.
  const grant = control.issueManifestReadGrant!(index, manifest, {
    principalId: request.principalId, purpose: request.purpose,
    dataCeilingCid: admission.dataCeilingCid,
    maxBytes: admission.maxBytes, maxUses: admission.maxUses,
    expiresAt: admission.expiresAt,
    authorizationContextCid: admission.authorizationContextCid,
  }, installed.limits);
  const authorizedFacts = Object.freeze({...facts, grant,
    authorizationContextCid: admission.authorizationContextCid,
    egressAdmissionCid: admission.egressAdmissionCid});
  await authorize(Object.freeze({...authorizedFacts, stage: 'read'}));
  const response = Object.freeze({ref: request.indexKey,
    ...control.describeCommittedResult!(index, manifest, request.resultName,
      evidence.bindings, evidence.definition, evidence.schemaWire,
      request.format, installed.limits)});
  if (!withinResultDescriptionLimits(response, limits)) {
    fail('ResultDescriptionTooLarge');
  }
  if (!validResultDescription(response, {ref: request.indexKey,
    resultName: request.resultName, format: request.format}, limits)) {
    fail('InvalidResultDescription');
  }
  const byteCount = new TextEncoder().encode(JSON.stringify(response)).length;
  if (!control.manifestReadGrantAllowsBytes!(grant, byteCount) ||
      !control.manifestReadGrantValidAt!(grant, await checkRetained())) {
    fail('ResultAccessDenied');
  }
  await store.consumeManifestReadGrant(grant.wire, request.attemptId);
  await authorize(Object.freeze({...authorizedFacts, stage: 'response'}));
  if (!control.manifestReadGrantValidAt!(grant, await checkRetained())) {
    fail('ResultAccessDenied');
  }
  if ((await store.confirmCommittedIndex(request.indexKey))
        ?.public_index_entry_cid !== entry.public_index_entry_cid) {
    fail('ResultDescriptionUnavailable');
  }
  signal?.throwIfAborted();
  return response;
}

function validateServiceConfiguration(configuration: ServiceConfiguration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'createDigest', 'limits',
    'frameLimits',
    ...(Object.hasOwn(configuration ?? {}, 'readWorkspace') ? ['readWorkspace'] : []),
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      configuration.store.sampleTrustedClock !== undefined &&
        typeof configuration.store.sampleTrustedClock !== 'function' ||
      typeof configuration.store.readCommittedResultRetentionExtension !==
        'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      configuration.store.sampleTrustedClock !== undefined &&
        typeof configuration.control.trustedClockNotBefore !== 'function' ||
      typeof configuration.control.issueResultReadGrant !== 'function' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultReadAvailability !== 'function' ||
      typeof configuration.control.resultReadExtendedAvailability !==
        'function' ||
      typeof configuration.control.resultReadDefinitionCid !== 'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      typeof configuration.control.resultReadGrantValidAt !== 'function' ||
      typeof configuration.control.beginResultAccessProgress !== 'function' ||
      typeof configuration.control.resultAccessProgressAction !== 'function' ||
      typeof configuration.control
        .recordResultAccessRequestAuthorization !== 'function' ||
      typeof configuration.control.recordResultAccessResolution !==
        'function' ||
      typeof configuration.control.recordResultAccessInitialAvailability !==
        'function' ||
      typeof configuration.control.recordResultAccessReadAdmission !==
        'function' ||
      typeof configuration.control.recordResultAccessGrant !== 'function' ||
      !authorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      typeof configuration.createDigest !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive) ||
      !exactKeys(configuration.frameLimits, [
        'maxRowBytes', 'maxDepth', 'maxFrameBytes',
      ]) || !Object.values(configuration.frameLimits).every(positive)) {
    fail('InvalidResultAccessService');
  }
}

export function installResultAccessService(configuration: ServiceConfiguration): ResultAccessService {
  validateServiceConfiguration(configuration);
  let readWorkspace: ReadWorkspace | undefined;
  if (configuration.readWorkspace !== undefined) {
    const receiver = configuration.readWorkspace;
    if (receiver === null || typeof receiver !== 'object') fail('InvalidResultAccessWorkspace');
    const callbacks = {} as Record<keyof ReadWorkspace, (...args: unknown[]) => unknown>;
    for (const name of ['begin', 'prepare', 'row', 'close', 'metadata', 'metadataRetain', 'metadataData', 'metadataRelease', 'metadataFinish', 'serializer'] as const) {
      const field = Object.getOwnPropertyDescriptor(receiver, name);
      if (field === undefined || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
        fail('InvalidResultAccessWorkspace');
      }
      callbacks[name] = (...args) => Reflect.apply(field.value, receiver, args);
    }
    readWorkspace = Object.freeze(callbacks) as ReadWorkspace;
  }
  const readCommittedPublication = configuration.store.readCommittedPublication;
  if (readCommittedPublication !== undefined && typeof readCommittedPublication !== 'function') {
    fail('InvalidResultAccessService');
  }
  const service = Object.freeze({}) as ResultAccessService;
  services.set(service, Object.freeze({
    store: configuration.store,
    readCommittedPublication,
    control: configuration.control,
    authority: authorities.get(configuration.authority)!,
    now: configuration.now,
    createDigest: configuration.createDigest,
    limits: Object.freeze({...configuration.limits}),
    frameLimits: Object.freeze({...configuration.frameLimits}),
    readWorkspace,
  }));
  return service;
}

async function readSelectedPublication(
  installed: Installed, indexKey: ReadRequest['indexKey'], readDemand?: ReadDemand,
): Promise<SelectedPublication | undefined> {
  if (installed.readCommittedPublication === undefined) {
    const entry = await installed.store.confirmCommittedIndex(indexKey, ...(readDemand === undefined ? [] : [readDemand] as [ReadDemand?]));
    if (entry === undefined) return undefined;
    const index = await installed.store.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry', ...(readDemand === undefined ? [] : [readDemand] as [ReadDemand?]));
    return {entry, index};
  }
  // This same Store read owns the selected Index's nominal admission. It is
  // not a permission or a successful-read cache across public operations.
  const selected: SelectedPublication | undefined = await Reflect.apply(installed.readCommittedPublication, installed.store, [indexKey, ...(readDemand === undefined ? [] : [readDemand] as [ReadDemand?])]);
  if (selected === undefined) return undefined;
  if (!exactKeys(selected, ['entry', 'index']) || selected.entry === null ||
      typeof selected.entry !== 'object' || selected.index === null || typeof selected.index !== 'object') {
    fail('InvalidCommittedPublicationState');
  }
  return selected;
}

export async function inspectAuthorizedDeliveryAttempt(
  service: ResultAccessService, input: LookupRequest,
): Promise<WireDeliveryAttemptLookup> {
  const installed = services.get(service) ?? fail('ForeignResultAccessService');
  const request = ownedResultRequest(input, false);
  if (typeof request.indexKey.namespaceId !== 'string' ||
      !request.indexKey.namespaceId ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.principalId !== 'string' || !request.principalId ||
      typeof request.purpose !== 'string' || !request.purpose ||
      typeof request.resultName !== 'string' || !request.resultName ||
      typeof request.attemptId !== 'string' || !request.attemptId ||
      request.attemptId.length > 256) {
    fail('InvalidResultAccessRequest');
  }
  const authorize = installed.authority.authorizeDeliveryAttemptLookup;
  if (typeof authorize !== 'function' ||
      typeof installed.store.lookupDeliveryAttempt !== 'function') {
    fail('ResultAttemptLookupUnavailable');
  }
  let allowed;
  try { allowed = await authorize(request, request); }
  catch { fail('ResultAccessDenied'); }
  if (allowed !== true) fail('ResultAccessDenied');
  const found = await installed.store.lookupDeliveryAttempt(request);
  try { allowed = await authorize(request, request); }
  catch { fail('ResultAccessDenied'); }
  if (allowed !== true) fail('ResultAccessDenied');
  if (found === undefined) return Object.freeze({kind: 'not_found'});
  const reply = Object.freeze({kind: 'found',
    attempt: found.attempt, record: found.record ?? null,
    hostReleaseReceipt: found.hostReleaseReceipt ?? null});
  if (!validDeliveryAttemptLookup(reply, {
    attemptId: request.attemptId,
    runDefinitionCid: request.indexKey.runDefinitionCid,
    resultName: request.resultName,
  })) {
    fail('InvalidDeliveryAttemptLookup');
  }
  return reply;
}

function validateRequest(request: ReadRequest) {
  if (!exactKeys(request, [
    'indexKey', 'principalId', 'purpose', 'resultName', 'format',
    'attemptId',
  ]) || !exactKeys(request.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.principalId !== 'string' ||
      request.principalId.length === 0 ||
      typeof request.purpose !== 'string' || request.purpose.length === 0 ||
      typeof request.resultName !== 'string' ||
      request.resultName.length === 0 ||
      !['json', 'jsonl', 'csv'].includes(request.format) ||
      typeof request.attemptId !== 'string' ||
      request.attemptId.length === 0) {
    fail('InvalidResultAccessRequest');
  }
}

function validateAdmission(admission: Admission) {
  if (!exactKeys(admission, [
    'authorizationContextCid', 'dataCeilingCid', 'egressAdmissionCid',
    'expiresAt', 'maxBytes', 'maxUses',
  ]) || !cidPattern.test(admission.authorizationContextCid) ||
      !cidPattern.test(admission.dataCeilingCid) ||
      !cidPattern.test(admission.egressAdmissionCid) ||
      typeof admission.expiresAt !== 'string' ||
      admission.expiresAt.length === 0 ||
      !Number.isSafeInteger(admission.maxBytes) || admission.maxBytes < 0 ||
      !positive(admission.maxUses)) {
    fail('InvalidResultReadAdmission');
  }
}

function observedAt(now: Delivery['now']) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidResultAccessClock');
  }
  return value;
}

// A concurrent physical Store may sample only after it reads its durable
// clock bound, and sample again after a CAS conflict. Use that exact accepted
// observation for semantic checks rather than an earlier caller sample.
// The explicit-observation fallback retains the existing Store contract.
async function sampleTrustedClock(installed: Installed, clockContractCid: string, suppliedAt?: string) {
  if (typeof installed.store.sampleTrustedClock === 'function') {
    const at = await installed.store.sampleTrustedClock(
      clockContractCid, () => observedAt(installed.now),
    );
    if (!installed.control.trustedClockNotBefore!(suppliedAt, at)) {
      fail('InvalidResultAccessClock');
    }
    return at;
  }
  const at = suppliedAt ?? observedAt(installed.now);
  await installed.store.observeTrustedClock(clockContractCid, at);
  return at;
}

export async function deliverAuthorizedResult(
  service: ResultAccessService,
  input: ReadRequest,
  sink: Delivery['sink'],
  signal?: AbortSignal,
) {
  const installed = services.get(service) ?? fail('ForeignResultAccessService');
  const request = ownedResultRequest(input, true);
  validateRequest(request);
  const workspace = installed.readWorkspace;
  if (workspace === undefined) {
    return deliverPreparedAuthorizedResult(installed, request, sink, signal);
  }
  // One real READ Request owns its constructors, including early refusal.
  // Its resource identity is distinct from the retired producing Run.
  workspace.begin(request, installed.control);
  let failure;
  try {
    const demand = Object.freeze(Object.assign((bytes: Parameters<ReadDemand>[0]) => workspace.metadata(request, bytes), {
      retain: (slot: number, original: PublicationContract, mode: number) => workspace.metadataRetain(request, slot, original, mode),
      data: (slot: number, nodes: number, textUnits: number) => workspace.metadataData(request, slot, nodes, textUnits),
      release: (slot: number) => workspace.metadataRelease(request, slot),
      finish: () => workspace.metadataFinish(request),
    }));
    return await deliverPreparedAuthorizedResult(installed, request, sink, signal,
      Object.freeze<DeliveryWorkspace>({
        prepare: metadata => workspace.prepare(request, metadata, installed.limits, installed.frameLimits),
        row: ((units: number | string) => workspace.row(request, units)) as DeliveryWorkspace['row'],
        metadata: demand,
        serializer: value => workspace.serializer(request, value),
      }));
  } catch (cause) {
    failure = cause;
    throw cause;
  } finally { workspace.close(request, failure); }
}

async function deliverPreparedAuthorizedResult(
  installed: Installed, request: ReadRequest, sink: Delivery['sink'], signal?: AbortSignal, workspace?: DeliveryWorkspace,
) {
  if (sink === null || typeof sink !== 'object' ||
      typeof sink.write !== 'function' ||
      typeof sink.finish !== 'function' || signal !== undefined &&
      (signal === null || typeof signal.throwIfAborted !== 'function')) {
    fail('InvalidResultAccessRequest');
  }
  signal?.throwIfAborted();
  const readDemand = workspace?.metadata;
  const demandArgument: [ReadDemand?] = readDemand === undefined ? [] : [readDemand];
  const progress = installed.control.beginResultAccessProgress();
  const requireAction = (expected: ReturnType<AccessProgress['resultAccessProgressAction']>) => {
    if (installed.control.resultAccessProgressAction(progress) !== expected) {
      fail('InvalidResultAccessProgress');
    }
  };
  requireAction('authorize_request');
  const indexKey = request.indexKey;
  let requestAuthorized = false;
  try {
    requestAuthorized = await installed.authority
      .authorizeResultReadRequest(Object.freeze({
        indexKey,
        principalId: request.principalId,
        purpose: request.purpose,
        resultName: request.resultName,
        format: request.format,
        attemptId: request.attemptId,
      }), request);
  } catch {
    installed.control.recordResultAccessRequestAuthorization(progress, false);
    fail('ResultAccessDenied');
  }
  signal?.throwIfAborted();
  installed.control.recordResultAccessRequestAuthorization(
    progress, requestAuthorized === true,
  );
  if (requestAuthorized !== true) fail('ResultAccessDenied');
  requireAction('resolve_committed_result');
  let entry: Entry | undefined;
  let index: PublicationContract;
  let manifest: PublicationContract;
  let retention: PublicationContract;
  let retained: RetentionExtension;
  try {
    const selected = await readSelectedPublication(installed, indexKey, readDemand);
    if (selected === undefined) {
      installed.control.recordResultAccessResolution(progress, false);
      fail('ResultAccessDenied');
    }
    ({entry, index} = selected);
    if (installed.readCommittedPublication === undefined) {
      readDemand?.retain(1, index, 1);
      readDemand?.finish();
    }
    manifest = await installed.store.readPublicationContract(
      entry.result_manifest_cid, 'result_manifest', ...demandArgument,
    );
    readDemand?.retain(2, manifest, 1);
    readDemand?.finish();
    const retentionPolicyCid =
      installed.control.resultReadRetentionPolicyCid(
        manifest, request.resultName,
      );
    retention = await installed.store.readPublicationContract(
      retentionPolicyCid, 'result_retention_policy', ...demandArgument,
    );
    readDemand?.retain(3, retention, 1);
    readDemand?.finish();
    const resultDefinitionCid = installed.control.resultReadDefinitionCid(
      manifest, request.resultName,
    );
    retained = installed.readCommittedPublication === undefined
      ? await installed.store.readCommittedResultRetentionExtension(indexKey, resultDefinitionCid, ...((readDemand === undefined ? [] : [undefined, readDemand]) as [unknown?, ReadDemand?]))
      : await installed.store.readCommittedResultRetentionExtension(indexKey, resultDefinitionCid, selected, ...demandArgument);
  } catch (error) {
    if (installed.control.resultAccessProgressAction(progress) ===
        'resolve_committed_result') {
      installed.control.recordResultAccessResolution(progress, false);
    }
    if ((error as CodedCause)?.code === 'PublicationObjectMissing') {
      fail('ResultUnavailable', error);
    }
    throw error;
  }
  installed.control.recordResultAccessResolution(progress, true);
  const availability = (observed: string) => retained === undefined
    ? installed.control.resultReadAvailability(
      manifest, request.resultName, retention, observed,
    )
    : installed.control.resultReadExtendedAvailability(
      manifest,
      request.resultName,
      retention,
      retained.extension,
      observed,
    );
  const clockContractCid =
    installed.control.resultRetentionClockContractCid(retention);
  const admittedAt = await sampleTrustedClock(installed, clockContractCid);
  const initiallyAvailable = availability(admittedAt) === 'available';
  requireAction('check_initial_availability');
  installed.control.recordResultAccessInitialAvailability(
    progress, initiallyAvailable,
  );
  if (!initiallyAvailable) {
    fail('ResultUnavailable');
  }
  const requestFacts = Object.freeze({
    indexKey,
    index,
    manifest,
    principalId: request.principalId,
    purpose: request.purpose,
    resultName: request.resultName,
    format: request.format,
    attemptId: request.attemptId,
    retention: retained?.extension ?? retention,
    baseRetention: retention,
    observedAt: admittedAt,
  });
  requireAction('admit_read');
  let admission;
  try {
    admission = await installed.authority.admitResultRead(requestFacts, request);
    validateAdmission(admission);
  } catch (error) {
    installed.control.recordResultAccessReadAdmission(progress, false);
    throw error;
  }
  installed.control.recordResultAccessReadAdmission(progress, true);
  requireAction('issue_grant');
  let grant;
  try {
    grant = installed.control.issueResultReadGrant(
      index,
      manifest,
      {
        resultNames: [request.resultName],
        formats: [request.format],
        principalId: request.principalId,
        purpose: request.purpose,
        dataCeilingCid: admission.dataCeilingCid,
        maxBytes: admission.maxBytes,
        maxUses: admission.maxUses,
        expiresAt: admission.expiresAt,
        authorizationContextCid: admission.authorizationContextCid,
        egressAdmissionCid: admission.egressAdmissionCid,
      },
      installed.limits,
    );
  } catch (error) {
    installed.control.recordResultAccessGrant(progress, false);
    throw error;
  }
  installed.control.recordResultAccessGrant(progress, true);
  requireAction('start_delivery');
  let checkedAt = admittedAt;
  const authorize = async (facts: DeliveryFacts) => {
    const at = observedAt(installed.now);
    if (typeof installed.control.trustedClockNotBefore === 'function' &&
        (!installed.control.trustedClockNotBefore(checkedAt, at) ||
         !installed.control.trustedClockNotBefore(facts.observedAt, at))) {
      fail('InvalidResultAccessClock');
    }
    checkedAt = at;
    if (availability(at) !== 'available') {
      return false;
    }
    const allowed = await installed.authority.authorizeResultRead(
      Object.freeze({
        ...requestFacts,
        grant,
        authorizationContextCid: admission.authorizationContextCid,
        egressAdmissionCid: admission.egressAdmissionCid,
        delivery: Object.freeze({...facts, observedAt: at}),
      }), request,
    );
    if (allowed !== true) return false;
    // Callback/dispatch time may cross expiry, but an internal stage does
    // not create another operation or require another durable clock write.
    const usableAt = observedAt(installed.now);
    if (typeof installed.control.trustedClockNotBefore === 'function' &&
        !installed.control.trustedClockNotBefore(checkedAt, usableAt)) {
      fail('InvalidResultAccessClock');
    }
    checkedAt = usableAt;
    return availability(usableAt) === 'available' &&
      installed.control.resultReadGrantValidAt(grant, usableAt);
  };
  entry = undefined;
  readDemand?.release(0);
  return deliverPublishedResult({
    store: installed.store as Delivery['store'],
    control: installed.control as Delivery['control'],
    indexKey,
    grant,
    resultName: request.resultName,
    format: request.format,
    attemptId: request.attemptId,
    limits: installed.limits,
    frameLimits: installed.frameLimits,
    now: installed.now,
    sink,
    createDigest: installed.createDigest,
    authorize,
    signal,
  }, Object.isFrozen(index) && Object.isFrozen(manifest)
    ? Object.freeze({store: installed.store as Delivery['store'], control: installed.control as Delivery['control'],
      index, manifest}) : undefined, workspace);
}
