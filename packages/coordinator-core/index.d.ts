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

/** Portable shared-owner client values. No installation, activation, physical
 * Store mutation, authority setup, transport, or automatic retry is exposed. */
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
}>;

export type Journal = {readonly [ownerHandle]: 'journal'};
export type DispatchRequest = {readonly [ownerHandle]: 'dispatch-request'};
export type EffectCheckpointReport = {readonly [ownerHandle]: 'effect-checkpoint-report'};
export type EffectCurrentQuery = {readonly [ownerHandle]: 'effect-current-query'};
export type EffectCurrentReply = {readonly [ownerHandle]: 'effect-current-reply'};
/** Correlation only. Authenticate the current Site and its exact outstanding
 * challenge using trusted Owners; historical replies grant no current permit. */
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
}>;
export type EffectCheckpointRefusal = 'authorization_denied' | 'scope_mismatch' | 'report_conflict';
export type EffectCheckpointReply = Readonly<{kind: 'accepted'} |
  {kind: 'refused'; reason: EffectCheckpointRefusal}>;

/** Serialization only: physical Reviewer/Host authentication, durable claim
 * and current fencing remain responsibilities of the existing trusted Owners. */
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
}>;

/** Canonical report admission is not remote persistence, approval, execution or
 * cleanup evidence. Authenticate the current Site and validate the original
 * Run/unit, consumer and retained custody using the existing trusted Owners. */
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
}>;
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

export function createJournal(authority: string): Journal;
export function prepareDispatch(input: DispatchInput): DispatchRequest;
export function dispatchCid(request: DispatchRequest): string;
export function dispatchJson(request: DispatchRequest): string;
export function admitDispatchJson(body: string,
  claimedCid: string): DispatchRequest;
export function dispatchRoute(request: DispatchRequest): string[];
export function pollDispatchJson(request: DispatchRequest,
  inputBindingBody: string, maxBindingBytes: number): string;
/** Dispatch envelope that also carries typed run materials; grants nothing. */
export function pollDispatchMaterialsJson(request: DispatchRequest,
  inputBindingBody: string, maxBindingBytes: number,
  runMaterials: string): string;
export function pollQueryJson(request: DispatchRequest): string;
/** Release request for the exact retained dispatch output; never executes. */
export function pollReleaseJson(request: DispatchRequest): string;
/** Exact cancellation request; persistence is not physical-stop evidence. */
export function pollCancelJson(request: DispatchRequest): string;
/** Admits a Site's not-seen answer for exactly this request; throws otherwise. */
export function admitPollNotSeen(body: string, request: DispatchRequest): true;
/** Admit exact canonical poll delivery bytes. Site/Run owners separately
 * validate materials meaning and authority. Persist before initial send. */
export function deliveryEnvelopeJson(request: DispatchRequest, body: string): string;
/** Host-owned CURRENT facts from existing authorization/Run owners, never
 * copied from a response. This is transport eligibility, not start authority. */
export interface RedeliveryContext {
  coordinatorAuthority: string;
  siteKey: string;
  siteGeneration: number;
  authorizationCurrent: boolean;
  cancellationRequested: boolean;
}
/** Empty notSeenBody requires an accepted durable Site observation. A typed
 * not-seen reply may recover only an intent with no accepted Site history. */
export function redeliveryEligible(record: IntentRecord, request: DispatchRequest,
  notSeenBody: string, context: Readonly<RedeliveryContext>): boolean;
/** Resume a persisted initial intent before any outcome-unknown transition.
 * Requires current trusted context, exact saved delivery bytes and a successful
 * conditional unknown write before send. Recheck current context after that
 * await. This does not authorize an uncertain send or acquire a start claim. */
export interface InitialDeliveryContext extends RedeliveryContext {
  /** Trusted transport invariant: every offer/send follows persisted unknown.
   * False for transports that may have sent while the record stayed durable. */
  outcomePersistedBeforeEverySend: boolean;
}
export function initialDeliveryEligible(record: IntentRecord, request: DispatchRequest,
  context: Readonly<InitialDeliveryContext>): boolean;
export function prepareIntent(journal: Journal,
  request: DispatchRequest): IntentAdmission;
export function intentIsNew(admission: IntentAdmission): boolean;
export function admissionDurableJson(admission: IntentAdmission): string;
/** Call only after the exact admission body was durably persisted. */
export function commitIntent(admission: IntentAdmission): IntentRecord;
export function admitDurableJson(body: string): DurableRecord;
export function restoreDurable(journal: Journal,
  durable: DurableRecord): IntentRecord;
