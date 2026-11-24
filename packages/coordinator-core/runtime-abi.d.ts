// Types available before the package build installs the pinned MoonBit runtime.
// Public handles share the facade types. Privately held values never cross that facade.
declare module '*/dist/remote_coordinator_abi.js' {
  type BundleCustodyRequest = import('./index.mjs').BundleCustodyRequest;
  type BundleCustodyResponse = import('./index.mjs').BundleCustodyResponse;
  type BundleDistribution = import('./index.mjs').BundleDistribution;
  type BundleHoldBinding = import('./index.mjs').BundleHoldBinding;
  type BundleHoldScope = import('./index.mjs').BundleHoldScope;
  type CheckedOutputPlan = import('./index.mjs').CheckedOutputPlan;
  type DispatchRequest = import('./index.mjs').DispatchRequest;
  type DispatchResponse = import('./index.mjs').DispatchResponse;
  type DurableOutputRecord = import('./index.mjs').DurableOutputRecord;
  type DurablePayloadRecord = import('./index.mjs').DurablePayloadRecord;
  type DurableRecord = import('./index.mjs').DurableRecord;
  type IntentAdmission = import('./index.mjs').IntentAdmission;
  type IntentRecord = import('./index.mjs').IntentRecord;
  type Journal = import('./index.mjs').Journal;
  type OutputIntentAdmission = import('./index.mjs').OutputIntentAdmission;
  type OutputRecord = import('./index.mjs').OutputRecord;
  type OutputTransition = import('./index.mjs').OutputTransition;
  type PayloadRecord = import('./index.mjs').PayloadRecord;
  type PayloadRequest = import('./index.mjs').PayloadRequest;
  type PayloadTransition = import('./index.mjs').PayloadTransition;
  type Transition = import('./index.mjs').Transition;

  const custody: unique symbol;
  export type EffectCheckpointValue = {readonly [custody]: 'EffectCheckpointValue'};
  export type EffectCurrentQueryValue = {readonly [custody]: 'EffectCurrentQueryValue'};
  export type EffectCurrentReplyValue = {readonly [custody]: 'EffectCurrentReplyValue'};
  export type HolderTerminalValue = {readonly [custody]: 'HolderTerminalValue'};
  export type Result<Value> = {readonly $tag: 1; readonly _0: Value} |
    {readonly $tag: 0; readonly _0: unknown};
  type BoxedOption<Value> = {readonly $tag: 1; readonly _0: Value} | {readonly $tag: 0};

