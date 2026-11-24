import {runtimeField, runtimeIsError, runtimeIsBoxedNone, runtimeIsOk, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import * as owner from './dist/remote_coordinator_abi.js';

declare const ownerHandle: unique symbol;

export type BundleDistribution = {readonly [ownerHandle]: 'bundle-distribution'};

export type BundleHoldScope = {readonly [ownerHandle]: 'bundle-hold-scope'};

export type BundleHoldBinding = {readonly [ownerHandle]: 'bundle-hold-binding'};

export type BundleCustodyRequest = {readonly [ownerHandle]: 'bundle-custody-request'};

export type BundleCustodyResponse = {readonly [ownerHandle]: 'bundle-custody-response'};

export type BundleCustodyOperation = 'retain' | 'query' | 'release';

export type BundleCustodyObservation = 'retained' | 'fenced' | 'unresolved' | 'unavailable';

/** Exact scope for the caller's own hold on an explicitly permitted existing
 * bundle. These fields identify the request; they grant no permission. */
export interface BundleHoldScopeInput {
  distribution: BundleDistribution;
  coordinatorAuthority: string;
  workspaceId: string;
  authorityScopeCid: string;
  environment: string;
  setRevisionCid: string;
  runtimeBundleCid: string;
  siteKey: string;
  siteGeneration: number;
  attemptId: string;
}

export type Journal = {readonly [ownerHandle]: 'journal'};

export type DispatchRequest = {readonly [ownerHandle]: 'dispatch-request'};

export type EffectCheckpointReport = {readonly [ownerHandle]: 'effect-checkpoint-report'};

export type EffectCurrentQuery = {readonly [ownerHandle]: 'effect-current-query'};

export type EffectCurrentReply = {readonly [ownerHandle]: 'effect-current-reply'};

export type EffectCheckpointRefusal = 'authorization_denied' | 'scope_mismatch' | 'report_conflict';

export type EffectCheckpointReply = Readonly<{kind: 'accepted'} |
  {kind: 'refused'; reason: EffectCheckpointRefusal}>;

export type IntentAdmission = {readonly [ownerHandle]: 'intent-admission'};

export type IntentRecord = {readonly [ownerHandle]: 'intent-record'};

export type DurableRecord = {readonly [ownerHandle]: 'durable-record'};

export type Transition = {readonly [ownerHandle]: 'transition'};

export type DispatchResponse = {readonly [ownerHandle]: 'dispatch-response'};

export type CheckedOutputPlan = {readonly [ownerHandle]: 'checked-output-plan'};

export type OutputIntentAdmission = {
  readonly [ownerHandle]: 'output-intent-admission'
};

export type OutputRecord = {readonly [ownerHandle]: 'output-record'};

export type DurableOutputRecord = {
  readonly [ownerHandle]: 'durable-output-record'
};

export type OutputTransition = {readonly [ownerHandle]: 'output-transition'};

export type PayloadRequest = {readonly [ownerHandle]: 'payload-request'};

export type PayloadRecord = {readonly [ownerHandle]: 'payload-record'};

export type DurablePayloadRecord = {
  readonly [ownerHandle]: 'durable-payload-record'
};

export type PayloadTransition = {readonly [ownerHandle]: 'payload-transition'};

export interface DispatchInput {
  coordinatorAuthority: string;
  runDefinitionCid: string;
  taskKey: string;
  taskAttempt: number;
  dispatchId: string;
  siteKey: string;
  siteGeneration: number;
  runtimeBundleCid: string;
  connectorRegistration: string;
  connectorRevision: string;
  strategyRevision: string;
  inputBindingCid: string;
  obligationsCid: string;
  budgetCid: string;
  evidenceIssuerCapabilityCid: string;
  grantCid: string;
}

/** Host-owned CURRENT facts from existing authorization/Run owners, never
 * copied from a response. This is transport eligibility, not start authority. */
export interface RedeliveryContext {
  coordinatorAuthority: string;
  siteKey: string;
  siteGeneration: number;
  authorizationCurrent: boolean;
  cancellationRequested: boolean;
}

/** Resume a persisted initial intent before any outcome-unknown transition.
 * Requires current trusted context, exact saved delivery bytes and a successful
 * conditional unknown write before send. Recheck current context after that
 * await. This does not authorize an uncertain send or acquire a start claim. */
export interface InitialDeliveryContext extends RedeliveryContext {
  /** Trusted transport invariant: every offer/send follows persisted unknown.
   * False for transports that may have sent while the record stayed durable. */
  outcomePersistedBeforeEverySend: boolean;
}

/** Accepted physical Site evidence, never publication or read authority. */
export interface AcceptedSiteOutput {
  evidenceCid: string;
  measurementCid: string;
  dispatchRequestCid: string;
  materialGeneration: string;
  holdingEvidenceCid: string;
  managedProfileCid: string;
  resultSchemaCid: string;
  logicalViewCid: string;
  representationCodecCid: string;
  physicalManifestCid: string;
  measurementEvidenceCid: string;
  rowCount: string;
  retainedBytes: string;
  subjectCid: string;
}

export interface OutputIntentInput {
  storeAuthorityCid: string;
  publicationAttemptCid: string;
  resultDefinitionCid: string;
  orderingEvidenceCid: string;
  coordinatorAuthority: string;
  transferAttempt: string;
  transferRoute: 'direct' | 'store';
  destinationSiteKey: string;
  destinationSiteGeneration: number;
  transferMaxBytes: number | bigint;
  transferExpiresUnixMs: number | bigint;
  sourceGrantCid: string;
  destinationGrantCid: string;
  routeCapabilityCid: string;
  transferOrigin: string;
}

/** Canonical inventory DATA; no current permission or physical stop witness. */
export type HolderTerminalReport = {readonly [ownerHandle]: 'holder-terminal-report'};

const siteInteger = (value: unknown): value is bigint => typeof value === 'bigint' && value >= 0n &&
  value <= 9223372036854775807n;
const siteOptionalInteger = (value: unknown) => value == null || siteInteger(value);
const siteArray = (value: unknown, valid: (entry: unknown) => boolean) => {
  if (!Array.isArray(value) || value.length > 64) return false;
  // Array.every skips holes; every supplied slot must be a typed observation.
  for (let index = 0; index < value.length; index++) {
    if (!Object.hasOwn(value, index) || !valid(value[index])) return false;
  }
  return true;
};
const siteBoolean = (value: unknown) => typeof value === 'boolean';
const invalidSiteInput = () => { throw new TypeError('InvalidSitePlanningInput'); };

// Pure planning over trusted current observations. This is the existing common
// Site selector, not remote authentication, resource admission or a dispatch.
export const sitePlanning: Readonly<{
  plan(input: Readonly<{
    durationMilliseconds: bigint | null;
    startupMilliseconds: bigint | null;
    capacitySupported: boolean;
    acceptsTransfer: boolean;
    transferProviderAvailable: boolean;
    transferMilliseconds: bigint | null;
    transferRequired: readonly boolean[];
    sharedTransfer: readonly boolean[];
    sourceRevoked: readonly boolean[];
    estimateAvailable: readonly boolean[];
    transferBytes: readonly bigint[];
    retainedBytes: readonly bigint[];
    executionBytes: readonly bigint[];
  }>): Readonly<{code: number; durationMilliseconds: bigint | null}>;
  select(durations: readonly bigint[], keys: readonly string[]): number;
}> = Object.freeze({
  plan: input => {
    if (input === null || typeof input !== 'object' ||
        !(['durationMilliseconds', 'startupMilliseconds', 'transferMilliseconds'] as const)
          .every(key => siteOptionalInteger(input[key])) ||
        !(['capacitySupported', 'acceptsTransfer', 'transferProviderAvailable'] as const)
          .every(key => siteBoolean(input[key])) ||
        !(['transferRequired', 'sharedTransfer', 'sourceRevoked', 'estimateAvailable'] as const)
          .every(key => siteArray(input[key], siteBoolean)) ||
        !(['transferBytes', 'retainedBytes', 'executionBytes'] as const)
          .every(key => siteArray(input[key], siteInteger))) invalidSiteInput();
    const result = owner.coordinatorPlanSiteCandidate(
      input.durationMilliseconds ?? undefined, input.startupMilliseconds ?? undefined,
      input.capacitySupported, input.acceptsTransfer,
      input.transferProviderAvailable, input.transferMilliseconds ?? undefined,
      input.transferRequired, input.sharedTransfer, input.sourceRevoked,
      input.estimateAvailable, input.transferBytes, input.retainedBytes,
      input.executionBytes);
    // The pinned Site ABI returns an Int/Int64 tuple in these two fields.
    const code = runtimeField(result, 0) as typeof result[0], duration = runtimeField(result, 1) as typeof result[1];
    return Object.freeze({code, durationMilliseconds: code === 0 ? duration : null});
  },
  select: (durations, keys) => {
    if (!siteArray(durations, siteInteger) || !siteArray(keys, value =>
      typeof value === 'string' && value.length > 0 && value.length <= 256 &&
      !/[\u0000-\u001f\u007f]/u.test(value))) invalidSiteInput();
    return owner.coordinatorSelectSiteCandidate(durations, keys);
  },
});

function checked<Value>(result: owner.Result<Value>): Value {
  if (runtimeIsOk(result)) return runtimeField(result, 0) as Value;
  if (runtimeIsError(result)) {
    throw Object.assign(new Error('CoordinatorOwnerRejected', {cause: runtimeField(result, 0)}),
      {code: 'CoordinatorOwnerRejected'});
  }
  throw Object.assign(new Error('InvalidCoordinatorOwnerResult'),
    {code: 'InvalidCoordinatorOwnerResult'});
}

// Portable construction/admission only. Context is not retained readiness;
// persist the original returned binding JSON/CID before requesting retention.
export const bundleRetention: Readonly<{
  prepareDistribution(members: readonly string[]): BundleDistribution;
  distributionIdentity(value: BundleDistribution): string;
  distributionJson(value: BundleDistribution): string;
  /** Distribution CID followed by its sorted member bundle CIDs. */
  distributionProjection(value: BundleDistribution): string[];
  distributionContains(value: BundleDistribution, runtimeBundleCid: string): boolean;
  admitDistributionJson(body: string, claimedCid: string): BundleDistribution;
  prepareHoldScope(input: Readonly<BundleHoldScopeInput>): BundleHoldScope;
  holdScopeIdentity(value: BundleHoldScope): string;
  holdScopeJson(value: BundleHoldScope): string;
  /** Scope CID, coordinator, workspace, authority scope CID, environment, set
   * revision CID, distribution CID, bundle CID, Site key, generation, attempt. */
  holdScopeProjection(value: BundleHoldScope): string[];
  admitHoldScopeJson(distribution: BundleDistribution, body: string,
    claimedCid: string): BundleHoldScope;
  holdBindingIdentity(value: BundleHoldBinding): string;
  holdBindingJson(value: BundleHoldBinding): string;
  /** Binding CID, catalog, coordinator, workspace, authority scope CID,
   * environment, set revision CID, distribution CID, bundle CID, Site key,
   * generation, initial revision, attempt. */
  holdBindingProjection(value: BundleHoldBinding): string[];
  holdBindingScope(value: BundleHoldBinding): BundleHoldScope;
  admitHoldBindingJson(distribution: BundleDistribution, body: string,
    claimedCid: string): BundleHoldBinding;
  /** Discovers a binding. A context response is never retained readiness. */
  prepareCustodyContextQuery(distribution: BundleDistribution,
    scope: BundleHoldScope): BundleCustodyRequest;
  /** Persist the exact returned binding JSON/CID before retain. Recovery uses
   * that same binding; never refresh its catalog, revision, or attempt. */
  prepareCustodyRequest(distribution: BundleDistribution,
    binding: BundleHoldBinding, operation: BundleCustodyOperation): BundleCustodyRequest;
  custodyRequestIdentity(value: BundleCustodyRequest): string;
  custodyRequestJson(value: BundleCustodyRequest): string;
  custodyRequestOperation(value: BundleCustodyRequest): BundleCustodyOperation;
  custodyRequestScope(value: BundleCustodyRequest): BundleHoldScope;
  custodyRequestBinding(value: BundleCustodyRequest): BundleHoldBinding | undefined;
  admitCustodyRequestJson(body: string, claimedCid: string): BundleCustodyRequest;
  /** Binds the canonical response to this exact original request and verb. */
  admitCustodyResponseJson(request: BundleCustodyRequest, body: string,
    claimedCid: string): BundleCustodyResponse;
  custodyResponseIdentity(value: BundleCustodyResponse): string;
  custodyResponseJson(value: BundleCustodyResponse): string;
  custodyResponseKind(value: BundleCustodyResponse): 'context' | 'observation';
  custodyResponseBinding(value: BundleCustodyResponse): BundleHoldBinding;
  /** Empty for context. Only an observation can report retained custody. */
  custodyResponseObservation(value: BundleCustodyResponse): BundleCustodyObservation | '';
  custodyResponseCatalog(value: BundleCustodyResponse): string | undefined;
  custodyResponseRevision(value: BundleCustodyResponse): number | undefined;
}> = Object.freeze({
  prepareDistribution: members => checked(
    owner.coordinatorBundleDistributionPrepare(members)),
  distributionIdentity: owner.coordinatorBundleDistributionIdentity,
  distributionJson: value => checked(owner.coordinatorBundleDistributionJson(value)),
  distributionProjection: owner.coordinatorBundleDistributionProjection,
  distributionContains: owner.coordinatorBundleDistributionContains,
  admitDistributionJson: (body, cid) => checked(
    owner.coordinatorBundleDistributionAdmitJson(body, cid)),
  prepareHoldScope: value => checked(owner.coordinatorBundleHoldScopePrepare(
    value.distribution, value.coordinatorAuthority, value.workspaceId,
    value.authorityScopeCid, value.environment, value.setRevisionCid,
    value.runtimeBundleCid, value.siteKey, value.siteGeneration, value.attemptId)),
  holdScopeIdentity: owner.coordinatorBundleHoldScopeIdentity,
  holdScopeJson: value => checked(owner.coordinatorBundleHoldScopeJson(value)),
  holdScopeProjection: owner.coordinatorBundleHoldScopeProjection,
  admitHoldScopeJson: (distribution, body, cid) => checked(
    owner.coordinatorBundleHoldScopeAdmitJson(distribution, body, cid)),
  holdBindingIdentity: owner.coordinatorBundleHoldBindingIdentity,
  holdBindingJson: value => checked(owner.coordinatorBundleHoldBindingJson(value)),
  holdBindingProjection: owner.coordinatorBundleHoldBindingProjection,
  holdBindingScope: value => checked(owner.coordinatorBundleHoldBindingScope(value)),
  admitHoldBindingJson: (distribution, body, cid) => checked(
    owner.coordinatorBundleHoldBindingAdmitJson(distribution, body, cid)),
  prepareCustodyContextQuery: (distribution, scope) => checked(
    owner.coordinatorBundleCustodyContextQueryPrepare(distribution, scope)),
  prepareCustodyRequest: (distribution, binding, operation) => checked(
    owner.coordinatorBundleCustodyRequestPrepare(distribution, binding, operation)),
  custodyRequestIdentity: owner.coordinatorBundleCustodyRequestIdentity,
  custodyRequestJson: value => checked(owner.coordinatorBundleCustodyRequestJson(value)),
  custodyRequestOperation: owner.coordinatorBundleCustodyRequestOperation,
  custodyRequestScope: owner.coordinatorBundleCustodyRequestScope,
  custodyRequestBinding: value => owner.coordinatorBundleCustodyRequestBindings(value)[0],
  admitCustodyRequestJson: (body, cid) => checked(
    owner.coordinatorBundleCustodyRequestAdmitJson(body, cid)),
  admitCustodyResponseJson: (request, body, cid) => checked(
    owner.coordinatorBundleCustodyResponseAdmitJson(request, body, cid)),
  custodyResponseIdentity: owner.coordinatorBundleCustodyResponseIdentity,
  custodyResponseJson: value => checked(owner.coordinatorBundleCustodyResponseJson(value)),
  custodyResponseKind: owner.coordinatorBundleCustodyResponseKind,
  custodyResponseBinding: owner.coordinatorBundleCustodyResponseBinding,
  custodyResponseObservation: owner.coordinatorBundleCustodyResponseObservationText,
  custodyResponseCatalog: value =>
    owner.coordinatorBundleCustodyResponseCatalogText(value) || undefined,
  custodyResponseRevision: value => {
    const revision = owner.coordinatorBundleCustodyResponseRevisionText(value);
    return revision === '' ? undefined : Number(revision);
  },
});

export const createJournal: (authority: string) => Journal = authority =>
  checked(owner.coordinatorCreateJournal(authority));

// Only after the exact successful Output record was durably committed.
export const outputReportAckJson: (record: OutputRecord, originalReport: string) => string = (record, originalReport) =>
  checked(owner.coordinatorOutputReportAckJson(record, originalReport));

// The receiver must first establish this current, definitive refusal.
export const outputReportRefusalJson: (record: OutputRecord, originalReport: string, reason: 'authorization_denied' | 'scope_mismatch' | 'report_conflict') => string = (record, originalReport, reason) =>
  checked(owner.coordinatorOutputReportRefusalJson(record, originalReport, reason));

// These handles carry canonical metadata, not persistence or approval proof.
// Keep the admitted common value private so a caller cannot forge a report by
// copying fields or pass an unrelated owner handle to reply construction.
const effectCheckpointHandles = new WeakMap<EffectCheckpointReport, owner.EffectCheckpointValue>();
const effectCheckpointValue = (handle: EffectCheckpointReport) => {
  const value = effectCheckpointHandles.get(handle);
  if (value === undefined) throw new TypeError('InvalidEffectCheckpointReport');
  return value;
};
const effectResumeAuthenticationFields = ['key_id', 'reviewer_id',
  'expected_authority_scope_cid', 'authority_context_cid', 'policy_cid', 'proof_preimage'];
const snapshotTextRecord = (value: unknown, fields: readonly string[]) => {
  if (value === null || typeof value !== 'object' ||
      Object.keys(value).length !== fields.length ||
      !fields.every(key => Object.hasOwn(value, key))) return null;
  const snapshot = fields.map(key => (value as Record<string, unknown>)[key]);
  return snapshot.every(item => typeof item === 'string') ? snapshot : null;
};

// This only serializes an original, approved common Resolution. Authenticate
// and persist the claim through the existing Run Owner, then fence immediately
// before handout. A transported claim is never a current Site observation.
const prepareEffectResumeDeliveryJson = (
  serialize: typeof owner.coordinatorEffectResumeDeliveryJson,
  report: EffectCheckpointReport,
  resolutionWire: string,
  authentication: Parameters<typeof effectResumeDeliveries.prepareJson>[2],
  reviewers: Parameters<typeof effectResumeDeliveries.prepareJson>[3],
  claim: Parameters<typeof effectResumeDeliveries.prepareJson>[4],
  limits: Parameters<typeof effectResumeDeliveries.prepareJson>[5]
) => {
  const invalid: () => never = () => { throw new TypeError('InvalidEffectResumeDeliveryInput'); };
  if (typeof resolutionWire !== 'string' || !Array.isArray(reviewers)) invalid();
  const count = reviewers.length;
  if (count > 64 || claim === null || typeof claim !== 'object' || Object.keys(claim).length !== 2 ||
      !Object.hasOwn(claim, 'claimant') || !Object.hasOwn(claim, 'generation') ||
      limits === null || typeof limits !== 'object') invalid();
  // Snapshot caller values once; validation and the Owner see the same facts.
  const claimant = claim.claimant, generation = claim.generation;
  const bounds = [limits.maxWireBytes, limits.maxNodes, limits.maxDepth] as const;
  if (typeof claimant !== 'string' || claimant.length === 0 || claimant.length > 256 ||
      !siteInteger(generation) || generation === 0n ||
      !bounds.every((value, index) => Number.isSafeInteger(value) && value > 0 &&
        value <= [262144, 4096, 32][index])) invalid();
  const fields = snapshotTextRecord(authentication, effectResumeAuthenticationFields);
  if (fields === null) invalid();
  const keys = [], ids = [];
  for (let index = 0; index < count; index++) {
    if (!Object.hasOwn(reviewers, index)) invalid();
    const pair = snapshotTextRecord(reviewers[index], ['key_id', 'reviewer_id']);
    if (pair === null) invalid();
    keys.push(pair[0]);
    ids.push(pair[1]);
  }
  const utf8 = new TextEncoder();
  // UTF-16 length is a safe lower bound on UTF-8 bytes. Reject first so the
  // encoder cannot allocate an arbitrarily large buffer for a refused input.
  const byteLength = (value: string, maximum: number) => {
    if (value.length > maximum) invalid();
    const length = utf8.encode(value).length;
    if (length > maximum) invalid();
    return length;
  };
  byteLength(claimant, 256);
  let remaining = bounds[0];
  for (const value of [resolutionWire, ...fields, ...keys, ...ids]) {
    remaining -= byteLength(value, remaining);
  }
  return checked(serialize(effectCheckpointValue(report),
    resolutionWire, fields, keys, ids, claimant, generation, ...bounds));
};
export const effectResumeDeliveries: Readonly<{
  prepareJson(report: EffectCheckpointReport, resolutionWire: string,
    authentication: Readonly<{key_id: string; reviewer_id: string;
      expected_authority_scope_cid: string; authority_context_cid: string;
      policy_cid: string; proof_preimage: string}>,
    reviewers: readonly Readonly<{key_id: string; reviewer_id: string}>[],
    claim: Readonly<{claimant: string; generation: bigint}>,
    limits: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>): string;
  preparePollJson(report: EffectCheckpointReport, resolutionWire: string,
    authentication: Readonly<{key_id: string; reviewer_id: string;
      expected_authority_scope_cid: string; authority_context_cid: string;
      policy_cid: string; proof_preimage: string}>,
    reviewers: readonly Readonly<{key_id: string; reviewer_id: string}>[],
    claim: Readonly<{claimant: string; generation: bigint}>,
    limits: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>): string;
}> = Object.freeze({
  prepareJson: (...args) => prepareEffectResumeDeliveryJson(owner.coordinatorEffectResumeDeliveryJson, ...args),
  preparePollJson: (...args) => prepareEffectResumeDeliveryJson(owner.coordinatorEffectResumePollJson, ...args),
});
const effectCurrentQueries = new WeakMap<EffectCurrentQuery, owner.EffectCurrentQueryValue>(),
  effectCurrentReplies = new WeakMap<EffectCurrentReply, {value: owner.EffectCurrentReplyValue; query: EffectCurrentQuery}>();
const effectCurrentValue = <Handle extends object, Value>(values: WeakMap<Handle, Value>, handle: Handle) => {
  const value = values.get(handle);
  if (value === undefined) throw new TypeError('InvalidEffectCurrentHandle');
  return value;
};
const effectCurrentLimits = (supplied: Parameters<typeof effectCurrentObservations.prepareQuery>[3]) => {
  if (supplied === null || typeof supplied !== 'object') throw new TypeError('InvalidEffectCurrentLimits');
  const names = ['maxWireBytes', 'maxNodes', 'maxDepth'] as const, values = names.map(name => supplied[name]);
  if (!values.every((value, index) => Number.isSafeInteger(value) && value > 0 && value <= [65536, 4096, 32][index])) {
    throw new TypeError('InvalidEffectCurrentLimits');
  }
  return values as [number, number, number];
};
const effectCurrentText = (value: unknown) => {
  if (typeof value !== 'string' || value.length === 0 || value.length > 256 ||
      new TextEncoder().encode(value).length > 256) throw new TypeError('InvalidEffectCurrentInput');
  return value;
};
export const effectCurrentObservations: Readonly<{
  prepareQuery(report: EffectCheckpointReport, effectId: string, queryId: string,
    limits: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>): EffectCurrentQuery;
  queryJson(query: EffectCurrentQuery): string;
  /** Bounded routing only; the receiver must admit its own original report. */
  pollJson(query: EffectCurrentQuery): string;
  queryFacts(query: EffectCurrentQuery): Readonly<{queryCid: string; reportCid: string;
    dispatchCid: string; checkpointCid: string; effectId: string; queryId: string}>;
  admitReplyJson(query: EffectCurrentQuery, body: string,
    limits: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>): EffectCurrentReply;
  replyFacts(reply: EffectCurrentReply): Readonly<{queryCid: string; reportCid: string;
    dispatchCid: string; checkpointCid: string; effectId: string; queryId: string; replyCid: string;
    ledgerHeadCid?: string; recoveryAction: number; responseSaved: boolean;
    unknownEffects: readonly string[]}>;
}> = Object.freeze({
  prepareQuery: (report, effectId, queryId, limits) => {
    const bounds = effectCurrentLimits(limits);
    const value = checked(owner.coordinatorEffectCurrentQueryPrepare(effectCheckpointValue(report),
      effectCurrentText(effectId), effectCurrentText(queryId), ...bounds));
    const handle = Object.freeze({}) as EffectCurrentQuery; effectCurrentQueries.set(handle, value); return handle;
  },
  queryJson: query => owner.coordinatorEffectCurrentQueryProjection(effectCurrentValue(effectCurrentQueries, query))[0],
  pollJson: query => checked(owner.coordinatorEffectCurrentPollJson(effectCurrentValue(effectCurrentQueries, query))),
  queryFacts: query => {
    const [, queryCid, reportCid, dispatchCid, checkpointCid, effectId, queryId] =
      owner.coordinatorEffectCurrentQueryProjection(effectCurrentValue(effectCurrentQueries, query));
    return Object.freeze({queryCid, reportCid, dispatchCid, checkpointCid, effectId, queryId});
  },
  admitReplyJson: (query, body, limits) => {
    const bounds = effectCurrentLimits(limits);
    if (typeof body !== 'string' || body.length > bounds[0] || new TextEncoder().encode(body).length > bounds[0]) {
      throw new TypeError('InvalidEffectCurrentInput');
    }
    const value = checked(owner.coordinatorEffectCurrentReplyAdmit(effectCurrentValue(effectCurrentQueries, query), body, ...bounds));
    const handle = Object.freeze({}) as EffectCurrentReply; effectCurrentReplies.set(handle, {value, query}); return handle;
  },
  replyFacts: reply => {
    const {value, query} = effectCurrentValue(effectCurrentReplies, reply);
    const [, replyCid, head, action, saved] = owner.coordinatorEffectCurrentReplyProjection(value);
    const facts = effectCurrentObservations.queryFacts(query), recoveryAction = Number(action);
    return Object.freeze({...facts, replyCid, ledgerHeadCid: head === '' ? undefined : head,
      recoveryAction, responseSaved: saved === 'true',
      unknownEffects: Object.freeze(recoveryAction === 3 || recoveryAction === 4 ? [facts.effectId] : [])});
  },
});
export const effectCheckpointReports: Readonly<{
  admit(body: string, request: DispatchRequest, limits: Readonly<{
    maxWireBytes: number; maxNodes: number; maxDepth: number}>): EffectCheckpointReport;
  facts(report: EffectCheckpointReport): Readonly<{reportCid: string;
    dispatchCid: string; checkpointCid: string; checkpointWire: string}>;
  /** Serialize only after the receiving Run Owner durably commits exact waiting.
   * This does not commit waiting, approve the Effect or retire Site custody. */
  acceptedJson(report: EffectCheckpointReport): string;
  /** Only a current, definitive refusal permits this reply. */
  refusedJson(report: EffectCheckpointReport, reason: EffectCheckpointRefusal): string;
  admitReplyJson(report: EffectCheckpointReport, body: string): EffectCheckpointReply;
}> = Object.freeze({
  admit: (body, request, limits) => {
    if (typeof body !== 'string' || limits === null || typeof limits !== 'object' ||
        !([['maxWireBytes', 262144], ['maxNodes', 4096], ['maxDepth', 32]] as const)
          .every(([key, maximum]) => Number.isSafeInteger(limits[key]) &&
            limits[key] > 0 && limits[key] <= maximum)) {
      throw new TypeError('InvalidEffectCheckpointReportInput');
    }
    const value = checked(owner.coordinatorEffectCheckpointReportAdmit(body,
      request, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    const handle = Object.freeze({}) as EffectCheckpointReport;
    effectCheckpointHandles.set(handle, value);
    return handle;
  },
  facts: handle => {
    const [reportCid, dispatchCid, checkpointCid, checkpointWire] =
      owner.coordinatorEffectCheckpointReportProjection(effectCheckpointValue(handle));
    return Object.freeze({reportCid, dispatchCid, checkpointCid, checkpointWire});
  },
  // The receiving Host calls this only after its existing Run Owner confirms
  // the exact waiting commit. This serializer does not perform that commit.
  acceptedJson: handle => checked(owner.coordinatorEffectCheckpointAcceptedJson(
    effectCheckpointValue(handle))),
  refusedJson: (handle, reason) => checked(owner.coordinatorEffectCheckpointRefusedJson(
    effectCheckpointValue(handle), reason)),
  admitReplyJson: (handle, body) => {
    if (typeof body !== 'string') throw new TypeError('InvalidEffectCheckpointReplyInput');
    const [kind, reason] = checked(owner.coordinatorEffectCheckpointReplyAdmit(
      effectCheckpointValue(handle), body));
    return Object.freeze(kind === 'accepted' ? {kind} : {kind, reason});
  },
});

export const prepareDispatch: (input: DispatchInput) => DispatchRequest = input => checked(owner.coordinatorPrepareDispatch(
  input.coordinatorAuthority, input.runDefinitionCid, input.taskKey,
  input.taskAttempt, input.dispatchId, input.siteKey, input.siteGeneration,
  input.runtimeBundleCid, input.connectorRegistration,
  input.connectorRevision, input.strategyRevision, input.inputBindingCid,
  input.obligationsCid, input.budgetCid,
  input.evidenceIssuerCapabilityCid, input.grantCid,
));

export const dispatchCid: (request: DispatchRequest) => string = owner.coordinatorDispatchCid;
export const dispatchJson: (request: DispatchRequest) => string = request => checked(owner.coordinatorDispatchJson(request));
export const admitDispatchJson: (body: string, claimedCid: string) => DispatchRequest = (body, claimedCid) =>
  checked(owner.coordinatorAdmitDispatchJson(body, claimedCid));
export const dispatchRoute: (request: DispatchRequest) => string[] = owner.coordinatorDispatchRoute;
export const pollDispatchJson: (request: DispatchRequest, inputBindingBody: string, maxBindingBytes: number) => string = (request, inputBindingBody,
  maxBindingBytes) => checked(owner.coordinatorPollDispatchJson(
    request, inputBindingBody, maxBindingBytes));
export const pollDispatchMaterialsJson: (request: DispatchRequest, inputBindingBody: string, maxBindingBytes: number, runMaterials: string) => string = (request, inputBindingBody,
  maxBindingBytes, runMaterials) => checked(
  owner.coordinatorPollDispatchMaterialsJson(
    request, inputBindingBody, maxBindingBytes, runMaterials));
export const pollQueryJson: (request: DispatchRequest) => string = request =>
  checked(owner.coordinatorPollQueryJson(request));
export const pollCancelJson: (request: DispatchRequest) => string = request =>
  checked(owner.coordinatorPollCancelJson(request));
export const pollReleaseJson: (request: DispatchRequest) => string = request =>
  checked(owner.coordinatorPollReleaseJson(request));
export const admitPollNotSeen: (body: string, request: DispatchRequest) => true = (body, request) =>
  checked(owner.coordinatorAdmitPollNotSeen(body, request));
export const deliveryEnvelopeJson: (request: DispatchRequest, body: string) => string = (request, body) =>
  checked(owner.coordinatorDeliveryEnvelopeJson(request, body));
function validateDeliveryContext(context: Readonly<RedeliveryContext>) {
  if (context === null || typeof context !== 'object' ||
      typeof context.coordinatorAuthority !== 'string' ||
      typeof context.siteKey !== 'string' ||
      !Number.isSafeInteger(context.siteGeneration) ||
      context.siteGeneration < 0 || context.siteGeneration > 2147483647 ||
      typeof context.authorizationCurrent !== 'boolean' ||
      typeof context.cancellationRequested !== 'boolean') {
    throw new TypeError('InvalidCoordinatorRedeliveryContext');
  }
}
export const redeliveryEligible: (record: IntentRecord, request: DispatchRequest, notSeenBody: string, context: Readonly<RedeliveryContext>) => boolean = (record, request, notSeenBody, context) => {
  validateDeliveryContext(context);
  if (typeof notSeenBody !== 'string') {
    throw new TypeError('InvalidCoordinatorRedeliveryContext');
  }
  return checked(owner.coordinatorRedeliveryEligible(record, request,
    notSeenBody, context.coordinatorAuthority, context.siteKey,
    context.siteGeneration, context.authorizationCurrent,
    context.cancellationRequested));
};
export const initialDeliveryEligible: (record: IntentRecord, request: DispatchRequest, context: Readonly<InitialDeliveryContext>) => boolean = (record, request, context) => {
  validateDeliveryContext(context);
  if (typeof context.outcomePersistedBeforeEverySend !== 'boolean') {
    throw new TypeError('InvalidCoordinatorInitialDeliveryContext');
  }
  return checked(owner.coordinatorInitialDeliveryEligible(record, request,
    context.coordinatorAuthority, context.siteKey, context.siteGeneration,
    context.authorizationCurrent, context.cancellationRequested,
    context.outcomePersistedBeforeEverySend));
};
export const prepareIntent: (journal: Journal, request: DispatchRequest) => IntentAdmission = (journal, request) =>
  checked(owner.coordinatorPrepareIntent(journal, request));
export const intentIsNew: (admission: IntentAdmission) => boolean = owner.coordinatorIntentIsNew;
export const admissionDurableJson: (admission: IntentAdmission) => string = admission =>
  checked(owner.coordinatorAdmissionDurableJson(admission));
export const commitIntent: (admission: IntentAdmission) => IntentRecord = admission =>
  checked(owner.coordinatorCommitIntent(admission));
export const admitDurableJson: (body: string) => DurableRecord = body =>
  checked(owner.coordinatorAdmitDurableJson(body));
export const restoreDurable: (journal: Journal, durable: DurableRecord) => IntentRecord = (journal, durable) =>
  checked(owner.coordinatorRestoreDurable(journal, durable));
export const durableRevision: (durable: DurableRecord) => number = owner.coordinatorDurableRevision;
export const durableDispatchCid: (durable: DurableRecord) => string = owner.coordinatorDurableDispatchCid;
export const durableRequest: (durable: DurableRecord) => DispatchRequest = owner.coordinatorDurableRequest;
export const acceptedSiteOutput: (durable: DurableRecord) => Readonly<AcceptedSiteOutput> | undefined = durable => {
  const option = checked(owner.coordinatorAcceptedSiteOutput(durable));
  if (runtimeIsBoxedNone(option)) return undefined;
  if (!runtimeIsBoxedSome(option) || !Array.isArray(runtimeField(option, 0)) ||
      (runtimeField(option, 0) as readonly unknown[]).length !== 14 ||
      !(runtimeField(option, 0) as readonly unknown[]).every(value => typeof value === 'string')) {
    throw Object.assign(new Error('InvalidCoordinatorOutputProjection'),
      {code: 'InvalidCoordinatorOutputProjection'});
  }
  const [evidenceCid, measurementCid, dispatchRequestCid,
    materialGeneration, holdingEvidenceCid, managedProfileCid,
    resultSchemaCid, logicalViewCid, representationCodecCid,
    physicalManifestCid, measurementEvidenceCid, rowCount,
    retainedBytes, subjectCid] = runtimeField(option, 0) as readonly string[];
  return Object.freeze({evidenceCid, measurementCid, dispatchRequestCid,
    materialGeneration, holdingEvidenceCid, managedProfileCid,
    resultSchemaCid, logicalViewCid, representationCodecCid,
    physicalManifestCid, measurementEvidenceCid, rowCount,
    retainedBytes, subjectCid});
};
// An admitted transport candidate still requires the original Run's trusted
// Source, policy and authorization checks before Invocation/publication.
export const acceptedSourceObservation: (durable: DurableRecord) => Readonly<{taskOrdinal: number; sourceEvidenceWire: string;
    inputLogicalWire: string; captureStartedAt: string;
    captureCompletedAt: string}> | undefined = durable => {
  const option = owner.coordinatorAcceptedSourceObservation(durable);
  if (runtimeIsBoxedNone(option)) return undefined;
  if (!runtimeIsBoxedSome(option) || !Array.isArray(runtimeField(option, 0)) ||
      (runtimeField(option, 0) as readonly unknown[]).length !== 5 ||
      !(runtimeField(option, 0) as readonly unknown[]).every(value => typeof value === 'string')) {
    throw new Error('InvalidCoordinatorSourceObservationProjection');
  }
  const [ordinal, sourceEvidenceWire, inputLogicalWire,
    captureStartedAt, captureCompletedAt] = runtimeField(option, 0) as readonly string[];
  const taskOrdinal = Number(ordinal);
  if (!Number.isSafeInteger(taskOrdinal) || taskOrdinal < 0 ||
      String(taskOrdinal) !== ordinal) {
    throw new Error('InvalidCoordinatorSourceObservationProjection');
  }
  return Object.freeze({taskOrdinal, sourceEvidenceWire, inputLogicalWire,
    captureStartedAt, captureCompletedAt});
};
export const issueOutputPlanPollJson: (durable: DurableRecord, input: Readonly<OutputIntentInput>) => string = (durable, input) => {
  const integer = (value: number | bigint) => typeof value === 'bigint'
    ? value > 0n && value <= 9223372036854775807n
    : Number.isSafeInteger(value) && value > 0;
  if (input === null || typeof input !== 'object' ||
      !(['storeAuthorityCid', 'publicationAttemptCid',
        'resultDefinitionCid', 'orderingEvidenceCid',
        'coordinatorAuthority', 'transferAttempt', 'destinationSiteKey',
        'sourceGrantCid', 'destinationGrantCid', 'routeCapabilityCid',
        'transferOrigin'] as const).every(key => typeof input[key] === 'string') ||
      input.transferRoute !== 'direct' && input.transferRoute !== 'store' ||
      !Number.isSafeInteger(input.destinationSiteGeneration) ||
      input.destinationSiteGeneration < 0 ||
      input.destinationSiteGeneration > 2147483647 ||
      !integer(input.transferMaxBytes) ||
      !integer(input.transferExpiresUnixMs)) {
    throw new TypeError('InvalidCoordinatorOutputIntentInput');
  }
  return checked(owner.coordinatorIssueOutputPlanPollJson(
    durable, input.storeAuthorityCid, input.publicationAttemptCid,
    input.resultDefinitionCid, input.orderingEvidenceCid,
    input.coordinatorAuthority, input.transferAttempt, input.transferRoute,
    input.destinationSiteKey, input.destinationSiteGeneration,
    BigInt(input.transferMaxBytes), BigInt(input.transferExpiresUnixMs),
    input.sourceGrantCid, input.destinationGrantCid,
    input.routeCapabilityCid, input.transferOrigin));
};
export const admitCheckedOutputPlan: (durable: DurableRecord, pollBody: string, planBody: string, expectedResultDefinitionCid: string, limits: Readonly<{maxChunks: number; maxManifestBytes: number;
    maxReferencedBytes: number | bigint}>) => CheckedOutputPlan = (durable, pollBody, planBody,
  expectedResultDefinitionCid, {maxChunks, maxManifestBytes,
    maxReferencedBytes}) => {
  if (typeof pollBody !== 'string' || typeof planBody !== 'string' ||
      typeof expectedResultDefinitionCid !== 'string' ||
      !Number.isSafeInteger(maxChunks) || maxChunks < 1 ||
      !Number.isSafeInteger(maxManifestBytes) || maxManifestBytes < 1 ||
      !(typeof maxReferencedBytes === 'bigint' &&
        maxReferencedBytes > 0n && maxReferencedBytes <= 9223372036854775807n ||
        Number.isSafeInteger(maxReferencedBytes) && maxReferencedBytes > 0)) {
    throw new TypeError('InvalidCoordinatorOutputPlanInput');
  }
  return checked(owner.coordinatorAdmitCheckedOutputPlan(
    durable, pollBody, planBody, expectedResultDefinitionCid, maxChunks,
    maxManifestBytes, BigInt(maxReferencedBytes)));
};
export const checkedOutputPlanCid: (plan: CheckedOutputPlan) => string = owner.coordinatorCheckedOutputPlanCid;
export const checkedOutputIntentCid: (plan: CheckedOutputPlan) => string = owner.coordinatorCheckedOutputIntentCid;
export const checkedOutputPublicationFacts: (plan: CheckedOutputPlan) => Readonly<{
    resultDefinitionCid: string;
    logicalRelationCid: string;
    resultSchemaCid: string;
    orderingEvidenceCid: string;
    codecContractCid: string;
    rowCount: bigint;
    materialGenerationCid: string;
  }> = plan => {
  const facts = owner.coordinatorCheckedOutputPublicationFacts(plan);
  if (!Array.isArray(facts) || facts.length !== 7 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidCoordinatorOutputPublicationFacts');
  }
  const [resultDefinitionCid, logicalRelationCid, resultSchemaCid,
    orderingEvidenceCid, codecContractCid, rowCount, materialGenerationCid] =
    facts;
  return Object.freeze({resultDefinitionCid, logicalRelationCid,
    resultSchemaCid, orderingEvidenceCid, codecContractCid,
    rowCount: BigInt(rowCount), materialGenerationCid});
};
export const durableOutputPublicationFacts: (durable: DurableOutputRecord) => Readonly<{
    storeAuthorityCid: string;
    resultDefinitionCid: string;
    logicalRelationCid: string;
    resultSchemaCid: string;
    orderingEvidenceCid: string;
    codecContractCid: string;
    rowCount: bigint;
    materialGenerationCid: string;
  }> = durable => {
  const facts = owner.coordinatorDurableOutputPublicationFacts(durable);
  if (!Array.isArray(facts) || facts.length !== 8 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidCoordinatorDurableOutputPublicationFacts');
  }
  const [storeAuthorityCid, resultDefinitionCid, logicalRelationCid,
    resultSchemaCid, orderingEvidenceCid, codecContractCid, rowCount,
    materialGenerationCid] = facts;
  if (!/^(0|[1-9][0-9]*)$/u.test(rowCount)) {
    throw new Error('InvalidCoordinatorDurableOutputPublicationFacts');
  }
  return Object.freeze({storeAuthorityCid, resultDefinitionCid,
    logicalRelationCid, resultSchemaCid, orderingEvidenceCid,
    codecContractCid, rowCount: BigInt(rowCount), materialGenerationCid});
};
// In-process Store handles from the admitted Output Plan. Physical adapters
// must verify custody and persist each transition before committing it.
export const payloadRequestFromOutput: (durable: DurableOutputRecord) => PayloadRequest =
  owner.coordinatorPayloadRequestFromOutput;
// Historical typed DATA only. Current read authority and physical sealed
// generation remain with the existing Store/publication caller.
export const payloadRequestFromDurable: (durable: DurablePayloadRecord) => PayloadRequest = owner.coordinatorPayloadRequestFromDurable;
export function payloadRequestFacts(request: PayloadRequest): Readonly<{
  storeAuthorityCid: string; publicationAttemptCid: string;
  materialGenerationCid: string; resultDefinitionCid: string;
  logicalRelationCid: string; resultSchemaCid: string;
  orderingEvidenceCid: string; codecContractCid: string;
  maxBytes: bigint; rowCount: bigint;
}> {
  const values = owner.coordinatorPayloadRequestFacts(request);
  if (!Array.isArray(values) || values.length !== 10 ||
      values.some(value => typeof value !== 'string') ||
      values.slice(0, 8).some(value => !/^sha256:[0-9a-f]{64}$/u.test(value)) ||
      values.slice(8).some(value => !/^(0|[1-9][0-9]*)$/u.test(value))) {
    throw new Error('InvalidCoordinatorPayloadRequestFacts');
  }
  const [storeAuthorityCid, publicationAttemptCid, materialGenerationCid,
    resultDefinitionCid, logicalRelationCid, resultSchemaCid,
    orderingEvidenceCid, codecContractCid, maxBytes, rowCount] = values;
  return Object.freeze({storeAuthorityCid, publicationAttemptCid, materialGenerationCid,
    resultDefinitionCid, logicalRelationCid, resultSchemaCid, orderingEvidenceCid,
    codecContractCid, maxBytes: BigInt(maxBytes), rowCount: BigInt(rowCount)});
}
export const payloadRequestCid: (request: PayloadRequest) => string = owner.coordinatorPayloadRequestCid;
export const payloadRequestMaxBytes: (request: PayloadRequest) => bigint = owner.coordinatorPayloadRequestMaxBytes;
export const admitPayloadRequestJson: (body: string, claimedCid: string) => PayloadRequest = (body, claimedCid) =>
  checked(owner.coordinatorPayloadAdmitRequestJson(body, claimedCid));
export const preparePayloadRecord: (request: PayloadRequest) => PayloadRecord = owner.coordinatorPayloadPrepareRecord;
export const payloadRecordDurableJson: (record: PayloadRecord) => string = record =>
  checked(owner.coordinatorPayloadRecordDurableJson(record));
export const admitDurablePayloadJson: (body: string) => DurablePayloadRecord = body =>
  checked(owner.coordinatorPayloadAdmitDurableJson(body));
export const durablePayloadRevision: (durable: DurablePayloadRecord) => number = owner.coordinatorPayloadDurableRevision;
export const durablePayloadState: (durable: DurablePayloadRecord) => 'intent' | 'reserved' | 'writing' | 'sealed' | 'reclaiming' | 'reclaimed' = owner.coordinatorPayloadDurableState;
export const durablePayloadRequestCid: (durable: DurablePayloadRecord) => string =
  owner.coordinatorPayloadDurableRequestCid;
export const restoreDurablePayload: (durable: DurablePayloadRecord) => PayloadRecord = durable =>
  checked(owner.coordinatorPayloadRestoreDurable(durable));
export const preparePayloadReserved: (record: PayloadRecord) => PayloadTransition = record =>
  checked(owner.coordinatorPayloadPrepareReserved(record));
export const preparePayloadWriting: (record: PayloadRecord) => PayloadTransition = record =>
  checked(owner.coordinatorPayloadPrepareWriting(record));
export const preparePayloadOpaqueOwned: (record: PayloadRecord, custodyCid: string) => PayloadTransition = (record, custodyCid) =>
  checked(owner.coordinatorPayloadPrepareOpaqueOwned(record, custodyCid));
export const preparePayloadOpaqueSealed: (record: PayloadRecord, custodyCid: string, actualBytes: number | bigint, physicalDigest: string) => PayloadTransition = (record, custodyCid,
  actualBytes, physicalDigest) => {
  if (!(typeof actualBytes === 'bigint' && actualBytes >= 0n &&
      actualBytes <= 9223372036854775807n ||
      Number.isSafeInteger(actualBytes) && actualBytes >= 0)) {
    throw new TypeError('InvalidPayloadActualBytes');
  }
  return checked(owner.coordinatorPayloadPrepareOpaqueSealed(
    record, custodyCid, BigInt(actualBytes), physicalDigest));
};
export const preparePayloadOpaqueReclaiming: (record: PayloadRecord, custodyCid: string) => PayloadTransition = (record, custodyCid) =>
  checked(owner.coordinatorPayloadPrepareOpaqueReclaiming(record, custodyCid));
export const preparePayloadReclaimed: (record: PayloadRecord) => PayloadTransition = record =>
  checked(owner.coordinatorPayloadPrepareReclaimed(record));
export const payloadTransitionDurableJson: (transition: PayloadTransition) => string = transition =>
  checked(owner.coordinatorPayloadTransitionDurableJson(transition));
export const payloadTransitionExpectedRevision: (transition: PayloadTransition) => number =
  owner.coordinatorPayloadTransitionExpectedRevision;
/** Call only after the exact next payload body was durably persisted. */
export const commitPayloadTransition: (transition: PayloadTransition) => PayloadRecord = transition =>
  checked(owner.coordinatorPayloadCommitTransition(transition));
export const payloadRecordOpaqueGeneration: (record: PayloadRecord) => string | undefined = record => {
  const value = owner.coordinatorPayloadRecordOpaqueGeneration(record);
  if (value === undefined || typeof value === 'string') return value;
  throw new Error('InvalidPayloadGenerationProjection');
};
export const payloadRecordOpaqueOwnership: (record: PayloadRecord) => string | undefined = record => {
  const value = owner.coordinatorPayloadRecordOpaqueOwnership(record);
  if (value === undefined || typeof value === 'string') return value;
  throw new Error('InvalidPayloadOwnershipProjection');
};
export const payloadRecordDigest: (record: PayloadRecord) => string = owner.coordinatorPayloadRecordDigest;
export const payloadRecordActualBytes: (record: PayloadRecord) => bigint =
  owner.coordinatorPayloadRecordActualBytes;
export const prepareOutputIntent: (journal: Journal, plan: CheckedOutputPlan) => OutputIntentAdmission = (journal, plan) =>
  checked(owner.coordinatorPrepareOutputIntent(journal, plan));
export const outputIntentIsNew: (admission: OutputIntentAdmission) => boolean = owner.coordinatorOutputIntentIsNew;
/** Call only after the matching output intent and plan were persisted. */
export const commitOutputIntent: (admission: OutputIntentAdmission) => OutputRecord = admission =>
  checked(owner.coordinatorCommitOutputIntent(admission));
export const outputRecordStatus: (record: OutputRecord) => string[] = owner.coordinatorOutputRecordStatus;
export const outputInitialPollJson: (record: OutputRecord) => string = record =>
  checked(owner.coordinatorOutputInitialPollJson(record));
export const outputAdmissionDurableJson: (plan: CheckedOutputPlan) => string = plan =>
  checked(owner.coordinatorOutputAdmissionDurableJson(plan));
export const admitDurableOutputJson: (body: string, dispatch: DurableRecord, expectedResultDefinitionCid: string, limits: Readonly<{maxChunks: number; maxManifestBytes: number;
    maxReferencedBytes: number | bigint}>) => DurableOutputRecord = (body, dispatch,
  expectedResultDefinitionCid, {maxChunks, maxManifestBytes,
    maxReferencedBytes}) => {
  if (typeof body !== 'string' ||
      typeof expectedResultDefinitionCid !== 'string' ||
      !Number.isSafeInteger(maxChunks) || maxChunks < 1 ||
      !Number.isSafeInteger(maxManifestBytes) || maxManifestBytes < 1 ||
      !(typeof maxReferencedBytes === 'bigint' &&
        maxReferencedBytes > 0n && maxReferencedBytes <= 9223372036854775807n ||
        Number.isSafeInteger(maxReferencedBytes) && maxReferencedBytes > 0)) {
    throw new TypeError('InvalidCoordinatorDurableOutputInput');
  }
  return checked(owner.coordinatorAdmitDurableOutputJson(
    body, dispatch, expectedResultDefinitionCid, maxChunks,
    maxManifestBytes, BigInt(maxReferencedBytes)));
};
export const restoreDurableOutput: (journal: Journal, durable: DurableOutputRecord) => OutputRecord = (journal, durable) =>
  checked(owner.coordinatorRestoreDurableOutput(journal, durable));
export const durableOutputRevision: (durable: DurableOutputRecord) => number = owner.coordinatorDurableOutputRevision;
export const durableOutputJson: (durable: DurableOutputRecord) => string = owner.coordinatorDurableOutputJson;
export const durableOutputPollJson: (durable: DurableOutputRecord) => string = durable =>
  checked(owner.coordinatorDurableOutputPollJson(durable));
export const durableOutputRequestJson: (durable: DurableOutputRecord) => string = durable =>
  checked(owner.coordinatorDurableOutputRequestJson(durable));
export const admitOutputTransferReplyJson: (durable: DurableOutputRecord, reply: string) => string = (durable, reply) =>
  checked(owner.coordinatorAdmitOutputTransferReplyJson(durable, reply));
export const outputTransferRequestCid: (durable: DurableOutputRecord) => string = durable =>
  owner.coordinatorOutputTransferRequestCid(durable);
export const prepareOutputResultJson: (durable: DurableOutputRecord, reply: string, payloadPhysicalDigest: string) => string = (durable, reply,
  payloadPhysicalDigest) => checked(owner.coordinatorPrepareOutputResultJson(
    durable, reply, payloadPhysicalDigest));
export const prepareOutputUnknown: (record: OutputRecord) => OutputTransition = record =>
  checked(owner.coordinatorPrepareOutputUnknown(record));
export const prepareOutputSuccessJson: (record: OutputRecord, body: string) => OutputTransition = (record, body) =>
  checked(owner.coordinatorPrepareOutputSuccessJson(record, body));
export const outputTransitionExpectedRevision: (transition: OutputTransition) => number =
  owner.coordinatorOutputTransitionExpectedRevision;
export const outputTransitionDurableJson: (durable: DurableOutputRecord, transition: OutputTransition) => string = (durable, transition) =>
  checked(owner.coordinatorOutputTransitionDurableJson(durable, transition));
/** Call only after the exact next output body was atomically persisted. */
export const commitOutputTransition: (transition: OutputTransition) => OutputRecord = transition =>
  checked(owner.coordinatorCommitOutputTransition(transition));
export const outputResultJson: (record: OutputRecord) => string = record =>
  checked(owner.coordinatorOutputResultJson(record));
export const prepareUnknown: (record: IntentRecord) => Transition = record =>
  checked(owner.coordinatorPrepareUnknown(record));
export const admitResponseJson: (body: string, request: DispatchRequest, statusReply: boolean) => DispatchResponse = (body, request, statusReply) =>
  checked(owner.coordinatorAdmitResponseJson(body, request, statusReply));
export const prepareResponseObservation: (record: IntentRecord, response: DispatchResponse) => Transition = (record, response) =>
  checked(owner.coordinatorPrepareResponseObservation(record, response));
export const transitionExpectedRevision: (transition: Transition) => number =
  owner.coordinatorTransitionExpectedRevision;
export const transitionIsReplay: (transition: Transition) => boolean = owner.coordinatorTransitionIsReplay;
export const transitionDurableJson: (durable: DurableRecord, transition: Transition) => string = (durable, transition) =>
  checked(owner.coordinatorTransitionDurableJson(durable, transition));
export const responseDurableJson: (durable: DurableRecord, transition: Transition, response: DispatchResponse) => string = (durable, transition, response) =>
  checked(owner.coordinatorResponseDurableJson(durable, transition, response));
export const commitTransition: (transition: Transition) => void = transition =>
  checked(owner.coordinatorCommitTransition(transition));
export const recordStateCodes: (record: IntentRecord) => string[] = owner.coordinatorRecordStateCodes;
export const exactRetransmissionEligible: (record: IntentRecord, request: DispatchRequest) => boolean =
  owner.coordinatorExactRetransmissionEligible;

export const canRetireCancellationDelivery: (record: IntentRecord) => boolean =
  owner.coordinatorCanRetireCancellationDelivery;

// One namespace for the existing Common report value. Copied handles and raw
// projections cannot stand in for the admitted original.
const holderTerminalHandles = new WeakMap<HolderTerminalReport, owner.HolderTerminalValue>();
const holderTerminalValue = (handle: HolderTerminalReport) => {
  const value = holderTerminalHandles.get(handle);
  if (value === undefined) throw new TypeError('InvalidHolderTerminalReport');
  return value;
};
export const holderTerminalReports: Readonly<{
  admit(body: string, maximum: number): HolderTerminalReport;
  facts(report: HolderTerminalReport): Readonly<{reportCid: string; rootDispatchCid: string}>;
  requests(report: HolderTerminalReport): readonly DispatchRequest[];
  /** Call only after durable exact original association. Partial Run inventory
   * receipt does not acknowledge whole-Run stop, Result or resource release. */
  acceptedJson(report: HolderTerminalReport): string;
  admitReplyJson(report: HolderTerminalReport, body: string): void;
}> = Object.freeze({
  admit: (body, maximum) => {
    if (typeof body !== 'string' || !Number.isSafeInteger(maximum) ||
        maximum < 1 || maximum > 262144) throw new TypeError('InvalidHolderTerminalReportInput');
    const value = checked(owner.coordinatorHolderTerminalReportAdmit(body, maximum));
    const handle = Object.freeze({}) as HolderTerminalReport;
    holderTerminalHandles.set(handle, value);
    return handle;
  },
  facts: handle => {
    const [reportCid, rootDispatchCid] = owner.coordinatorHolderTerminalReportProjection(holderTerminalValue(handle));
    return Object.freeze({reportCid, rootDispatchCid});
  },
  requests: handle => Object.freeze([...owner.coordinatorHolderTerminalReportDispatches(holderTerminalValue(handle))]),
  acceptedJson: handle => checked(owner.coordinatorHolderTerminalAcceptedJson(holderTerminalValue(handle))),
  admitReplyJson: (handle, body) => {
    if (typeof body !== 'string') throw new TypeError('InvalidHolderTerminalReplyInput');
    checked(owner.coordinatorHolderTerminalReplyAdmit(holderTerminalValue(handle), body));
  },
});