export function durableRevision(durable: DurableRecord): number;
export function durableDispatchCid(durable: DurableRecord): string;
export function durableRequest(durable: DurableRecord): DispatchRequest;
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
export function acceptedSiteOutput(durable: DurableRecord):
  Readonly<AcceptedSiteOutput> | undefined;
/** Completed transport candidate; grants no Source or publication authority. */
export function acceptedSourceObservation(durable: DurableRecord):
  Readonly<{taskOrdinal: number; sourceEvidenceWire: string;
    inputLogicalWire: string; captureStartedAt: string;
    captureCompletedAt: string}> | undefined;
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
/** Caller must independently authorize every publication and movement field. */
export function issueOutputPlanPollJson(durable: DurableRecord,
  input: Readonly<OutputIntentInput>): string;
export function admitCheckedOutputPlan(durable: DurableRecord,
  pollBody: string, planBody: string, expectedResultDefinitionCid: string,
  limits: Readonly<{maxChunks: number; maxManifestBytes: number;
    maxReferencedBytes: number | bigint}>): CheckedOutputPlan;
export function checkedOutputPlanCid(plan: CheckedOutputPlan): string;
export function checkedOutputIntentCid(plan: CheckedOutputPlan): string;
/** Admitted Site claims, not verified publication or a read grant. */
export function checkedOutputPublicationFacts(plan: CheckedOutputPlan):
  Readonly<{
    resultDefinitionCid: string;
    logicalRelationCid: string;
    resultSchemaCid: string;
    orderingEvidenceCid: string;
    codecContractCid: string;
    rowCount: bigint;
    materialGenerationCid: string;
  }>;
/** Retained Site claims; Store custody and publication need separate checks. */
export function durableOutputPublicationFacts(durable: DurableOutputRecord):
  Readonly<{
    storeAuthorityCid: string;
    resultDefinitionCid: string;
    logicalRelationCid: string;
    resultSchemaCid: string;
    orderingEvidenceCid: string;
    codecContractCid: string;
    rowCount: bigint;
    materialGenerationCid: string;
  }>;
/** In-process identity from an admitted Site plan, never a custody grant. */
export function payloadRequestFromOutput(durable: DurableOutputRecord):
  PayloadRequest;
export function payloadRequestCid(request: PayloadRequest): string;
export function payloadRequestMaxBytes(request: PayloadRequest): bigint;
export function admitPayloadRequestJson(body: string,
  claimedCid: string): PayloadRequest;
export function preparePayloadRecord(request: PayloadRequest): PayloadRecord;
export function payloadRecordDurableJson(record: PayloadRecord): string;
export function admitDurablePayloadJson(body: string): DurablePayloadRecord;
export function durablePayloadRevision(durable: DurablePayloadRecord): number;
export function durablePayloadState(durable: DurablePayloadRecord):
  'intent' | 'reserved' | 'writing' | 'sealed' | 'reclaiming' | 'reclaimed';
export function durablePayloadRequestCid(durable: DurablePayloadRecord): string;
export function restoreDurablePayload(durable: DurablePayloadRecord):
  PayloadRecord;
export function preparePayloadReserved(record: PayloadRecord):
  PayloadTransition;
export function preparePayloadWriting(record: PayloadRecord):
  PayloadTransition;
export function preparePayloadOpaqueOwned(record: PayloadRecord,
  custodyCid: string): PayloadTransition;
export function preparePayloadOpaqueSealed(record: PayloadRecord,
  custodyCid: string, actualBytes: number | bigint,
  physicalDigest: string): PayloadTransition;
export function preparePayloadOpaqueReclaiming(record: PayloadRecord,
  custodyCid: string): PayloadTransition;
export function preparePayloadReclaimed(record: PayloadRecord):
  PayloadTransition;
export function payloadTransitionDurableJson(
  transition: PayloadTransition): string;
export function payloadTransitionExpectedRevision(
  transition: PayloadTransition): number;
/** Call only after the exact transition body was durably persisted. */
export function commitPayloadTransition(transition: PayloadTransition):
  PayloadRecord;
export function payloadRecordOpaqueGeneration(record: PayloadRecord):
  string | undefined;
export function payloadRecordOpaqueOwnership(record: PayloadRecord):
  string | undefined;
export function payloadRecordDigest(record: PayloadRecord): string;
export function payloadRecordActualBytes(record: PayloadRecord): bigint;
export function prepareOutputIntent(journal: Journal,
  plan: CheckedOutputPlan): OutputIntentAdmission;