  export function coordinatorAcceptedSiteOutput(durable: DurableRecord): Result<BoxedOption<string[]>>;
  export function coordinatorAcceptedSourceObservation(durable: DurableRecord): BoxedOption<string[]>;
  export function coordinatorAdmissionDurableJson(admission: IntentAdmission): Result<string>;
  export function coordinatorAdmitCheckedOutputPlan(
    durable: DurableRecord,
    pollBody: string,
    planBody: string,
    expectedResultDefinitionCid: string,
    maxChunks: number,
    maxManifestBytes: number,
    maxReferencedBytes: bigint
  ): Result<CheckedOutputPlan>;
  export function coordinatorAdmitDispatchJson(body: string, claimedCid: string): Result<DispatchRequest>;
  export function coordinatorAdmitDurableJson(body: string): Result<DurableRecord>;
  export function coordinatorAdmitDurableOutputJson(
    body: string,
    dispatch: DurableRecord,
    expectedResultDefinitionCid: string,
    maxChunks: number,
    maxManifestBytes: number,
    maxReferencedBytes: bigint
  ): Result<DurableOutputRecord>;
  export function coordinatorAdmitOutputTransferReplyJson(
    durable: DurableOutputRecord,
    reply: string
  ): Result<string>;
  export function coordinatorAdmitPollNotSeen(body: string, request: DispatchRequest): Result<true>;
  export function coordinatorAdmitResponseJson(
    body: string,
    request: DispatchRequest,
    statusReply: boolean
  ): Result<DispatchResponse>;
  export function coordinatorBundleCustodyContextQueryPrepare(
    distribution: BundleDistribution,
    scope: BundleHoldScope
  ): Result<BundleCustodyRequest>;
  export function coordinatorBundleCustodyRequestAdmitJson(
    body: string,
    claimedCid: string
  ): Result<BundleCustodyRequest>;
  export function coordinatorBundleCustodyRequestBindings(value: BundleCustodyRequest): BundleHoldBinding[];
  export function coordinatorBundleCustodyRequestIdentity(value: BundleCustodyRequest): string;
  export function coordinatorBundleCustodyRequestJson(value: BundleCustodyRequest): Result<string>;
  export function coordinatorBundleCustodyRequestOperation(
    value: BundleCustodyRequest
  ): import('./index.mjs').BundleCustodyOperation;
  export function coordinatorBundleCustodyRequestPrepare(
    distribution: BundleDistribution,
    binding: BundleHoldBinding,
    operation: string
  ): Result<BundleCustodyRequest>;
  export function coordinatorBundleCustodyRequestScope(value: BundleCustodyRequest): BundleHoldScope;
  export function coordinatorBundleCustodyResponseAdmitJson(
    request: BundleCustodyRequest,
    body: string,
    claimedCid: string
  ): Result<BundleCustodyResponse>;
  export function coordinatorBundleCustodyResponseBinding(value: BundleCustodyResponse): BundleHoldBinding;
  export function coordinatorBundleCustodyResponseCatalogText(value: BundleCustodyResponse): string;
  export function coordinatorBundleCustodyResponseIdentity(value: BundleCustodyResponse): string;
  export function coordinatorBundleCustodyResponseJson(value: BundleCustodyResponse): Result<string>;
  export function coordinatorBundleCustodyResponseKind(
    value: BundleCustodyResponse
  ): 'context' | 'observation';
  export function coordinatorBundleCustodyResponseObservationText(
    value: BundleCustodyResponse
  ): import('./index.mjs').BundleCustodyObservation | '';
  export function coordinatorBundleCustodyResponseRevisionText(value: BundleCustodyResponse): string;
  export function coordinatorBundleDistributionAdmitJson(
    body: string,
    claimedCid: string
  ): Result<BundleDistribution>;
  export function coordinatorBundleDistributionContains(
    value: BundleDistribution,
    runtimeBundleCid: string
  ): boolean;
  export function coordinatorBundleDistributionIdentity(value: BundleDistribution): string;
  export function coordinatorBundleDistributionJson(value: BundleDistribution): Result<string>;
  export function coordinatorBundleDistributionPrepare(
    members: readonly string[]
  ): Result<BundleDistribution>;
  export function coordinatorBundleDistributionProjection(value: BundleDistribution): string[];
  export function coordinatorBundleHoldBindingAdmitJson(
    distribution: BundleDistribution,
    body: string,
    claimedCid: string
  ): Result<BundleHoldBinding>;
  export function coordinatorBundleHoldBindingIdentity(value: BundleHoldBinding): string;
  export function coordinatorBundleHoldBindingJson(value: BundleHoldBinding): Result<string>;
  export function coordinatorBundleHoldBindingProjection(value: BundleHoldBinding): string[];
  export function coordinatorBundleHoldBindingScope(value: BundleHoldBinding): Result<BundleHoldScope>;
  export function coordinatorBundleHoldScopeAdmitJson(
    distribution: BundleDistribution,
    body: string,
    claimedCid: string
  ): Result<BundleHoldScope>;
  export function coordinatorBundleHoldScopeIdentity(value: BundleHoldScope): string;
  export function coordinatorBundleHoldScopeJson(value: BundleHoldScope): Result<string>;
  export function coordinatorBundleHoldScopePrepare(
    distribution: BundleDistribution,
    coordinatorAuthority: string,
    workspaceId: string,
    authorityScopeCid: string,
    environment: string,
    setRevisionCid: string,
    runtimeBundleCid: string,
    siteKey: string,
    siteGeneration: number,
    attemptId: string
  ): Result<BundleHoldScope>;
  export function coordinatorBundleHoldScopeProjection(value: BundleHoldScope): string[];
  export function coordinatorCanRetireCancellationDelivery(record: IntentRecord): boolean;
  export function coordinatorCheckedOutputIntentCid(checked: CheckedOutputPlan): string;
  export function coordinatorCheckedOutputPlanCid(checked: CheckedOutputPlan): string;
  export function coordinatorCheckedOutputPublicationFacts(checked: CheckedOutputPlan): string[];
  export function coordinatorCommitIntent(admission: IntentAdmission): Result<IntentRecord>;
  export function coordinatorCommitOutputIntent(admission: OutputIntentAdmission): Result<OutputRecord>;
  export function coordinatorCommitOutputTransition(transition: OutputTransition): Result<OutputRecord>;
  export function coordinatorCommitTransition(transition: Transition): Result<void>;
  export function coordinatorCreateJournal(authority: string): Result<Journal>;
  export function coordinatorDeliveryEnvelopeJson(request: DispatchRequest, body: string): Result<string>;
  export function coordinatorDispatchCid(request: DispatchRequest): string;
  export function coordinatorDispatchJson(request: DispatchRequest): Result<string>;
  export function coordinatorDispatchRoute(request: DispatchRequest): string[];
  export function coordinatorDurableDispatchCid(durable: DurableRecord): string;
  export function coordinatorDurableOutputJson(durable: DurableOutputRecord): string;
  export function coordinatorDurableOutputPollJson(durable: DurableOutputRecord): Result<string>;
  export function coordinatorDurableOutputPublicationFacts(durable: DurableOutputRecord): string[];
  export function coordinatorDurableOutputRequestJson(durable: DurableOutputRecord): Result<string>;
  export function coordinatorDurableOutputRevision(durable: DurableOutputRecord): number;
  export function coordinatorDurableRequest(durable: DurableRecord): DispatchRequest;
  export function coordinatorDurableRevision(durable: DurableRecord): number;
  export function coordinatorEffectCheckpointAcceptedJson(report: EffectCheckpointValue): Result<string>;
  export function coordinatorEffectCheckpointRefusedJson(
    report: EffectCheckpointValue,
    reason: string
  ): Result<string>;
  export function coordinatorEffectCheckpointReplyAdmit(
    report: EffectCheckpointValue,
    body: string
  ): Result<readonly ['accepted', ''] | readonly ['refused', import('./index.mjs').EffectCheckpointRefusal]>;
  export function coordinatorEffectCheckpointReportAdmit(
    body: string,
    request: DispatchRequest,
    maxWireBytes: number,
    maxNodes: number,
    maxDepth: number
  ): Result<EffectCheckpointValue>;
  export function coordinatorEffectCheckpointReportProjection(report: EffectCheckpointValue): string[];
  export function coordinatorEffectCurrentPollJson(query: EffectCurrentQueryValue): Result<string>;
  export function coordinatorEffectCurrentQueryPrepare(
    report: EffectCheckpointValue,
    effectId: string,
    queryId: string,
    maxWireBytes: number,
    maxNodes: number,
    maxDepth: number
  ): Result<EffectCurrentQueryValue>;
  export function coordinatorEffectCurrentQueryProjection(query: EffectCurrentQueryValue): string[];
  export function coordinatorEffectCurrentReplyAdmit(
    query: EffectCurrentQueryValue,
    body: string,
    maxWireBytes: number,
    maxNodes: number,
    maxDepth: number
  ): Result<EffectCurrentReplyValue>;
  export function coordinatorEffectCurrentReplyProjection(reply: EffectCurrentReplyValue): string[];
  export function coordinatorEffectResumeDeliveryJson(
    report: EffectCheckpointValue,
    resolutionWire: string,
    authentication: readonly string[],
    reviewerKeys: readonly string[],
    reviewerIds: readonly string[],
    claimant: string,
    generation: bigint,
    maxWireBytes: number,
    maxNodes: number,
    maxDepth: number
  ): Result<string>;
  export function coordinatorEffectResumePollJson(
    report: EffectCheckpointValue,
    resolutionWire: string,
    authentication: readonly string[],
    reviewerKeys: readonly string[],
    reviewerIds: readonly string[],
    claimant: string,
    generation: bigint,
    maxWireBytes: number,
    maxNodes: number,
    maxDepth: number
  ): Result<string>;
  export function coordinatorExactRetransmissionEligible(
    record: IntentRecord,
    request: DispatchRequest
  ): boolean;
  export function coordinatorHolderTerminalAcceptedJson(report: HolderTerminalValue): Result<string>;
  export function coordinatorHolderTerminalReplyAdmit(
    report: HolderTerminalValue,
    body: string
  ): Result<void>;
  export function coordinatorHolderTerminalReportAdmit(
    body: string,
    maximum: number
  ): Result<HolderTerminalValue>;
  export function coordinatorHolderTerminalReportDispatches(report: HolderTerminalValue): DispatchRequest[];
  export function coordinatorHolderTerminalReportProjection(report: HolderTerminalValue): string[];
  export function coordinatorInitialDeliveryEligible(
    record: IntentRecord,
    request: DispatchRequest,
    expectedAuthority: string,
    expectedSite: string,
    expectedGeneration: number,
    authorizationCurrent: boolean,
    cancellationRequested: boolean,
    outcomePersistedBeforeEverySend: boolean
  ): Result<boolean>;
  export function coordinatorIntentIsNew(admission: IntentAdmission): boolean;
  export function coordinatorIssueOutputPlanPollJson(
    durable: DurableRecord,
    storeAuthorityCid: string,
    publicationAttemptCid: string,
    resultDefinitionCid: string,
    orderingEvidenceCid: string,
    coordinatorAuthority: string,
    transferAttempt: string,
    transferRoute: string,
    destinationSiteKey: string,
    destinationSiteGeneration: number,
    transferMaxBytes: bigint,
    transferExpiresUnixMs: bigint,
    sourceGrantCid: string,
    destinationGrantCid: string,
    routeCapabilityCid: string,
    transferOrigin: string
  ): Result<string>;
  export function coordinatorOutputAdmissionDurableJson(checked: CheckedOutputPlan): Result<string>;
  export function coordinatorOutputInitialPollJson(record: OutputRecord): Result<string>;
  export function coordinatorOutputIntentIsNew(admission: OutputIntentAdmission): boolean;
  export function coordinatorOutputRecordStatus(record: OutputRecord): string[];
  export function coordinatorOutputReportAckJson(record: OutputRecord, body: string): Result<string>;
  export function coordinatorOutputReportRefusalJson(
    record: OutputRecord,
    body: string,
    reason: string
  ): Result<string>;
  export function coordinatorOutputResultJson(record: OutputRecord): Result<string>;
  export function coordinatorOutputTransferRequestCid(durable: DurableOutputRecord): string;
  export function coordinatorOutputTransitionDurableJson(
    durable: DurableOutputRecord,
    transition: OutputTransition
  ): Result<string>;
  export function coordinatorOutputTransitionExpectedRevision(transition: OutputTransition): number;
  export function coordinatorPayloadAdmitDurableJson(body: string): Result<DurablePayloadRecord>;
  export function coordinatorPayloadAdmitRequestJson(
    body: string,
    claimedCid: string
  ): Result<PayloadRequest>;
  export function coordinatorPayloadCommitTransition(transition: PayloadTransition): Result<PayloadRecord>;
  export function coordinatorPayloadDurableRequestCid(durable: DurablePayloadRecord): string;
  export function coordinatorPayloadDurableRevision(durable: DurablePayloadRecord): number;
  export function coordinatorPayloadDurableState(
    durable: DurablePayloadRecord
  ): ReturnType<typeof import('./index.mjs').durablePayloadState>;
  export function coordinatorPayloadPrepareOpaqueOwned(
    record: PayloadRecord,
    custodyCid: string
  ): Result<PayloadTransition>;
  export function coordinatorPayloadPrepareOpaqueReclaiming(
    record: PayloadRecord,
    custodyCid: string
  ): Result<PayloadTransition>;
  export function coordinatorPayloadPrepareOpaqueSealed(
    record: PayloadRecord,
    custodyCid: string,
    actualBytes: bigint,
    physicalDigest: string
  ): Result<PayloadTransition>;
  export function coordinatorPayloadPrepareReclaimed(record: PayloadRecord): Result<PayloadTransition>;
  export function coordinatorPayloadPrepareRecord(request: PayloadRequest): PayloadRecord;
  export function coordinatorPayloadPrepareReserved(record: PayloadRecord): Result<PayloadTransition>;
  export function coordinatorPayloadPrepareWriting(record: PayloadRecord): Result<PayloadTransition>;
  export function coordinatorPayloadRecordActualBytes(record: PayloadRecord): bigint;
  export function coordinatorPayloadRecordDigest(record: PayloadRecord): string;
  export function coordinatorPayloadRecordDurableJson(record: PayloadRecord): Result<string>;
  export function coordinatorPayloadRecordOpaqueGeneration(record: PayloadRecord): string | undefined;
  export function coordinatorPayloadRecordOpaqueOwnership(record: PayloadRecord): string | undefined;
  export function coordinatorPayloadRequestCid(request: PayloadRequest): string;
  export function coordinatorPayloadRequestFacts(request: PayloadRequest): string[];
  export function coordinatorPayloadRequestFromDurable(durable: DurablePayloadRecord): PayloadRequest;
  export function coordinatorPayloadRequestFromOutput(durable: DurableOutputRecord): PayloadRequest;
  export function coordinatorPayloadRequestMaxBytes(request: PayloadRequest): bigint;
  export function coordinatorPayloadRestoreDurable(durable: DurablePayloadRecord): Result<PayloadRecord>;
  export function coordinatorPayloadTransitionDurableJson(transition: PayloadTransition): Result<string>;
  export function coordinatorPayloadTransitionExpectedRevision(transition: PayloadTransition): number;
  export function coordinatorPlanSiteCandidate(
    duration: bigint | undefined,
    startup: bigint | undefined,
    capacitySupported: boolean,
    acceptsTransfer: boolean,
    transferProviderAvailable: boolean,
    transferDuration: bigint | undefined,
    transferRequired: readonly boolean[],
    sharedTransfer: readonly boolean[],
    sourceRevoked: readonly boolean[],
    estimateAvailable: readonly boolean[],
    transferBytes: readonly bigint[],
    retainedBytes: readonly bigint[],
    executionBytes: readonly bigint[]
  ): readonly [number, bigint];
  export function coordinatorPollCancelJson(request: DispatchRequest): Result<string>;
  export function coordinatorPollDispatchJson(
    request: DispatchRequest,
    inputBindingBody: string,
    maxBindingBytes: number
  ): Result<string>;
  export function coordinatorPollDispatchMaterialsJson(
    request: DispatchRequest,
    inputBindingBody: string,
    maxBindingBytes: number,
    runMaterials: string
  ): Result<string>;
  export function coordinatorPollQueryJson(request: DispatchRequest): Result<string>;
  export function coordinatorPollReleaseJson(request: DispatchRequest): Result<string>;
  export function coordinatorPrepareDispatch(
    coordinatorAuthority: string,
    runDefinitionCid: string,
    taskKey: string,
    taskAttempt: number,
    dispatchId: string,
    siteKey: string,
    siteGeneration: number,
    runtimeBundleCid: string,
    connectorRegistration: string,
    connectorRevision: string,
    strategyRevision: string,
    inputBindingCid: string,
    obligationsCid: string,
    budgetCid: string,
    evidenceIssuerCapabilityCid: string,
    grantCid: string
  ): Result<DispatchRequest>;
  export function coordinatorPrepareIntent(
    journal: Journal,
    request: DispatchRequest
  ): Result<IntentAdmission>;
  export function coordinatorPrepareOutputIntent(
    journal: Journal,
    checked: CheckedOutputPlan
  ): Result<OutputIntentAdmission>;
  export function coordinatorPrepareOutputResultJson(
    durable: DurableOutputRecord,
    reply: string,
    payloadPhysicalDigest: string
  ): Result<string>;
  export function coordinatorPrepareOutputSuccessJson(
    record: OutputRecord,
    body: string
  ): Result<OutputTransition>;
  export function coordinatorPrepareOutputUnknown(record: OutputRecord): Result<OutputTransition>;
  export function coordinatorPrepareResponseObservation(
    record: IntentRecord,
    response: DispatchResponse
  ): Result<Transition>;
  export function coordinatorPrepareUnknown(record: IntentRecord): Result<Transition>;
  export function coordinatorRecordStateCodes(record: IntentRecord): string[];
  export function coordinatorRedeliveryEligible(
    record: IntentRecord,
    request: DispatchRequest,
    notSeenBody: string,
    expectedAuthority: string,
    expectedSite: string,
    expectedGeneration: number,
    authorizationCurrent: boolean,
    cancellationRequested: boolean
  ): Result<boolean>;
  export function coordinatorResponseDurableJson(
    durable: DurableRecord,
    transition: Transition,
    response: DispatchResponse
  ): Result<string>;
  export function coordinatorRestoreDurable(journal: Journal, durable: DurableRecord): Result<IntentRecord>;
  export function coordinatorRestoreDurableOutput(
    journal: Journal,
    durable: DurableOutputRecord
  ): Result<OutputRecord>;
  export function coordinatorSelectSiteCandidate(
    durations: readonly bigint[],
    keys: readonly string[]
  ): number;
  export function coordinatorTransitionDurableJson(
    durable: DurableRecord,
    transition: Transition
  ): Result<string>;
  export function coordinatorTransitionExpectedRevision(transition: Transition): number;
  export function coordinatorTransitionIsReplay(transition: Transition): boolean;
}
