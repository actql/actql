// Compiler ports available to strict TypeScript before normal Run Host packaging.
// Opaque MoonBit values are nominal and never become public Host handles.
declare module '*/dist/client_values_host_abi.js' {
  const moonBitValue: unique symbol;
  type Opaque<Name extends string> = {readonly [moonBitValue]: Name};
  export type Result<Value> = {readonly $tag: 1; readonly _0: Value} |
    {readonly $tag: 0; readonly _0: unknown};
  type BoxedOption<Value> = {readonly $tag: 1; readonly _0: Value} | {readonly $tag: 0};

  export type CapturedResultSnapshot = Opaque<'CapturedResultSnapshot'>;
  export type CheckEnvironment = Opaque<'CheckEnvironment'>;
  export type ClientCancellationIdentity = Opaque<'ClientCancellationIdentity'>;
  export type ClientEffectAllowedRun = Opaque<'ClientEffectAllowedRun'>;
  export type ClientEffectCompilation = Opaque<'ClientEffectCompilation'>;
  export type ClientEffectIssuedNormalizationMaterials = Opaque<'ClientEffectIssuedNormalizationMaterials'>;
  export type ClientEffectRunMaterials = Opaque<'ClientEffectRunMaterials'>;
  export type ClientRemoteEffectTaskProgress = Opaque<'ClientRemoteEffectTaskProgress'>;
  export type ClientRemoteEffectTaskRunProjection = Opaque<'ClientRemoteEffectTaskRunProjection'>;
  export type ClientRemoteTaskProgress = Opaque<'ClientRemoteTaskProgress'>;
  export type ClientRemoteTaskRunProjection = Opaque<'ClientRemoteTaskRunProjection'>;
  export type ClientRequestIdentity = Opaque<'ClientRequestIdentity'>;
  export type ClientRetainedInputEdge = Opaque<'ClientRetainedInputEdge'>;
  export type ClientRetainedInputProducer = Opaque<'ClientRetainedInputProducer'>;
  export type ClientSourcePreparation = Opaque<'ClientSourcePreparation'>;
  export type ClientSubmittedIntent = Opaque<'ClientSubmittedIntent'>;
  export type ClientTaskCompilation = Opaque<'ClientTaskCompilation'>;
  export type ClientValuesCompilation = Opaque<'ClientValuesCompilation'>;
  export type ClientValuesHostAllowedRun = Opaque<'ClientValuesHostAllowedRun'>;
  export type ClientValuesHostProgramPreparation = Opaque<'ClientValuesHostProgramPreparation'>;
  export type ClientValuesHostRetainedInputPlan = Opaque<'ClientValuesHostRetainedInputPlan'>;
  export type ClientValuesHostRetainedInputQuery = Opaque<'ClientValuesHostRetainedInputQuery'>;
  export type ClientValuesHostRetainedTaskInput = Opaque<'ClientValuesHostRetainedTaskInput'>;
  export type DeliveryGrantUsageClaim = Opaque<'DeliveryGrantUsageClaim'>;
  export type DispatchRequest = Opaque<'DispatchRequest'>;
  export type DurableResultRowFrames = Opaque<'DurableResultRowFrames'>;
  export type EffectPreviewIdentity = Opaque<'EffectPreviewIdentity'>;
  export type EffectfulFinalRunEvidence = Opaque<'EffectfulFinalRunEvidence'>;
  export type PreparedClientEffectComputation = Opaque<'PreparedClientEffectComputation'>;
  export type PreparedClientProgram = Opaque<'PreparedClientProgram'>;
  export type PreparedPublishedQueryEnvironment = Opaque<'PreparedPublishedQueryEnvironment'>;
  export type PublicationContract = Opaque<'PublicationContract'>;
  export type RemoteRetainedCurrentReply = Opaque<'RemoteRetainedCurrentReply'>;
  export type RemoteRetainedInputIntent = Opaque<'RemoteRetainedInputIntent'>;
  export type RemoteRetainedInputResult = Opaque<'RemoteRetainedInputResult'>;
  export type ResultAccessProgress = Opaque<'ResultAccessProgress'>;
  export type ResultDeliverySerializer = Opaque<'ResultDeliverySerializer'>;
  export type ResultMaterialHolds = Opaque<'ResultMaterialHolds'>;
  export type ResultOrderingEvidence = Opaque<'ResultOrderingEvidence'>;
  export type RunEvidenceValue = Opaque<'RunEvidenceValue'>;
  export type RunPublicationAdmission = Opaque<'RunPublicationAdmission'>;
  export type SealedCheckpoint = Opaque<'SealedCheckpoint'>;
  export type SubmissionEpoch = Opaque<'SubmissionEpoch'>;