export function outputIntentIsNew(admission: OutputIntentAdmission): boolean;
/** Call only after the matching output intent and plan were persisted. */
export function commitOutputIntent(admission: OutputIntentAdmission): OutputRecord;
export function outputRecordStatus(record: OutputRecord): string[];
/** Available only before the first durably recorded physical send. */
export function outputInitialPollJson(record: OutputRecord): string;
export function outputAdmissionDurableJson(plan: CheckedOutputPlan): string;
export function admitDurableOutputJson(body: string, dispatch: DurableRecord,
  expectedResultDefinitionCid: string,
  limits: Readonly<{maxChunks: number; maxManifestBytes: number;
    maxReferencedBytes: number | bigint}>): DurableOutputRecord;
export function restoreDurableOutput(journal: Journal,
  durable: DurableOutputRecord): OutputRecord;
export function durableOutputRevision(durable: DurableOutputRecord): number;
export function durableOutputJson(durable: DurableOutputRecord): string;
export function durableOutputPollJson(durable: DurableOutputRecord): string;
/** The poll Output request (`actql-remote-poll-output/0.1`) for the retained
 * Output Plan; an outbound Site admits it with `admitPollOutput`. */
export function durableOutputRequestJson(durable: DurableOutputRecord): string;
/** Binds a destination-committed reply to the retained Transfer request. */
export function admitOutputTransferReplyJson(durable: DurableOutputRecord,
  reply: string): string;
/** Identity for recovery only; current authority and bytes must be checked. */
export function outputTransferRequestCid(durable: DurableOutputRecord): string;
/** The caller must independently verify local payload custody and digest. */
export function prepareOutputResultJson(durable: DurableOutputRecord,
  reply: string, payloadPhysicalDigest: string): string;
export function prepareOutputUnknown(record: OutputRecord): OutputTransition;
export function prepareOutputSuccessJson(record: OutputRecord,
  body: string): OutputTransition;
export function outputTransitionExpectedRevision(
  transition: OutputTransition): number;
export function outputTransitionDurableJson(durable: DurableOutputRecord,
  transition: OutputTransition): string;
/** Call only after the exact next output body was atomically persisted. */
export function commitOutputTransition(
  transition: OutputTransition): OutputRecord;
export function outputResultJson(record: OutputRecord): string;
/** Call after durable acceptance. Exact replay is ACK-only; foreign or
 * unaccepted report bytes are rejected. Never use an in-memory waiter. */
export function outputReportAckJson(record: OutputRecord, originalReport: string): string;
/** After a checked current refusal. Unknown HTTP/errors are not refusals.
 * Admits the original report against the expected Output owner; no transition. */
export function outputReportRefusalJson(record: OutputRecord, originalReport: string,
  reason: 'authorization_denied' | 'scope_mismatch' | 'report_conflict'): string;
export function prepareUnknown(record: IntentRecord): Transition;
export function admitResponseJson(body: string, request: DispatchRequest,
  statusReply: boolean): DispatchResponse;
export function prepareResponseObservation(record: IntentRecord,
  response: DispatchResponse): Transition;
export function transitionExpectedRevision(transition: Transition): number;
/** Exact admitted replay: responseDurableJson returns the unchanged body.
 * Reconcile/persist that body before ACK; do not increment its revision. */
export function transitionIsReplay(transition: Transition): boolean;
export function transitionDurableJson(durable: DurableRecord,
  transition: Transition): string;
export function responseDurableJson(durable: DurableRecord,
  transition: Transition, response: DispatchResponse): string;
/** Call only after the exact next durable body was atomically persisted. */
export function commitTransition(transition: Transition): void;
export function recordStateCodes(record: IntentRecord): string[];
/** Structural transport candidate only (including historical Accepted).
 * Use redeliveryEligible with current trusted Host facts and an admitted query
 * before sending; this function grants no executor/start-claim permission. */
export function exactRetransmissionEligible(record: IntentRecord,
  request: DispatchRequest): boolean;

/** Cancel delivery custody only, after durable observation admission. Success
 * may win a cancellation race; this does not confirm Run cancellation. */
export function canRetireCancellationDelivery(record: IntentRecord): boolean;
/** Pure common Site planning; caller-owned facts are not execution authority. */
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
}>;

/** Canonical inventory DATA; no current permission or physical stop witness. */
export type HolderTerminalReport = {readonly [ownerHandle]: 'holder-terminal-report'};
export const holderTerminalReports: Readonly<{
  admit(body: string, maximum: number): HolderTerminalReport;
  facts(report: HolderTerminalReport): Readonly<{reportCid: string; rootDispatchCid: string}>;
  requests(report: HolderTerminalReport): readonly DispatchRequest[];
  /** Call only after durable exact original association. Partial Run inventory
   * receipt does not acknowledge whole-Run stop, Result or resource release. */
  acceptedJson(report: HolderTerminalReport): string;
  admitReplyJson(report: HolderTerminalReport, body: string): void;
}>;