  export function clientValuesHostAdmitCapturedResultSnapshot(
    definition: PublicationContract, artifact: PublicationContract, rowsWire: string,
    fields: readonly string[], maxWireBytes: number, maxNodes: number, maxDepth: number): Result<CapturedResultSnapshot>;
  export function clientValuesHostAdmitCompletedSourceObservation(
    sourceEvidenceWire: string, inputLogicalWire: string, sourceRef: string, sourceContractCid: string,
    authorityScopeCid: string, effectiveDataPolicyCid: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<string>;
  export function clientValuesHostAdmitEffectCheckpointBinding(
    allowed: ClientEffectAllowedRun, definition: PublicationContract, wire: string): Result<SealedCheckpoint>;
  export function clientValuesHostAdmitEffectCheckpointPreview(
    original: SealedCheckpoint, allowed: ClientEffectAllowedRun, definition: PublicationContract,
    storedWire: string, previewWire: string, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<EffectPreviewIdentity>;
  export function clientValuesHostAdmitEffectPreviewIdentity(
    previewWire: string, expectedRunIdentityCid: string, expectedAuthoringContextCid: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<EffectPreviewIdentity>;
  export function clientValuesHostAdmitEffectRunMaterials(
    wire: string, definitionCid: string, textTime: boolean, veca: boolean, rela: boolean, sga: boolean,
    tea: boolean, calendar: boolean, textRank: boolean,
    original: ClientEffectIssuedNormalizationMaterials | undefined,
    expectedRequest: ClientRequestIdentity | undefined,
    sourcePreparation: ClientSourcePreparation | undefined, numericProfileCid: string | undefined): Result<ClientEffectRunMaterials>;
  export function clientValuesHostAdmitEffectfulFinalRunEvidence(
    runDefinition: PublicationContract, invocation: PublicationContract,
    definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[],
    derivations: readonly PublicationContract[], orderings: readonly PublicationContract[],
    retentions: readonly PublicationContract[], manifest: PublicationContract,
    computationReceipt: PublicationContract, capturedRun: PublicationContract,
    preview: EffectPreviewIdentity, setReceiptWire: string, memberReceiptWires: readonly string[],
    finalReceipt: PublicationContract, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<EffectfulFinalRunEvidence>;
  export function clientValuesHostAdmitOriginalResultOccurrenceEvidence(
    definition: PublicationContract, artifact: PublicationContract, derivation: PublicationContract,
    ordering: PublicationContract, retention: PublicationContract, logicalValueCid: string,
    resultSchemaCid: string, effectiveDataPolicyCid: string): Result<ResultOrderingEvidence>;
  export function clientValuesHostAdmitPublicationContract(
    name: string, wire: string, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostAdmitRequestIdentity(
    authorityScopeCid: string, callerRequestId: string, programDefinitionCid: string,
    parameterValuesCid: string, callerInputIntentCid: string, logicalRequestScopeCid: string,
    intentFingerprintCid: string): Result<ClientRequestIdentity>;
  export function clientValuesHostAdmitResultMaterialHolds(wire: string): Result<ResultMaterialHolds>;
  export function clientValuesHostAdmitRetainedInputCurrentReply(
    query: ClientValuesHostRetainedInputQuery, body: string, cid: string, maxChunks: number,
    maxManifestBytes: number, maxReferencedBytes: bigint): Result<RemoteRetainedCurrentReply>;
  export function clientValuesHostAdmitRetainedInputIntent(
    producer: ClientRetainedInputProducer, body: string, cid: string): Result<RemoteRetainedInputIntent>;
  export function clientValuesHostAdmitRetainedInputPlan(
    producer: ClientRetainedInputProducer, intent: RemoteRetainedInputIntent, body: string, cid: string,
    siteCurrent: (argument1: string, argument2: string, argument3: string) => boolean,
    authority: () => string, nowUnixMs: () => bigint,
    authorized: (argument1: string, argument2: string) => boolean, maxChunks: number,
    maxManifestBytes: number, maxReferencedBytes: bigint): Result<ClientValuesHostRetainedInputPlan>;
  export function clientValuesHostAdmitRetainedInputResult(
    value: ClientValuesHostRetainedInputPlan, body: string, cid: string): Result<RemoteRetainedInputResult>;
  export function clientValuesHostAdmitRetainedTaskInput(
    value: ClientValuesHostRetainedTaskInput, savedWire: string, savedCid: string): Result<ClientValuesHostRetainedTaskInput>;
  export function clientValuesHostAdmitRun(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation,
    preparedInvocationWire: string, authorizationWire: string): Result<RunPublicationAdmission>;
  export function clientValuesHostAdmitRunDefinition(wire: string): Result<PublicationContract>;
  export function clientValuesHostAdmitRunEvidenceValue(
    name: string, wire: string, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<RunEvidenceValue>;
  export function clientValuesHostAdmitSourceFreeRequestIdentity(
    authorityScopeCid: string, callerRequestId: string, programDefinitionCid: string,
    parameterValuesCid: string, callerInputIntentCid: string, logicalRequestScopeCid: string,
    intentFingerprintCid: string): Result<ClientRequestIdentity>;
  export function clientValuesHostAdmitSourceFreeRunDefinition(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation,
    admission: RunPublicationAdmission, wire: string): Result<PublicationContract>;
  export function clientValuesHostAdmitTaskRun(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation, preparedInvocationWire: string,
    authorizationWire: string): Result<RunPublicationAdmission>;
  export function clientValuesHostAdmitTaskRunDefinition(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, wire: string): Result<PublicationContract>;
  export function clientValuesHostAllowedEffectAuthorizationWire(allowed: ClientEffectAllowedRun): string;
  export function clientValuesHostAllowedEffectPreparedWire(allowed: ClientEffectAllowedRun): string;
  export function clientValuesHostAllowedRunAdmission(value: ClientValuesHostAllowedRun): RunPublicationAdmission;
  export function clientValuesHostAllowedRunAuthorizationWire(value: ClientValuesHostAllowedRun): string;
  export function clientValuesHostAllowedRunPreparedWire(value: ClientValuesHostAllowedRun): string;
  export function clientValuesHostBeginResultAccessProgress(): ResultAccessProgress;
  export function clientValuesHostBeginResultDelivery(serializer: ResultDeliverySerializer): Result<string>;
  export function clientValuesHostBeginResultMaterialHolds(
    bindingCid: string, materialGenerationCid: string): Result<ResultMaterialHolds>;
  export function clientValuesHostBindPreparedEffectRunMaterials(
    allowed: ClientEffectAllowedRun, definition: PublicationContract,
    issued: ClientEffectIssuedNormalizationMaterials, request: ClientRequestIdentity): Result<ClientEffectRunMaterials>;
  export function clientValuesHostCancelDurableResultRowFrames(frames: DurableResultRowFrames): void;
  export function clientValuesHostCancellationIntentCid(value: ClientCancellationIdentity): string;
  export function clientValuesHostCaptureOriginalTaskRunPlan(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, maxBytes: number,
    maxNodes: number, maxDepth: number): Result<string[]>;
  export function clientValuesHostCaptureOriginalValuesRunPlan(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, maxBytes: number,
    maxNodes: number, maxDepth: number): Result<string[]>;
  export function clientValuesHostCheckLogicalMapBinding(
    map: RunEvidenceValue, plan: PublicationContract, maxBytes: number, maxNodes: number,
    maxDepth: number): Result<void>;
  export function clientValuesHostCheckRunBinding(
    prepared: PreparedClientProgram, admission: RunPublicationAdmission, definition: PublicationContract): Result<void>;
  export function clientValuesHostCheckStoredPlanView(
    wire: string, maxBytes: number, maxNodes: number, maxDepth: number): Result<void>;
  export function clientValuesHostCompile(prepared: PreparedClientProgram): Result<ClientValuesCompilation>;
  export function clientValuesHostCompileEffect(
    prepared: PreparedClientEffectComputation, normalizationProfile: boolean): Result<ClientEffectCompilation>;
  export function clientValuesHostCompileTasks(prepared: PreparedClientProgram): Result<ClientTaskCompilation>;
  export function clientValuesHostCompiledPlanCid(value: ClientValuesCompilation): string;
  export function clientValuesHostCompiledPlanWire(value: ClientValuesCompilation): string;
  export function clientValuesHostDeliveryFailureTerminalAction(cancellationObserved: boolean): number;
  export function clientValuesHostDeliveryGrantUsageClaimIsNew(claim: DeliveryGrantUsageClaim): boolean;
  export function clientValuesHostDeliveryGrantUsageClaimWire(claim: DeliveryGrantUsageClaim): string;
  export function clientValuesHostDeliveryRecordRetryAction(nextRecord: number, recordCount: number): number;
  export function clientValuesHostDeliveryRecordTransition(
    previous: PublicationContract | undefined, next: PublicationContract): boolean;
  export function clientValuesHostDeliveryResultDefinitionCid(
    manifest: PublicationContract, attempt: PublicationContract): Result<string>;
  export function clientValuesHostDeliverySuccessValid(
    attempt: PublicationContract, receipt: PublicationContract, record: PublicationContract): boolean;
  export function clientValuesHostDescribeCommittedResult(
    index: PublicationContract, manifest: PublicationContract, resultName: string,
    bindings: readonly PublicationContract[], definition: PublicationContract, schemaWire: string,
    format: string, maxWireBytes: number, maxNodes: number, maxDepth: number): string | undefined;
  export function clientValuesHostDispatchCid(request: DispatchRequest): string;
  export function clientValuesHostDispatchWire(request: DispatchRequest): Result<string>;
  export function clientValuesHostEffectCheckpointBindingFields(original: SealedCheckpoint): Result<string[]>;
  export function clientValuesHostEffectCheckpointCancelledState(
    original: SealedCheckpoint, allowed: ClientEffectAllowedRun, definition: PublicationContract,
    storedWire: string, updatedAt: string, declaredResults: readonly string[]): Result<string>;
  export function clientValuesHostEffectCheckpointMembers(
    allowed: ClientEffectAllowedRun, definition: PublicationContract, checkpointWire: string): Result<string[]>;
  export function clientValuesHostEffectCheckpointReconciliationState(
    original: SealedCheckpoint, allowed: ClientEffectAllowedRun, definition: PublicationContract,
    storedWire: string, previewWire: string, invocationWire: string, setWire: string,
    memberReceiptWires: readonly string[], updatedAt: string, declaredResults: readonly string[]): Result<string>;
  export function clientValuesHostEffectCheckpointWaitingState(
    original: SealedCheckpoint, storedWire: string, updatedAt: string,
    declaredResults: readonly string[]): Result<string>;
  export function clientValuesHostEffectCompiledPlanWire(compilation: ClientEffectCompilation): string;
  export function clientValuesHostEffectPreviewMemberCount(preview: EffectPreviewIdentity): number;
  export function clientValuesHostEffectPreviewSemanticIdentity(preview: EffectPreviewIdentity): string;
  export function clientValuesHostEffectRequestIdentity(
    prepared: PreparedClientEffectComputation, authorityScopeCid: string, requestId: string): Result<ClientRequestIdentity>;
  export function clientValuesHostEffectResultDefinitions(compilation: ClientEffectCompilation): Result<string[]>;
  export function clientValuesHostEffectResultNames(compilation: ClientEffectCompilation): string[];
  export function clientValuesHostEffectResultSchema(
    compilation: ClientEffectCompilation, result: number): Result<string[]>;
  export function clientValuesHostEffectRetainedInputEdge(
    allowed: ClientEffectAllowedRun, definition: PublicationContract): Result<ClientRetainedInputEdge>;
  export function clientValuesHostEffectReviewProjectionBindingFacts(review: RunEvidenceValue): string[];
  export function clientValuesHostEffectShape(compilation: ClientEffectCompilation): number[];
  export function clientValuesHostEffectSourceEvidenceFacts(
    compilation: ClientEffectCompilation, stage: number, sourceIndex: number): BoxedOption<string[]>;
  export function clientValuesHostEffectSourceInputBinding(
    compilation: ClientEffectCompilation, request: ClientRequestIdentity | undefined): Result<string>;
  export function clientValuesHostEffectStartCurrent(
    allowed: ClientEffectAllowedRun, definition: PublicationContract, at: string): boolean;
  export function clientValuesHostEffectTaskKeys(compilation: ClientEffectCompilation): Result<string[]>;
  export function clientValuesHostEffectTaskProgressComputationComplete(
    value: ClientRemoteEffectTaskProgress): boolean;
  export function clientValuesHostEffectTaskProgressFields(value: ClientRemoteEffectTaskProgress): string[][];
  export function clientValuesHostEffectTaskProgressNext(value: ClientRemoteEffectTaskProgress): number;
  export function clientValuesHostEffectTaskProgressResultTasks(value: ClientRemoteEffectTaskProgress): number[];
  export function clientValuesHostEffectTaskProgressScopes(value: ClientRemoteEffectTaskProgress): string[][];
  export function clientValuesHostEffectTaskProgressTaskCleanupComplete(
    value: ClientRemoteEffectTaskProgress): boolean;
  export function clientValuesHostEffectTaskRunFields(value: ClientRemoteEffectTaskRunProjection): string[];
  export function clientValuesHostEffectTaskRunWork(value: ClientRemoteEffectTaskRunProjection): string[];
  export function clientValuesHostEffectTemplateWire(compilation: ClientEffectCompilation): string;
  export function clientValuesHostEffectfulFinalRunAllUnattempted(value: EffectfulFinalRunEvidence): boolean;
  export function clientValuesHostEffectfulFinalRunFailedState(
    value: EffectfulFinalRunEvidence, updatedAt: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<string>;
  export function clientValuesHostEffectfulFinalRunReceipt(value: EffectfulFinalRunEvidence): PublicationContract;
  export function clientValuesHostEffectfulFinalRunReconciliationState(
    value: EffectfulFinalRunEvidence, updatedAt: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<string>;
  export function clientValuesHostEffectfulFinalRunStatus(value: EffectfulFinalRunEvidence): string;
  export function clientValuesHostEnvironment(
    body: string, evidenceBundleCid: string, textTime: boolean, veca: boolean, rela: boolean,
    sga: boolean, tea: boolean, calendar: boolean, textRank: boolean,
    numericProfileCid: string | undefined): CheckEnvironment | undefined;
  export function clientValuesHostExistingDeliveryAttemptAction(record: PublicationContract | undefined): number;
  export function clientValuesHostFactManifestWire(value: ClientValuesCompilation): string;
  export function clientValuesHostFeedDurableResultRowFrames(
    frames: DurableResultRowFrames, chunk: Uint8Array): Result<string[]>;
  export function clientValuesHostFinishDurableResultRowFrames(frames: DurableResultRowFrames): Result<number[]>;
  export function clientValuesHostFinishResultDelivery(serializer: ResultDeliverySerializer): Result<string>;
  export function clientValuesHostInspectCanonicalResultRows(
    rowsWire: string, fields: readonly string[], maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<string[]>;
  export function clientValuesHostInspectEffectTaskProgress(
    allowed: ClientEffectAllowedRun, definition: PublicationContract, authority: string,
    wires: readonly string[]): Result<ClientRemoteEffectTaskProgress>;
  export function clientValuesHostInspectTaskProgress(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, authority: string,
    wires: readonly string[]): Result<ClientRemoteTaskProgress>;
  export function clientValuesHostIssueAllowedEffectRun(
    compilation: ClientEffectCompilation, executionContextCid: string, hostPolicyCid: string,
    expiresAt: string): Result<ClientEffectAllowedRun>;
  export function clientValuesHostIssueAllowedRun(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation, executionContextCid: string,
    hostPolicyCid: string, expiresAt: string): Result<ClientValuesHostAllowedRun>;
  export function clientValuesHostIssueAllowedTaskRun(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation, executionContextCid: string,
    hostPolicyCid: string, expiresAt: string): Result<ClientValuesHostAllowedRun>;
  export function clientValuesHostIssueCheckedValuesResultOccurrenceEvidence(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation,
    definition: PublicationContract, logicalValueCid: string, resultSchemaCid: string, scopeCid: string,
    effectiveDataPolicyCid: string, issuerId: string, authorityScopeCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): Result<ResultOrderingEvidence>;
  export function clientValuesHostIssueCompleteResultArtifact(
    definition: PublicationContract, invocation: PublicationContract, evidence: ResultOrderingEvidence,
    retention: PublicationContract, actualRowCount: number, maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueDeliveryAttempt(
    index: PublicationContract, manifest: PublicationContract, grant: PublicationContract,
    resultName: string, format: string, attemptId: string, requestedAt: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueDeliveryRecord(
    attempt: PublicationContract, previous: PublicationContract | undefined, state: string,
    confirmedByteCount: number, exposure: string, possibleUnconfirmedMaxBytes: number | undefined,
    deliveredSha256: string | undefined, receipt: PublicationContract | undefined,
    failureCid: string | undefined, observedAt: string, cleanupOwnerCids: readonly string[],
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueDurableResultBinding(
    runDefinition: PublicationContract, definition: PublicationContract, invocation: PublicationContract,
    artifact: PublicationContract, ordering: PublicationContract, retention: PublicationContract,
    codecContractCid: string, resultFields: readonly string[], resultSchemaWire: string,
    materialGenerationCid: string, storeAuthorityCid: string, rowCount: number, byteCount: number,
    physicalSha256: string, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueEffectFreeRunReceipt(
    admission: RunPublicationAdmission, runDefinition: PublicationContract,
    invocation: PublicationContract, observation: RunEvidenceValue,
    definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[],
    manifest: PublicationContract, normalizationJournal: RunEvidenceValue,
    bindingNames: readonly string[], bindingDigests: readonly string[],
    sourceEvidence: readonly RunEvidenceValue[], modelEvidence: readonly RunEvidenceValue[],
    barrierAttemptReceiptCids: readonly string[], maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueEffectRunDefinition(
    allowed: ClientEffectAllowedRun, scopeId: string, runId: string, createdAt: string,
    validUntil: string): Result<PublicationContract>;
  export function clientValuesHostIssueEffectRunMaterials(
    allowed: ClientEffectAllowedRun, definition: PublicationContract, environment: CheckEnvironment,
    environmentWire: string, document: string, parameters: string | undefined,
    request: ClientRequestIdentity | undefined): Result<string>;
  export function clientValuesHostIssueEffectSucceededRunStateWire(
    prepared: PreparedClientEffectComputation, allowed: ClientEffectAllowedRun,
    definition: PublicationContract, evidence: EffectfulFinalRunEvidence, observedAt: string,
    names: readonly string[], states: readonly string[], reasons: readonly string[],
    resultObservedAt: readonly string[]): string | undefined;
  export function clientValuesHostIssueEffectfulFinalRunReceipt(
    runDefinition: PublicationContract, computationReceipt: PublicationContract,
    capturedRun: PublicationContract, preview: EffectPreviewIdentity, setReceiptWire: string,
    memberReceiptWires: readonly string[], maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueManifestReadGrant(
    index: PublicationContract, manifest: PublicationContract, principalId: string, purpose: string,
    dataCeilingCid: string, maxBytes: number, maxUses: number, expiresAt: string,
    authorizationContextCid: string, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssuePreparedEffectRunMaterials(
    prepared: PreparedClientEffectComputation, allowed: ClientEffectAllowedRun,
    definition: PublicationContract, request: ClientRequestIdentity | undefined): Result<ClientEffectIssuedNormalizationMaterials>;
  export function clientValuesHostIssuePublicIndexEntry(
    runDefinition: PublicationContract, invocation: PublicationContract, manifest: PublicationContract,
    receipt: PublicationContract, capturedRun: PublicationContract,
    durableBindings: readonly PublicationContract[], request: PublicationContract,
    attempt: PublicationContract, committedAt: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssuePublicationAttempt(
    request: PublicationContract, runDefinition: PublicationContract, attemptId: string,
    fenceCid: string, externalIdempotencyKey: string | undefined, startedAt: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssuePublicationRecord(
    attempt: PublicationContract, previous: PublicationContract | undefined, state: string,
    observedAt: string, publicIndexEntry: PublicationContract | undefined,
    failureCid: string | undefined, cleanupOwnerCids: readonly string[], uncommittedConfirmed: boolean,
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssuePublicationRequest(
    runDefinition: PublicationContract, definitions: readonly PublicationContract[], namespaceId: string,
    authorityScopeCid: string, publicationPolicyCid: string, publicationTargetCid: string,
    requestedAt: string, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueResultDeliveryReceipt(
    index: PublicationContract, manifest: PublicationContract, grant: PublicationContract,
    attempt: PublicationContract, deliveredByteCount: number, deliveredSha256: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueResultManifest(
    runDefinition: PublicationContract, invocation: PublicationContract,
    definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[],
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueResultOccurrenceEvidence(
    definition: PublicationContract, logicalValueCid: string, resultSchemaCid: string,
    computationContractCid: string, inputRelationCids: readonly string[], scopeCid: string,
    effectiveDataPolicyCid: string, issuerId: string, authorityScopeCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): Result<ResultOrderingEvidence>;
  export function clientValuesHostIssueResultReadGrant(
    index: PublicationContract, manifest: PublicationContract, resultNames: readonly string[],
    formats: readonly string[], principalId: string, purpose: string, dataCeilingCid: string,
    maxBytes: number, maxUses: number, expiresAt: string, authorizationContextCid: string,
    egressAdmissionCid: string, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueRunDefinition(
    admission: RunPublicationAdmission, scopeId: string, runId: string, inputArtifactSetCid: string,
    createdAt: string, validUntil: string): Result<PublicationContract>;
  export function clientValuesHostIssueSourceFreeCapturedRun(
    runDefinition: PublicationContract, invocation: PublicationContract,
    definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[],
    manifest: PublicationContract, receipt: PublicationContract,
    snapshots: readonly CapturedResultSnapshot[], authoring: RunEvidenceValue,
    models: readonly RunEvidenceValue[], maxWireBytes: number, maxNodes: number, maxDepth: number): Result<PublicationContract>;
  export function clientValuesHostIssueSourceFreeInvocation(
    compilation: ClientValuesCompilation, dataPolicyCid: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<string[]>;
  export function clientValuesHostIssueSourceFreeRunDefinition(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation,
    admission: RunPublicationAdmission, scopeId: string, runId: string, createdAt: string,
    validUntil: string): Result<PublicationContract>;
  export function clientValuesHostIssueSourceFreeRunMaterials(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, environment: CheckEnvironment,
    environmentWire: string, program: string, parametersWire: string | undefined): Result<string>;
  export function clientValuesHostIssueSourceFreeTaskInvocation(
    compilation: ClientTaskCompilation, dataPolicyCid: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number): Result<string[]>;
  export function clientValuesHostIssueSucceededRunStateWire(
    definition: PublicationContract, compilation: ClientValuesCompilation, observedAt: string,
    names: readonly string[], states: readonly string[], reasons: readonly string[],
    resultObservedAt: readonly string[]): string | undefined;
  export function clientValuesHostIssueTaskInvocation(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, runDefinition: PublicationContract, sourceEvidenceWire: string,
    inputLogicalWire: string, sourceRef: string, sourceContractCid: string, authorityScopeCid: string,
    dataPolicyCid: string, captureStartedAt: string, captureCompletedAt: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): Result<string[]>;
  export function clientValuesHostIssueTaskRunDefinition(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, scopeId: string, runId: string, createdAt: string,
    validUntil: string): Result<PublicationContract>;
  export function clientValuesHostIssueTaskRunMaterials(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, environment: CheckEnvironment,
    environmentWire: string, program: string, parametersWire: string | undefined): Result<string>;
  export function clientValuesHostIssueTaskSucceededRunStateWire(
    definition: PublicationContract, compilation: ClientTaskCompilation, observedAt: string,
    names: readonly string[], states: readonly string[], reasons: readonly string[],
    resultObservedAt: readonly string[]): string | undefined;
  export function clientValuesHostIssueTaskUnpublishedRunStateWire(
    definition: PublicationContract, compilation: ClientTaskCompilation, observedAt: string,
    dispatchReserved: boolean, preDispatchFailureConfirmed: boolean, cancelledBeforeStart: boolean,
    executionUnknown: boolean): string | undefined;
  export function clientValuesHostIssueUnpublishedRunStateWire(
    definition: PublicationContract, compilation: ClientValuesCompilation, observedAt: string,
    dispatchReserved: boolean, preDispatchFailureConfirmed: boolean, cancelledBeforeStart: boolean,
    executionUnknown: boolean): string | undefined;
  export function clientValuesHostIssuedEffectRunMaterialsWire(
    issued: ClientEffectIssuedNormalizationMaterials): string;
  export function clientValuesHostManifestReadGrantAllowsBytes(grant: PublicationContract, bytes: number): boolean;
  export function clientValuesHostManifestReadGrantValidAt(grant: PublicationContract, at: string): boolean;
  export function clientValuesHostNextResultDeliveryRow(
    serializer: ResultDeliverySerializer, rowWire: string): Result<string>;
  export function clientValuesHostOutputContractCid(value: ClientValuesCompilation): string;
  export function clientValuesHostPlanNodeId(value: ClientValuesCompilation): string;
  export function clientValuesHostPlanWire(value: ClientValuesCompilation): string;
  export function clientValuesHostPrepare(
    document: string, format: string, environment: CheckEnvironment, parameters: string | undefined,
    publicationEnvironment: PreparedPublishedQueryEnvironment | undefined): Result<PreparedClientProgram>;
  export function clientValuesHostPrepareCancellation(
    definition: PublicationContract, definitionCid: string, authorized: boolean, terminal: boolean,
    requested: boolean): Result<string>;
  export function clientValuesHostPrepareCancellationIdentity(
    namespaceId: string, authorityScopeCid: string, cancelId: string, definition: PublicationContract,
    expectedRevision: number): Result<ClientCancellationIdentity>;
  export function clientValuesHostPrepareCancellationOperation(
    requested: ClientCancellationIdentity, retained: ClientCancellationIdentity | undefined,
    definition: PublicationContract, currentRevision: number, authorized: boolean, terminal: boolean,
    cancellationRequested: boolean): Result<string>;
  export function clientValuesHostPrepareDeliveryGrantUsageClaim(
    grant: PublicationContract, existingWire: string | undefined, attempt: PublicationContract,
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<DeliveryGrantUsageClaim>;
  export function clientValuesHostPrepareDispatch(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, request: ClientRequestIdentity,
    taskAttempt: number, dispatchId: string, siteKey: string, siteGeneration: number,
    runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string): Result<DispatchRequest>;
  export function clientValuesHostPrepareDurableResultRowFrames(
    maxBytes: number, maxRows: number, maxRowBytes: number, maxDepth: number, maxFrameBytes: number): Result<DurableResultRowFrames>;
  export function clientValuesHostPrepareEffect(
    document: string, format: string, environment: CheckEnvironment, parameters: string | undefined,
    publicationEnvironment: PreparedPublishedQueryEnvironment | undefined): Result<PreparedClientEffectComputation>;
  export function clientValuesHostPrepareEffectRetainedTaskDispatch(
    allowed: ClientEffectAllowedRun, definition: PublicationContract, request: ClientRequestIdentity,
    taskAttempt: number, dispatchId: string, siteKey: string, siteGeneration: number,
    runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string, value: ClientValuesHostRetainedTaskInput): Result<DispatchRequest>;
  export function clientValuesHostPrepareEffectSourceDispatch(
    allowed: ClientEffectAllowedRun, definition: PublicationContract, request: ClientRequestIdentity,
    taskAttempt: number, dispatchId: string, siteKey: string, siteGeneration: number,
    runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string): Result<DispatchRequest>;
  export function clientValuesHostPrepareEffectTaskPhysicalStart(
    progress: ClientRemoteEffectTaskProgress, taskKey: string, dispatchCid: string,
    requested: ClientRequestIdentity, retained: ClientRequestIdentity, definitionCid: string,
    reserved: boolean, unstarted: boolean, authorized: boolean, cancelled: boolean, failed: boolean): Result<boolean>;
  export function clientValuesHostPreparePhysicalStart(
    requested: ClientRequestIdentity, retained: ClientRequestIdentity, definition: PublicationContract,
    definitionCid: string, reserved: boolean, unstarted: boolean, authorized: boolean,
    cancellationRequested: boolean, preStartFailureConfirmed: boolean): Result<boolean>;
  export function clientValuesHostPreparePreStartFailure(
    requested: ClientRequestIdentity, retained: ClientRequestIdentity, definition: PublicationContract,
    definitionCid: string, reserved: boolean, unstarted: boolean, admissionDenied: boolean,
    cancellationRequested: boolean): Result<boolean>;
  export function clientValuesHostPrepareProgram(
    document: string, format: string, environment: CheckEnvironment, parameters: string | undefined,
    publicationEnvironment: PreparedPublishedQueryEnvironment | undefined): Result<ClientValuesHostProgramPreparation>;
  export function clientValuesHostPreparePublicSourceProgram(
    intent: ClientSubmittedIntent, environment: CheckEnvironment, publication: string,
    publicationEnvironment: PreparedPublishedQueryEnvironment | undefined): Result<ClientSourcePreparation>;
  export function clientValuesHostPreparePublishedEnvironment(
    environment: CheckEnvironment, publication: string): Result<PreparedPublishedQueryEnvironment>;
  export function clientValuesHostPrepareRemoteTaskPhysicalStart(
    progress: ClientRemoteTaskProgress, taskKey: string, dispatchCid: string,
    requested: ClientRequestIdentity, retained: ClientRequestIdentity, definitionCid: string,
    reserved: boolean, unstarted: boolean, authorized: boolean, cancelled: boolean, failed: boolean): Result<boolean>;
  export function clientValuesHostPrepareResultDeliverySerializer(
    format: string, schemaWire: string, fields: readonly string[], maxWireBytes: number,
    maxNodes: number, maxDepth: number): Result<ResultDeliverySerializer>;
  export function clientValuesHostPrepareResultMaterialHoldsStep(
    value: ResultMaterialHolds, operation: string, identity: string): Result<ResultMaterialHolds>;
  export function clientValuesHostPrepareRetainedInputCurrentQuery(
    plan: ClientValuesHostRetainedInputPlan, queryId: string): Result<ClientValuesHostRetainedInputQuery>;
  export function clientValuesHostPrepareRetainedInputIntent(
    producer: ClientRetainedInputProducer, destinationGrantCid: string, routeCapabilityCid: string,
    sourceGrantCid: string, transferAttempt: string, transferExpiresUnixMs: bigint,
    transferMaxBytes: bigint): Result<RemoteRetainedInputIntent>;
  export function clientValuesHostPrepareRetainedTaskDispatch(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, request: ClientRequestIdentity,
    task: number, taskAttempt: number, dispatchId: string, siteKey: string, siteGeneration: number,
    runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string, value: ClientValuesHostRetainedTaskInput): Result<DispatchRequest>;
  export function clientValuesHostPrepareRetainedTaskDispatchWithSource(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, request: ClientRequestIdentity,
    task: number, taskAttempt: number, dispatchId: string, siteKey: string, siteGeneration: number,
    runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string, value: ClientValuesHostRetainedTaskInput,
    source: ClientSourcePreparation): Result<DispatchRequest>;
  export function clientValuesHostPrepareRetainedTaskInput(
    producer: ClientRetainedInputProducer, readTransfer: () => string, receiptWire: string,
    receiptCid: string, destinationUseId: string,
    siteCurrent: (argument1: string, argument2: string, argument3: string) => boolean,
    authority: () => string, nowUnixMs: () => bigint,
    authorized: (argument1: string, argument2: string) => boolean, maxChunks: number,
    maxManifestBytes: number, maxReferencedBytes: bigint, maxBindingBytes: number): Result<ClientValuesHostRetainedTaskInput>;
  export function clientValuesHostPrepareRunStart(
    requested: ClientRequestIdentity, retained: ClientRequestIdentity, definition: PublicationContract,
    retainedRunDefinitionCid: string, dispatchReserved: boolean, currentAuthorization: boolean): Result<number>;
  export function clientValuesHostPrepareSourceProgram(
    intent: ClientSubmittedIntent, environment: CheckEnvironment, publication: string,
    publicationEnvironment: PreparedPublishedQueryEnvironment | undefined): Result<ClientSourcePreparation>;
  export function clientValuesHostPrepareTaskDispatch(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, request: ClientRequestIdentity,
    task: number, taskAttempt: number, dispatchId: string, siteKey: string, siteGeneration: number,
    runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string): Result<DispatchRequest>;
  export function clientValuesHostPrepareTaskDispatchWithSource(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, request: ClientRequestIdentity,
    task: number, taskAttempt: number, dispatchId: string, siteKey: string, siteGeneration: number,
    runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string, source: ClientSourcePreparation): Result<DispatchRequest>;
  export function clientValuesHostProgramPreparationEffect(
    value: ClientValuesHostProgramPreparation): PreparedClientEffectComputation | undefined;
  export function clientValuesHostProgramPreparationEffectFree(
    value: ClientValuesHostProgramPreparation): PreparedClientProgram | undefined;
  export function clientValuesHostProgramPreparationKind(value: ClientValuesHostProgramPreparation): string;
  export function clientValuesHostProjectCommittedResultReadWire(
    index: PublicationContract, manifest: PublicationContract, resultName: string,
    bindings: readonly PublicationContract[]): string | undefined;
  export function clientValuesHostProjectEffectTaskRun(
    progress: ClientRemoteEffectTaskProgress, observedAt: string, cancellationRequested: boolean,
    taskKeys: readonly string[], dispatchCids: readonly string[], reserved: readonly boolean[],
    physicallyClaimed: readonly boolean[]): Result<ClientRemoteEffectTaskRunProjection>;
  export function clientValuesHostProjectPublicationSnapshot(
    record: PublicationContract | undefined, indexMode: number, index: PublicationContract | undefined): Result<string[]>;
  export function clientValuesHostProjectRemoteTaskRun(
    progress: ClientRemoteTaskProgress, observedAt: string, cancellationRequested: boolean,
    claimedTaskKeys: readonly string[]): Result<ClientRemoteTaskRunProjection>;
  export function clientValuesHostProjectSiteRun(
    definition: PublicationContract, compilation: ClientValuesCompilation, authority: string,
    durableWire: string, observedAt: string, cancellationRequested: boolean,
    physicalStartClaimed: boolean): Result<string[]>;
  export function clientValuesHostProjectTaskSiteRun(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, authority: string,
    durableWire: string, observedAt: string, cancellationRequested: boolean,
    physicalStartClaimed: boolean): Result<string[]>;
  export function clientValuesHostPublicationContractIdentity(contract: PublicationContract): string;
  export function clientValuesHostPublicationContractIdentityField(contract: PublicationContract): string;
  export function clientValuesHostPublicationContractName(contract: PublicationContract): string;
  export function clientValuesHostPublicationContractWire(contract: PublicationContract): string;
  export function clientValuesHostPublicationIndexScopeKey(
    namespaceId: string, authorityScopeCid: string, runDefinitionCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): Result<string>;
  export function clientValuesHostRecordResultAccessGrant(
    progress: ResultAccessProgress, issued: boolean): boolean;
  export function clientValuesHostRecordResultAccessInitialAvailability(
    progress: ResultAccessProgress, available: boolean): boolean;
  export function clientValuesHostRecordResultAccessReadAdmission(
    progress: ResultAccessProgress, admitted: boolean): boolean;
  export function clientValuesHostRecordResultAccessRequestAuthorization(
    progress: ResultAccessProgress, authorized: boolean): boolean;
  export function clientValuesHostRecordResultAccessResolution(
    progress: ResultAccessProgress, resolved: boolean): boolean;
  export function clientValuesHostRemoteTaskRunFields(value: ClientRemoteTaskRunProjection): string[];
  export function clientValuesHostRemoteTaskRunWork(value: ClientRemoteTaskRunProjection): string[];
  export function clientValuesHostRequestAuthorityScopeCid(identity: ClientRequestIdentity): string;
  export function clientValuesHostRequestCallerId(identity: ClientRequestIdentity): string;
  export function clientValuesHostRequestIdentity(
    prepared: PreparedClientProgram, authorityScopeCid: string, callerRequestId: string,
    callerInputIntentCid: string): Result<ClientRequestIdentity>;
  export function clientValuesHostRequestInputCid(identity: ClientRequestIdentity): string;
  export function clientValuesHostRequestIntentCid(identity: ClientRequestIdentity): string;
  export function clientValuesHostRequestParametersCid(identity: ClientRequestIdentity): string;
  export function clientValuesHostRequestProgramCid(identity: ClientRequestIdentity): string;
  export function clientValuesHostRequestRelation(
    requested: ClientRequestIdentity, retained: ClientRequestIdentity): number;
  export function clientValuesHostRequestScopeCid(identity: ClientRequestIdentity): string;
  export function clientValuesHostRestoreEffectRunNormalization(
    materials: ClientEffectRunMaterials): Result<RunEvidenceValue>;
  export function clientValuesHostRestoredEffectAllowed(
    restored: ClientEffectRunMaterials): ClientEffectAllowedRun;
  export function clientValuesHostRestoredEffectCompilation(
    restored: ClientEffectRunMaterials): ClientEffectCompilation;
  export function clientValuesHostRestoredEffectDefinition(
    restored: ClientEffectRunMaterials): PublicationContract;
  export function clientValuesHostRestoredEffectPrepared(
    restored: ClientEffectRunMaterials): PreparedClientEffectComputation;
  export function clientValuesHostRestoredEffectRequest(
    restored: ClientEffectRunMaterials): ClientRequestIdentity[];
  export function clientValuesHostResultAccessProgressAction(progress: ResultAccessProgress): number;
  export function clientValuesHostResultDefinitions(
    prepared: PreparedClientProgram, compilation: ClientValuesCompilation): Result<string[]>;
  export function clientValuesHostResultMaterialHoldsBinding(value: ResultMaterialHolds): string;
  export function clientValuesHostResultMaterialHoldsGeneration(value: ResultMaterialHolds): string;
  export function clientValuesHostResultMaterialHoldsReclaimable(value: ResultMaterialHolds): boolean;
  export function clientValuesHostResultMaterialHoldsRevision(value: ResultMaterialHolds): number;
  export function clientValuesHostResultMaterialHoldsWire(value: ResultMaterialHolds): Result<string>;
  export function clientValuesHostResultMetadataRetentionState(
    retention: PublicationContract, observedAt: string): string | undefined;
  export function clientValuesHostResultNames(value: ClientValuesCompilation): string[];
  export function clientValuesHostResultOccurrenceDerivation(
    evidence: ResultOrderingEvidence): PublicationContract;
  export function clientValuesHostResultOccurrenceOrdering(evidence: ResultOrderingEvidence): PublicationContract;
  export function clientValuesHostResultReadAvailability(
    manifest: PublicationContract, resultName: string, retention: PublicationContract,
    observedAt: string): Result<string>;
  export function clientValuesHostResultReadDefinitionCid(
    manifest: PublicationContract, resultName: string): Result<string>;
  export function clientValuesHostResultReadExtendedAvailability(
    manifest: PublicationContract, resultName: string, base: PublicationContract,
    extension: PublicationContract, observedAt: string): Result<string>;
  export function clientValuesHostResultReadGrantAllowsBytes(
    grant: PublicationContract, byteCount: number): boolean;
  export function clientValuesHostResultReadGrantValidAt(grant: PublicationContract, observedAt: string): boolean;
  export function clientValuesHostResultReadRetentionPolicyCid(
    manifest: PublicationContract, resultName: string): Result<string>;
  export function clientValuesHostResultRetentionClockContractCid(retention: PublicationContract): Result<string>;
  export function clientValuesHostResultSchema(prepared: PreparedClientProgram): Result<string[]>;
  export function clientValuesHostRetainedInputCurrentEnvelope(
    query: ClientValuesHostRetainedInputQuery): Result<string>;
  export function clientValuesHostRetainedInputCurrentReplyFacts(
    reply: RemoteRetainedCurrentReply): Result<string[]>;
  export function clientValuesHostRetainedInputEdge(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation,
    admission: RunPublicationAdmission, definition: PublicationContract, consumerTask: number,
    inputIndex: number): Result<ClientRetainedInputEdge>;
  export function clientValuesHostRetainedInputEdgeFacts(edge: ClientRetainedInputEdge): string[];
  export function clientValuesHostRetainedInputIntentFacts(intent: RemoteRetainedInputIntent): string[];
  export function clientValuesHostRetainedInputPlanEnvelope(
    producer: ClientRetainedInputProducer, intent: RemoteRetainedInputIntent): Result<string>;
  export function clientValuesHostRetainedInputPlanFacts(
    value: ClientValuesHostRetainedInputPlan): Result<string[]>;
  export function clientValuesHostRetainedInputProducer(
    edge: ClientRetainedInputEdge, readCurrent: () => string[]): Result<ClientRetainedInputProducer>;
  export function clientValuesHostRetainedInputProducerAvailable(producer: ClientRetainedInputProducer): boolean;
  export function clientValuesHostRetainedInputProducerFacts(
    producer: ClientRetainedInputProducer): Result<string[]>;
  export function clientValuesHostRetainedInputResultFacts(value: RemoteRetainedInputResult): Result<string[]>;
  export function clientValuesHostRetainedInputTransferEnvelope(
    value: ClientValuesHostRetainedInputPlan): Result<string>;
  export function clientValuesHostRetainedTaskInputFacts(value: ClientValuesHostRetainedTaskInput): string[];
  export function clientValuesHostRunControlObservation(
    revision: number, requested: boolean, unstarted: boolean, stopped: boolean): Result<string>;
  export function clientValuesHostRunDefinitionCid(definition: PublicationContract): string;
  export function clientValuesHostRunDefinitionWire(definition: PublicationContract): string;
  export function clientValuesHostRunEvidenceValueIdentity(value: RunEvidenceValue): string;
  export function clientValuesHostRunEvidenceValueWire(value: RunEvidenceValue): string;
  export function clientValuesHostSealRunEvidenceValue(
    name: string, bodyWire: string, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<RunEvidenceValue>;
  export function clientValuesHostSourceEvidenceFacts(
    prepared: PreparedClientProgram, stage: number, sourceIndex: number): BoxedOption<string[]>;
  export function clientValuesHostSourceFreeRequestIdentity(
    prepared: PreparedClientProgram, authorityScopeCid: string, callerRequestId: string): Result<ClientRequestIdentity>;
  export function clientValuesHostSourceProgramDeclarations(value: ClientSourcePreparation): string | undefined;
  export function clientValuesHostSourceProgramDocument(value: ClientSourcePreparation): string;
  export function clientValuesHostSourceProgramEffect(
    value: ClientSourcePreparation): PreparedClientEffectComputation | undefined;
  export function clientValuesHostSourceProgramInput(value: ClientSourcePreparation): string[];
  export function clientValuesHostSourceProgramKind(value: ClientSourcePreparation): string;
  export function clientValuesHostSourceProgramOriginals(value: ClientSourcePreparation): string[];
  export function clientValuesHostSourceProgramParameters(value: ClientSourcePreparation): string | undefined;
  export function clientValuesHostSourceProgramPure(
    value: ClientSourcePreparation): PreparedClientProgram | undefined;
  export function clientValuesHostSourceProgramRequest(
    value: ClientSourcePreparation, intent: ClientSubmittedIntent, environment: CheckEnvironment,
    authorityScopeCid: string, requestId: string): Result<ClientRequestIdentity>;
  export function clientValuesHostSubmissionEpoch(
    authorityScopeCid: string, epochNonce: string, notBefore: number, expiresAt: number): SubmissionEpoch | undefined;
  export function clientValuesHostSubmissionEpochCid(epoch: SubmissionEpoch): string;
  export function clientValuesHostSubmissionEpochValidity(epoch: SubmissionEpoch, now: number): string | undefined;
  export function clientValuesHostSubmissionEpochWire(epoch: SubmissionEpoch): string;
  export function clientValuesHostSubmissionRequestId(
    epoch: SubmissionEpoch, callerNonce: string): string | undefined;
  export function clientValuesHostSubmittedIntent(
    wire: string, maxBytes: number, maxNodes: number, maxDepth: number): ClientSubmittedIntent | undefined;
  export function clientValuesHostSubmittedIntentCid(value: ClientSubmittedIntent): string;
  export function clientValuesHostSubmittedIntentTransition(before: string, after: string): boolean;
  export function clientValuesHostSubmittedIntentWire(value: ClientSubmittedIntent): string;
  export function clientValuesHostTaskCompiledPlanWire(value: ClientTaskCompilation): string;
  export function clientValuesHostTaskExecutionShape(prepared: PreparedClientProgram): number[];
  export function clientValuesHostTaskFactManifestWire(value: ClientTaskCompilation): string;
  export function clientValuesHostTaskInputBinding(prepared: PreparedClientProgram, task: number): Result<string>;
  export function clientValuesHostTaskKeys(prepared: PreparedClientProgram): Result<string[]>;
  export function clientValuesHostTaskPlanWire(value: ClientTaskCompilation): string;
  export function clientValuesHostTaskProgressCleanupComplete(value: ClientRemoteTaskProgress): boolean;
  export function clientValuesHostTaskProgressExecutionComplete(value: ClientRemoteTaskProgress): boolean;
  export function clientValuesHostTaskProgressFields(value: ClientRemoteTaskProgress): string[][];
  export function clientValuesHostTaskProgressNext(value: ClientRemoteTaskProgress): number;
  export function clientValuesHostTaskProgressResultTasks(value: ClientRemoteTaskProgress): number[];
  export function clientValuesHostTaskProgressScopes(value: ClientRemoteTaskProgress): string[][];
  export function clientValuesHostTaskResultDefinitions(
    prepared: PreparedClientProgram, compilation: ClientTaskCompilation): Result<string[]>;
  export function clientValuesHostTaskResultNames(value: ClientTaskCompilation): string[];
  export function clientValuesHostTaskResultSchema(
    prepared: PreparedClientProgram, result: number): Result<string[]>;
  export function clientValuesHostTaskTemplateWire(value: ClientTaskCompilation): string;
  export function clientValuesHostTemplateWire(value: ClientValuesCompilation): string;
  export function clientValuesHostTrustedClockNotBefore(previous: string | undefined, observedAt: string): boolean;
  export function clientValuesHostValidateEffectFreePublicationCommit(
    runDefinition: PublicationContract, invocation: PublicationContract,
    definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[],
    derivations: readonly PublicationContract[], orderings: readonly PublicationContract[],
    retentions: readonly PublicationContract[], bindings: readonly PublicationContract[],
    manifest: PublicationContract, receipt: PublicationContract, capturedRun: PublicationContract,
    request: PublicationContract, attempt: PublicationContract, indexEntry: PublicationContract,
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<void>;
  export function clientValuesHostValidateEffectfulPublicationCommit(
    runDefinition: PublicationContract, invocation: PublicationContract,
    definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[],
    derivations: readonly PublicationContract[], orderings: readonly PublicationContract[],
    retentions: readonly PublicationContract[], bindings: readonly PublicationContract[],
    manifest: PublicationContract, computationReceipt: PublicationContract,
    capturedRun: PublicationContract, preview: EffectPreviewIdentity, setReceiptWire: string,
    memberReceiptWires: readonly string[], finalReceipt: PublicationContract,
    request: PublicationContract, attempt: PublicationContract, indexEntry: PublicationContract,
    maxWireBytes: number, maxNodes: number, maxDepth: number): Result<void>;
  export function clientValuesHostValidatePublicationChain(
    runDefinition: PublicationContract, invocation: PublicationContract,
    definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[],
    manifest: PublicationContract, maxWireBytes: number, maxNodes: number, maxDepth: number): Result<void>;
  export function clientValuesHostValidatePublicationRecordTransition(
    previous: PublicationContract | undefined, next: PublicationContract, uncommittedConfirmed: boolean): Result<void>;
  export function clientValuesHostValidateRetainedEffectfulPublicationCommit(
    value: EffectfulFinalRunEvidence, bindings: readonly PublicationContract[],
    request: PublicationContract, attempt: PublicationContract, indexEntry: PublicationContract): Result<PublicationContract>;
  export function clientValuesHostValidateRetainedInputPlan(
    value: ClientValuesHostRetainedInputPlan): Result<void>;
  export function clientValuesHostValidateRetainedTaskInput(
    value: ClientValuesHostRetainedTaskInput): Result<void>;
}
