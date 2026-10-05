declare const environmentBrand: unique symbol;
declare const preparedBrand: unique symbol;
declare const compilationBrand: unique symbol;
declare const taskCompilationBrand: unique symbol;
declare const requestBrand: unique symbol;
declare const admissionBrand: unique symbol;
declare const definitionBrand: unique symbol;
declare const publicationBrand: unique symbol;
declare const deliveryContractBrand: unique symbol;
declare const resultOccurrenceBrand: unique symbol;
declare const runEvidenceBrand: unique symbol;
declare const capturedSnapshotBrand: unique symbol;
declare const materialHoldsBrand: unique symbol;
declare const retainedInputEdgeBrand: unique symbol;
declare const retainedInputProducerBrand: unique symbol;
declare const retainedInputIntentBrand: unique symbol;
declare const retainedInputPlanBrand: unique symbol;
declare const retainedInputResultBrand: unique symbol;
declare const retainedTaskInputBrand: unique symbol;

export interface ResultMaterialHolds {
  readonly [materialHoldsBrand]: true;
}

/** An in-process owner value; only the canonical wire is durable. */
export function beginResultMaterialHolds(bindingCid: string,
  materialGenerationCid: string): ResultMaterialHolds;
export function admitResultMaterialHolds(wire: string): ResultMaterialHolds;
export function resultMaterialHoldsWire(value: ResultMaterialHolds): string;
export function resultMaterialHoldsFacts(value: ResultMaterialHolds):
  Readonly<{bindingCid: string; materialGenerationCid: string;
    revision: number; reclaimable: boolean}>;
export function prepareResultMaterialHoldsStep(value: ResultMaterialHolds,
  operation: 'add_consumer' | 'release_consumer' | 'begin_reader' |
    'end_reader' | 'stop_readers', identity: string): ResultMaterialHolds;

export interface CheckEnvironment {
  readonly [environmentBrand]: true;
}

export interface PreparedProgram {
  readonly [preparedBrand]: true;
}

export interface ValuesCompilation {
  readonly [compilationBrand]: true;
}

export interface TaskCompilation {
  readonly [taskCompilationBrand]: true;
}

/** Count physical checked tasks separately from Result Plan transformations. */
export function taskExecutionShape(prepared: PreparedProgram,
  compilation: TaskCompilation): Readonly<{taskCount: number; acquisitionCount: number}>;

export interface RequestIdentity {
  readonly [requestBrand]: true;
}

export interface RunAdmission {
  readonly [admissionBrand]: true;
}

export interface RunDefinition {
  readonly [definitionBrand]: true;
}

export interface PublicationContract<Kind extends string = string> {
  readonly token: {readonly [publicationBrand]: Kind};
  readonly cid: string;
  readonly wire: string;
}

export type PublicationRequestContract =
  PublicationContract<'publication_request'>;
export type PublicationAttemptContract =
  PublicationContract<'publication_attempt'>;
export type PublicationRecordContract =
  PublicationContract<'publication_record'>;
export type PublicIndexEntryContract =
  PublicationContract<'public_index_entry'>;

export interface DeliveryContractView<Kind extends string = string> {
  readonly [deliveryContractBrand]: Kind;
  readonly name: Kind;
  readonly identityField: string;
  readonly identity: string;
  readonly wire: string;
}

type IndexView = DeliveryContractView<'public_index_entry'>;
type ManifestView = DeliveryContractView<'result_manifest'>;
type RetentionView = DeliveryContractView<'result_retention_policy'>;
type ExtensionView = RetentionView;
type GrantView = DeliveryContractView<'result_read_grant'>;
type AttemptView = DeliveryContractView<'delivery_attempt'>;
type ReceiptView = DeliveryContractView<'result_delivery_receipt'>;
type RecordView = DeliveryContractView<'delivery_record'>;

declare const resultAccessBrand: unique symbol;
declare const resultSerializerBrand: unique symbol;
export interface ResultAccessProgress {
  readonly [resultAccessBrand]: true;
}
export interface ResultDeliverySerializer {
  readonly [resultSerializerBrand]: true;
}
declare const durableRowFramesBrand: unique symbol;
export interface DurableResultRowFrames {
  readonly [durableRowFramesBrand]: true;
}

export interface ResultDeliveryControl {
  describeCommittedResult(index: IndexView, manifest: ManifestView,
    resultName: string, bindings: readonly DeliveryContractView<string>[],
    definition: DeliveryContractView<string>, schemaWire: string,
    format: string, limits: PublicationLimits):
    Omit<import('@actql/client-wire').WireResultDescription, 'ref'>;
  resultMetadataRetentionState(retention: RetentionView,
    observedAt: string): 'retained' | 'delete_due';
  issueManifestReadGrant(index: IndexView, manifest: ManifestView,
    grant: Readonly<{principalId: string; purpose: string;
      dataCeilingCid: string; maxBytes: number; maxUses: number;
      expiresAt: string; authorizationContextCid: string}>,
    limits: PublicationLimits): DeliveryContractView<'manifest_read_grant'>;
  manifestReadGrantValidAt(grant: DeliveryContractView<'manifest_read_grant'>,
    at: string): boolean;
  manifestReadGrantAllowsBytes(grant: DeliveryContractView<'manifest_read_grant'>,
    bytes: number): boolean;
  admit<Kind extends string>(name: Kind, wire: string,
    limits: PublicationLimits): DeliveryContractView<Kind>;
  beginResultAccessProgress(): ResultAccessProgress;
  resultAccessProgressAction(progress: ResultAccessProgress):
    'authorize_request' | 'resolve_committed_result' |
    'check_initial_availability' | 'admit_read' | 'issue_grant' |
    'start_delivery' | 'reject';
  recordResultAccessRequestAuthorization(progress: ResultAccessProgress,
    value: boolean): boolean;
  recordResultAccessResolution(progress: ResultAccessProgress,
    value: boolean): boolean;
  recordResultAccessInitialAvailability(progress: ResultAccessProgress,
    value: boolean): boolean;
  recordResultAccessReadAdmission(progress: ResultAccessProgress,
    value: boolean): boolean;
  recordResultAccessGrant(progress: ResultAccessProgress,
    value: boolean): boolean;
  resultReadRetentionPolicyCid(manifest: ManifestView,
    resultName: string): string;
  resultReadDefinitionCid(manifest: ManifestView,
    resultName: string): string;
  resultReadAvailability(manifest: ManifestView,
    resultName: string, retention: RetentionView,
    observedAt: string): string;
  resultReadExtendedAvailability(manifest: ManifestView,
    resultName: string, retention: RetentionView,
    extension: ExtensionView, observedAt: string): string;
  resultRetentionClockContractCid(retention: RetentionView): string;
  issueResultReadGrant(index: IndexView,
    manifest: ManifestView, grant: Readonly<{
      resultNames: readonly string[]; formats: readonly string[];
      principalId: string; purpose: string; dataCeilingCid: string;
      maxBytes: number; maxUses: number; expiresAt: string;
      authorizationContextCid: string; egressAdmissionCid: string;
    }>, limits: PublicationLimits): GrantView;
  resultReadGrantValidAt(grant: GrantView,
    observedAt: string): boolean;
  resultReadGrantAllowsBytes(grant: GrantView,
    count: number): boolean;
  issueDeliveryAttempt(index: IndexView,
    manifest: ManifestView, grant: GrantView,
    attempt: Readonly<{resultName: string; format: string;
      attemptId: string; requestedAt: string}>,
    limits: PublicationLimits): AttemptView;
  deliveryResultDefinitionCid(manifest: ManifestView,
    attempt: AttemptView): string;
  issueResultDeliveryReceipt(index: IndexView,
    manifest: ManifestView, grant: GrantView,
    attempt: AttemptView,
    delivered: Readonly<{byteCount: number; sha256: string}>,
    limits: PublicationLimits): ReceiptView;
  issueDeliveryRecord(attempt: AttemptView,
    previous: RecordView | undefined,
    update: Readonly<{state: string; confirmedByteCount: number;
      exposure: string; possibleUnconfirmedMaxBytes?: number;
      deliveredSha256?: string; receipt?: ReceiptView;
      failureCid?: string; observedAt: string;
      cleanupOwnerCids: readonly string[]}>,
    limits: PublicationLimits): RecordView;
  existingDeliveryAttemptAction(record?: RecordView):
    'confirm_succeeded_record' | 'reject_unresolved_attempt' |
    'reject_terminal_attempt' | 'invalid';
  deliveryFailureTerminalAction(observed: boolean): 'failed' | 'cancelled';
  deliveryRecordRetryAction(next: number, count: number):
    'append_next_record' | 'finished' | 'invalid';
  deliveryTransition(previous: RecordView | undefined,
    next: RecordView): boolean;
  deliverySuccessValid(attempt: AttemptView,
    receipt: ReceiptView, record: RecordView): boolean;
  trustedClockNotBefore(previous: string | undefined,
    observedAt: string): boolean;
  prepareDeliveryGrantUsageClaim(grant: GrantView,
    existingWire: string | undefined, attempt: AttemptView,
    limits: PublicationLimits): Readonly<{
      wire: string; newlyClaimed: boolean;
    }>;
  prepareDurableResultRowFrames(bounds: Readonly<{
    maxBytes: number; maxRows: number; maxRowBytes: number;
    maxDepth: number; maxFrameBytes: number;
  }>): DurableResultRowFrames;
  feedDurableResultRowFrames(frames: DurableResultRowFrames,
    chunk: Uint8Array): readonly string[];
  finishDurableResultRowFrames(frames: DurableResultRowFrames):
    Readonly<{bytes: number; rows: number}>;
  cancelDurableResultRowFrames(frames: DurableResultRowFrames): void;
  prepareResultDeliverySerializer(format: string, schemaWire: string,
    fields: readonly string[], limits: PublicationLimits):
    ResultDeliverySerializer;
  beginResultDelivery(serializer: ResultDeliverySerializer): string;
  nextResultDeliveryRow(serializer: ResultDeliverySerializer,
    rowWire: string): string;
  finishResultDelivery(serializer: ResultDeliverySerializer): string;
}

/** MoonBit delivery decisions; Host policy and physical I/O are separate. */
export function openResultDeliveryControl(): ResultDeliveryControl;

export type PublicationIndexObservation =
  | Readonly<{kind: 'absent'}>
  | Readonly<{kind: 'unknown'}>
  | Readonly<{kind: 'committed'; entry: PublicationContract}>;

/** Projection only; the caller proves the latest record and index query. */
export function projectPublicationSnapshot(
  record: PublicationContract | undefined,
  index: PublicationIndexObservation): Readonly<{
    state: 'not_started' | 'preparing' | 'committing' |
      'publication_unknown' | 'succeeded' | 'failed' | 'cancelled';
    evidenceCid: string | undefined;
  }>;

/** Shared Store key; the key alone grants no read or publication access. */
export function publicationIndexScopeKey(ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>, limits: PublicationLimits): string;

export interface RunEvidence {
  readonly token: {readonly [runEvidenceBrand]: true};
  readonly cid: string;
  readonly wire: string;
}

export interface CapturedResultSnapshot {
  readonly token: {readonly [capturedSnapshotBrand]: true};
}

export interface PublicationLimits {
  readonly maxWireBytes: number;
  readonly maxNodes: number;
  readonly maxDepth: number;
}

export interface ResultOccurrenceEvidence {
  readonly token: {readonly [resultOccurrenceBrand]: true};
  readonly derivation: PublicationContract;
  readonly ordering: PublicationContract;
}

export interface RequestFields {
  readonly authorityScopeCid: string;
  readonly requestId: string;
  readonly logicalRequestScopeCid: string;
  readonly intentFingerprintCid: string;
  readonly programDefinitionCid: string;
  readonly parameterValuesCid: string;
  readonly callerInputIntentCid: string;
}

export interface ProfileSelection {
  readonly textTime?: boolean;
  readonly veca?: boolean;
  readonly rela?: boolean;
  readonly sga?: boolean;
  readonly tea?: boolean;
  readonly calendar?: boolean;
  readonly textRank?: boolean;
}

/** Validate the closed profile selection contract and normalize omitted values
 * to false. Returns a detached frozen value suitable for retained Run input;
 * it does not admit a Check Environment or grant execution authority. */
export function admitProfileSelection(profiles: unknown):
  Readonly<Required<ProfileSelection>>;

export interface PrivateCompilationWires {
  readonly executablePlan: string;
  readonly factManifest: string;
  readonly boundTemplate: string;
  readonly compiledPlan: string;
}

export function admitEnvironment(body: string, evidenceBundleCid: string,
  profiles: ProfileSelection): CheckEnvironment;
export function prepare(document: string, format: 'json' | 'yaml',
  environment: CheckEnvironment, parametersWire?: string): PreparedProgram;
export function compileValues(prepared: PreparedProgram): ValuesCompilation;
export function compileTasks(prepared: PreparedProgram): TaskCompilation;
export function privateTaskCompilationWires(
  compilation: TaskCompilation): PrivateCompilationWires;
export function taskResultNames(compilation: TaskCompilation): readonly string[];
/** Exact dispatch keys from checked fragments, excluding Result transforms. */
export function taskKeys(prepared: PreparedProgram, compilation: TaskCompilation): readonly string[];
export function taskResultDefinitions(prepared: PreparedProgram,
  compilation: TaskCompilation): readonly Readonly<{
  name: string;
  cid: string;
  wire: string;
}>[];
export function privateCompilationWires(
  compilation: ValuesCompilation): PrivateCompilationWires;
/** Exact identity of the checked Compiled Plan, not publication authority. */
export function compiledPlanCid(compilation: ValuesCompilation): string;
export function executionShape(compilation: ValuesCompilation): Readonly<{
  planNodeId: string;
  outputContractCid: string;
  resultNames: readonly string[];
}>;
/** Complete checked inventory; these identities are not read grants. */
export function resultDefinitions(prepared: PreparedProgram,
  compilation: ValuesCompilation): readonly Readonly<{
  name: string;
  cid: string;
  wire: string;
}>[];
/** Checked output schema for this Values compilation, not a read grant. */
export function resultSchema(prepared: PreparedProgram,
  compilation: ValuesCompilation): Readonly<{
    cid: string;
    wire: string;
    fields: readonly string[];
  }>;
export function taskResultSchema(prepared: PreparedProgram,
  compilation: TaskCompilation, resultName: string): Readonly<{
    cid: string;
    wire: string;
    fields: readonly string[];
  }>;
// The Host establishes authority scope and admitted input intent. An identity
// handle or its fields do not grant Run access or permission to dispatch.
export function prepareRequest(prepared: PreparedProgram,
  authorityScopeCid: string, requestId: string,
  admittedInputIntentCid: string): RequestIdentity;
export function prepareSourceFreeRequest(prepared: PreparedProgram,
  compilation: ValuesCompilation, authorityScopeCid: string,
  requestId: string): RequestIdentity;
export function requestFields(request: RequestIdentity): RequestFields;
export function admitRequestFields(fields: RequestFields): RequestIdentity;
export function admitSourceFreeRequestFields(prepared: PreparedProgram,
  compilation: ValuesCompilation, fields: RequestFields): RequestIdentity;
export function requestRelation(requested: RequestIdentity,
  retained: RequestIdentity): 'different_request' | 'same_request' |
    'changed_intent';
// Current Host policy and authorization evidence must be issued by the Host.
// This operation only checks their binding to the compiled Program.
export function admitRun(prepared: PreparedProgram,
  compilation: ValuesCompilation, preparedInvocationWire: string,
  authorizationWire: string): RunAdmission;
// Call only after the Host has made its current authorization decision.
export function issueAllowedRun(prepared: PreparedProgram,
  compilation: ValuesCompilation, policy: Readonly<{
    executionContextCid: string;
    hostPolicyCid: string;
    expiresAt: string;
  }>): Readonly<{
    admission: RunAdmission;
    preparedInvocationWire: string;
    authorizationWire: string;
  }>;
export function issueAllowedTaskRun(prepared: PreparedProgram,
  compilation: TaskCompilation, policy: Readonly<{
    executionContextCid: string;
    hostPolicyCid: string;
    expiresAt: string;
  }>): Readonly<{
    admission: RunAdmission;
    preparedInvocationWire: string;
    authorizationWire: string;
  }>;
export function admitTaskRun(prepared: PreparedProgram,
  compilation: TaskCompilation, preparedInvocationWire: string,
  authorizationWire: string): RunAdmission;
export function issueRunDefinition(admission: RunAdmission, scopeId: string,
  runId: string, inputArtifactSetCid: string, createdAt: string,
  validUntil: string): RunDefinition;
/** Bind zero captured Run-start inputs to the checked source-free Program. */
export function issueSourceFreeRunDefinition(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission, scopeId: string,
  runId: string, createdAt: string, validUntil: string): RunDefinition;
export function issueTaskRunDefinition(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission, scopeId: string,
  runId: string, createdAt: string, validUntil: string): RunDefinition;
export function admitTaskRunDefinition(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  wire: string): RunDefinition;
export function privateRunDefinition(definition: RunDefinition): Readonly<{
  wire: string;
  cid: string;
}>;
/** Project the owner's unpublished Run state from retained physical facts. */
export function issueUnpublishedRunStateWire(prepared: PreparedProgram,
  compilation: ValuesCompilation | TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, observedAt: string,
  observation: Readonly<{dispatchReserved: boolean;
    preDispatchFailureConfirmed: boolean; cancelledBeforeStart?: boolean;
    executionUnknown?: boolean}>): string;
/** Project a committed Run with current physical availability observations. */
export function issueSucceededRunStateWire(prepared: PreparedProgram,
  compilation: ValuesCompilation | TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, observedAt: string,
  observations: readonly Readonly<{name: string;
    state: 'available' | 'unavailable' | 'unknown';
    reason: 'confirmed_present' | 'retention_expired' | 'deleted' |
      'policy_unavailable' | 'integrity_failed' | 'not_published' |
      'store_query_failed' | 'clock_uncertain' | 'verification_pending';
    observedAt: string}>[]): string;
/** Admission of the current clock against the pinned Result retention. */
export function resultReadAvailability(manifest: PublicationContract,
  resultName: string, retention: PublicationContract,
  observedAt: string): 'available' | 'retention_expired' | 'delete_due';
export function describeCommittedResult(index: PublicationContract,
  manifest: PublicationContract, resultName: string,
  bindings: readonly PublicationContract[], definition: PublicationContract,
  schemaWire: string, format: string, limits: PublicationLimits):
  Omit<import('@actql/client-wire').WireResultDescription, 'ref'>;
/** Select one committed Result and validate the complete binding inventory. */
export function projectCommittedResultRead(index: PublicationContract,
  manifest: PublicationContract, resultName: string,
  bindings: readonly PublicationContract[]): Readonly<{
    resultName: string;
    resultArtifactCid: string;
    resultDefinitionCid: string;
    logicalResultCid: string;
    resultSchemaCid: string;
    orderingEvidenceCid: string;
    effectiveRetentionPolicyCid: string;
    durableResultBindingCid: string;
    materialGenerationCid: string;
    storeAuthorityCid: string;
    codecContractCid: string;
    resultFields: readonly string[];
    rowCount: number;
    byteCount: number;
    physicalSha256: string;
  }>;
export function admitRunDefinition(wire: string): RunDefinition;
/** Re-admit the same checked source-free Run without changing its input set. */
export function admitSourceFreeRunDefinition(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission,
  wire: string): RunDefinition;
/** Original JSON input retained alongside a Run; not new authority. */
export interface SourceFreeRunMaterialsInput {
  readonly document: string;
  readonly format: 'json';
  readonly environment: CheckEnvironment;
  readonly environmentWire: string;
  readonly parametersWire?: string;
}
/** Projects the existing Run and evidence. Does not compile, authorize or
 * extend expiry. The encoded body is bounded to 262144 UTF-8 bytes. */
export function issueSourceFreeRunMaterials(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission,
  definition: RunDefinition, retained: SourceFreeRunMaterialsInput): string;

/** Projects an original checked task Run through the common materials owner.
 * Physical Source paths and connection configuration remain Site-owned. */
export function issueTaskRunMaterials(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, retained: SourceFreeRunMaterialsInput): string;

export function prepareRunStart(requested: RequestIdentity,
  retained: RequestIdentity, definition: RunDefinition,
  retainedRunDefinitionCid: string, dispatchReserved: boolean,
  currentAuthorization: boolean): 'reserve_dispatch' |
  'reconcile_reserved_dispatch';
export function checkRunBinding(prepared: PreparedProgram,
  admission: RunAdmission, definition: RunDefinition): void;
/** Host policy selects the data policy before source-free observation. */
export function issueSourceFreeInvocation(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission,
  definition: RunDefinition, dataPolicyCid: string,
  limits: PublicationLimits): Readonly<{
    observation: RunEvidence;
    invocation: PublicationContract;
  }>;
/** Source-free Observation Set for a checked multi-task compilation. */
export function issueSourceFreeTaskInvocation(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, dataPolicyCid: string,
  limits: PublicationLimits): Readonly<{
    observation: RunEvidence;
    invocation: PublicationContract;
  }>;
/** Bind observed source evidence to a completed captured input and scope. */
export function admitCompletedSourceObservation(facts: Readonly<{
  sourceEvidenceWire: string;
  inputLogicalWire: string;
  sourceRef: string;
  sourceContractCid: string;
  authorityScopeCid: string;
  effectiveDataPolicyCid: string;
  limits: PublicationLimits;
}>): string;
/** Issue a task Invocation after one completed source capture is admitted. */
export function issueTaskInvocation(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, source: Readonly<{
    sourceEvidenceWire: string;
    inputLogicalWire: string;
    sourceRef: string;
    sourceContractCid: string;
    authorityScopeCid: string;
    dataPolicyCid: string;
    captureStartedAt: string;
    captureCompletedAt: string;
  }>, limits: PublicationLimits): Readonly<{
    observation: RunEvidence;
    invocation: PublicationContract;
  }>;
export interface ValuesSiteSelection {
  readonly taskAttempt: number;
  readonly dispatchId: string;
  readonly siteKey: string;
  readonly siteGeneration: number;
  readonly runtimeBundleCid: string;
  readonly connectorRegistration: string;
  readonly connectorRevision: string;
  readonly strategyRevision: string;
  readonly obligationsCid: string;
  readonly budgetCid: string;
  readonly evidenceIssuerCapabilityCid: string;
  readonly grantCid: string;
}
/** Call only after current Host authorization and Site selection. */
export function issueSourceFreeDispatch(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission,
  definition: RunDefinition, request: RequestIdentity,
  selection: ValuesSiteSelection): Readonly<{cid: string; wire: string}>;
/** No caller-supplied Run-start Artifact; later Source capture remains separate. */
export function prepareTaskRequest(prepared: PreparedProgram,
  compilation: TaskCompilation, authorityScopeCid: string,
  requestId: string): RequestIdentity;
/** Original checked Catalog facts; these do not grant acquisition I/O. */
export function sourceEvidenceFacts(prepared: PreparedProgram, stage: number,
  sourceIndex: number): Readonly<{sourceRef: string; sourceContractCid: string;
    carrierSchemaContractCid: string; sourceDataPolicyCid: string;
    dataClassification: string; sourceViewContractCid: string}> | undefined;
/** Checked logical input only, with no Site path or connection settings. */
export function taskInputBinding(prepared: PreparedProgram, task: number): string;
/** A checked edge, not producer completion, physical custody or permission. */
export interface RetainedTaskInputEdge {
  readonly [retainedInputEdgeBrand]: true;
}
export function prepareRetainedTaskInputEdge(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, consumerTask: number,
  inputIndex: number): RetainedTaskInputEdge;
export function retainedTaskInputEdgeFacts(edge: RetainedTaskInputEdge): Readonly<{
  runDefinitionCid: string;
  producerTaskKey: string;
  producerOutputPort: string;
  producerLogicalCid: string;
  carrierContractCid: string;
  consumerTaskKey: string;
  consumerLogicalCid: string;
  consumerInputPort: string;
  physicalSchemaCid: string;
}>;
/** Accepted producer evidence; independent current Transfer custody is required. */
export interface RetainedInputProducer {
  readonly [retainedInputProducerBrand]: true;
}
/** An atomic current snapshot from the trusted Host's existing Coordinator owner. */
export function prepareRetainedInputProducer(edge: RetainedTaskInputEdge,
  readCurrent: () => Readonly<{authority: string;
    durableRecordWire: string}>): RetainedInputProducer;
export function retainedInputProducerAvailable(producer: RetainedInputProducer): boolean;
export function retainedInputProducerFacts(producer: RetainedInputProducer): Readonly<{
  dispatch: Readonly<{cid: string; wire: string}>;
  evidence: Readonly<{cid: string; wire: string}>;
  subject: Readonly<{cid: string; wire: string}>;
}>;
/** Current trusted Owner ports; saved evidence is never its own authority. */
export interface RetainedInputPlanCurrent {
  readonly siteBindingCurrent: (siteKey: string, generation: number,
    runtimeBundleCid: string) => boolean;
  readonly authority: () => string;
  readonly nowUnixMs: () => bigint;
  readonly authorized: (producerDispatchCid: string,
    transferRequestWire: string) => boolean;
}
/** The actual receiver record exists only after physical handoff. */
export interface RetainedInputCurrent extends RetainedInputPlanCurrent {
  readonly readTransfer: () => string;
}
export interface RetainedInputTransferPolicy {
  readonly destinationGrantCid: string;
  readonly routeCapabilityCid: string;
  readonly sourceGrantCid: string;
  readonly transferAttempt: string;
  readonly transferExpiresUnixMs: bigint;
  readonly transferMaxBytes: bigint;
}
export interface RetainedInputIntent {
  readonly [retainedInputIntentBrand]: true;
}
export interface RetainedInputPlan {
  readonly [retainedInputPlanBrand]: true;
}
export interface RetainedInputPlanLimits {
  readonly maxChunks: number;
  readonly maxManifestBytes: number;
  readonly maxReferencedBytes: bigint;
}
export function prepareRetainedInputIntent(producer: RetainedInputProducer,
  policy: RetainedInputTransferPolicy): RetainedInputIntent;
export function admitRetainedInputIntent(producer: RetainedInputProducer,
  saved: Readonly<{cid: string; wire: string}>): RetainedInputIntent;
/** Historical wire alone is neither authority nor a physical input binding. */
export function retainedInputIntentFacts(intent: RetainedInputIntent): Readonly<{
  cid: string; wire: string;
}>;
export function retainedInputPlanEnvelope(intent: RetainedInputIntent): string;
export function admitRetainedInputPlan(intent: RetainedInputIntent,
  saved: Readonly<{cid: string; wire: string}>, current: RetainedInputPlanCurrent,
  limits: RetainedInputPlanLimits): RetainedInputPlan;
/** Revalidate current Owners across persistence and before delivery. */
export function validateRetainedInputPlan(plan: RetainedInputPlan): void;
export function retainedInputPlanFacts(plan: RetainedInputPlan): Readonly<{
  cid: string; wire: string;
  transfer: Readonly<{cid: string; wire: string}>;
  manifest: Readonly<{cid: string; wire: string}>;
}>;
/** The saved handoff is issued only after current Owner validation. */
export function retainedInputTransferEnvelope(plan: RetainedInputPlan): string;
/** Historical protocol evidence; no reservation, borrow or execution authority. */
export interface RetainedInputResult {
  readonly [retainedInputResultBrand]: true;
}
export function admitRetainedInputResult(plan: RetainedInputPlan,
  saved: Readonly<{cid: string; wire: string}>): RetainedInputResult;
export function retainedInputResultFacts(result: RetainedInputResult): Readonly<{
  cid: string; wire: string; planCid: string;
  transferReply: Readonly<{requestCid: string; wire: string}>;
  receipt: Readonly<{cid: string; wire: string}>;
}>;
export interface RetainedInputLimits {
  readonly maxChunks: number;
  readonly maxManifestBytes: number;
  readonly maxReferencedBytes: bigint;
  readonly maxBindingBytes: number;
}
/** Checked binding only; physical borrow/start claims remain with their Owners. */
export interface RetainedTaskInput {
  readonly [retainedTaskInputBrand]: true;
}
export function prepareRetainedTaskInput(producer: RetainedInputProducer,
  receipt: Readonly<{cid: string; wire: string}>, destinationUseId: string,
  current: RetainedInputCurrent, limits: RetainedInputLimits): RetainedTaskInput;
export function admitRetainedTaskInput(producer: RetainedInputProducer,
  saved: Readonly<{cid: string; wire: string}>,
  receipt: Readonly<{cid: string; wire: string}>, destinationUseId: string,
  current: RetainedInputCurrent, limits: RetainedInputLimits): RetainedTaskInput;
export function validateRetainedTaskInput(input: RetainedTaskInput): void;
/** Historical wire; this is neither material access nor execution permission. */
export function retainedTaskInputFacts(input: RetainedTaskInput): Readonly<{
  cid: string; wire: string;
}>;
export function issueRetainedTaskDispatch(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, request: RequestIdentity, task: number,
  selection: ValuesSiteSelection, input: RetainedTaskInput): Readonly<{
  cid: string; wire: string;
}>;
export function issueTaskDispatch(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, request: RequestIdentity, task: number,
  selection: ValuesSiteSelection): Readonly<{cid: string; wire: string}>;
/** Canonical contract admission is not publication or read authorization. */
export function admitPublicationContract<Name extends string>(name: Name,
  wire: string, limits: PublicationLimits): PublicationContract<Name>;
export function admitRunEvidenceValue(name: string, wire: string,
  limits: PublicationLimits): RunEvidence;
/** Seal registered evidence without granting authority or publication. */
export function sealRunEvidenceValue(name: string, bodyWire: string,
  limits: PublicationLimits): RunEvidence;
export function issueResultManifest(runDefinition: PublicationContract,
  invocation: PublicationContract,
  definitions: readonly PublicationContract[],
  artifacts: readonly PublicationContract[],
  limits: PublicationLimits): PublicationContract;
/** Facts must come from the exact completed, checked Result export. */
export function issueResultOccurrenceEvidence(
  definition: PublicationContract, facts: Readonly<{
    logicalValueCid: string;
    resultSchemaCid: string;
    computationContractCid: string;
    inputRelationCids: readonly string[];
    scopeCid: string;
    effectiveDataPolicyCid: string;
    issuerId: string;
    authorityScopeCid: string;
  }>, limits: PublicationLimits): ResultOccurrenceEvidence;
/** Checked source-free Values binding; Plan and Result port come from owner. */
export function issueCheckedValuesResultOccurrenceEvidence(
  prepared: PreparedProgram, compilation: ValuesCompilation,
  definition: PublicationContract, facts: Readonly<{
    logicalValueCid: string;
    resultSchemaCid: string;
    scopeCid: string;
    effectiveDataPolicyCid: string;
    issuerId: string;
    authorityScopeCid: string;
  }>, limits: PublicationLimits): ResultOccurrenceEvidence;
export function issueCompleteResultArtifact(definition: PublicationContract,
  invocation: PublicationContract, evidence: ResultOccurrenceEvidence,
  retention: PublicationContract, actualRowCount: number,
  limits: PublicationLimits): PublicationContract;
/** Physical facts must come from an independently held Store object. */
export function issueDurableResultBinding(
  runDefinition: PublicationContract, definition: PublicationContract,
  invocation: PublicationContract, artifact: PublicationContract,
  ordering: PublicationContract, retention: PublicationContract,
  physical: Readonly<{
    codecContractCid: string;
    resultFields: readonly string[];
    resultSchemaWire: string;
    materialGenerationCid: string;
    storeAuthorityCid: string;
    rowCount: number;
    byteCount: number;
    physicalSha256: string;
  }>, limits: PublicationLimits): PublicationContract;
/** Establish logical identity from bounded bytes at the physical holder. */
export function inspectCanonicalResultRows(rowsWire: string,
  fields: readonly string[], limits: PublicationLimits):
  Readonly<{logicalRelationCid: string; rowCount: number}>;
export function validatePublicationChain(runDefinition: PublicationContract,
  invocation: PublicationContract,
  definitions: readonly PublicationContract[],
  artifacts: readonly PublicationContract[], manifest: PublicationContract,
  limits: PublicationLimits): void;
/** Physical CAS and durable persistence remain Store effects. */
export function validatePublicationRecordTransition(
  previous: PublicationRecordContract | undefined,
  next: PublicationRecordContract,
  uncommittedConfirmed: boolean): void;
/** Immutable request for the full checked Named Result inventory. */
export function issuePublicationRequest(runDefinition: PublicationContract,
  definitions: readonly PublicationContract[], facts: Readonly<{
    namespaceId: string;
    authorityScopeCid: string;
    publicationPolicyCid: string;
    publicationTargetCid: string;
    requestedAt: string;
  }>, limits: PublicationLimits): PublicationRequestContract;
/** One attempt identity, separate from Store effects and outcome. */
export function issuePublicationAttempt(request: PublicationRequestContract,
  runDefinition: PublicationContract, facts: Readonly<{
    attemptId: string;
    fenceCid: string;
    externalIdempotencyKey?: string;
    startedAt: string;
  }>, limits: PublicationLimits): PublicationAttemptContract;
/** Candidate entry; the Store must atomically validate and install it. */
export function issuePublicIndexEntry(runDefinition: PublicationContract,
  invocation: PublicationContract, manifest: PublicationContract,
  receipt: PublicationContract, capturedRun: PublicationContract,
  durableBindings: readonly PublicationContract[],
  request: PublicationRequestContract, attempt: PublicationAttemptContract,
  committedAt: string, limits: PublicationLimits): PublicIndexEntryContract;
/** Validate full captured evidence and index binding before Store commit. */
export function validateEffectFreePublicationCommit(evidence: Readonly<{
  runDefinition: PublicationContract;
  invocation: PublicationContract;
  definitions: readonly PublicationContract[];
  artifacts: readonly PublicationContract[];
  derivations: readonly PublicationContract[];
  orderings: readonly PublicationContract[];
  retentions: readonly PublicationContract[];
  durableBindings: readonly PublicationContract[];
  manifest: PublicationContract;
  receipt: PublicationContract;
  capturedRun: PublicationContract;
}>, request: PublicationRequestContract,
  attempt: PublicationAttemptContract,
  indexEntry: PublicIndexEntryContract, limits: PublicationLimits): void;
/** Sequence and predecessor come from the shared publication owner. */
export function issuePublicationRecord(attempt: PublicationAttemptContract,
  previous: PublicationRecordContract | undefined, facts: Readonly<{
    state: string;
    observedAt: string;
    publicIndexEntry?: PublicIndexEntryContract;
    failureCid?: string;
    cleanupOwnerCids: readonly string[];
    uncommittedConfirmed: boolean;
  }>, limits: PublicationLimits): PublicationRecordContract;
/** The shared owner checks the full Effect-free completion chain. */
export function issueEffectFreeRunReceipt(admission: RunAdmission,
  runDefinition: PublicationContract, invocation: PublicationContract,
  observation: RunEvidence,
  definitions: readonly PublicationContract[],
  artifacts: readonly PublicationContract[],
  manifest: PublicationContract, normalizationJournal: RunEvidence,
  facts: Readonly<{
    bindingNames: readonly string[];
    bindingDigests: readonly string[];
    sourceEvidence: readonly RunEvidence[];
    modelEvidence: readonly RunEvidence[];
    barrierAttemptReceiptCids: readonly string[];
  }>, limits: PublicationLimits): PublicationContract;
/** Rows are checked against the issued Result Artifact before capture. */
export function admitCapturedResultSnapshot(definition: PublicationContract,
  artifact: PublicationContract, rowsWire: string,
  fields: readonly string[], limits: PublicationLimits):
  CapturedResultSnapshot;
/** Source-free capture uses the same read-only captured-computation owner. */
export function issueSourceFreeCapturedRun(
  runDefinition: PublicationContract, invocation: PublicationContract,
  definitions: readonly PublicationContract[],
  artifacts: readonly PublicationContract[],
  manifest: PublicationContract, receipt: PublicationContract,
  snapshots: readonly CapturedResultSnapshot[], authoring: RunEvidence,
  models: readonly RunEvidence[], limits: PublicationLimits):
  PublicationContract;

/** Read-only Source capture has no source-state advances; receipt validation
 * still requires the exact acquired Source evidence inventory. */
export function issueReadOnlyCapturedRun(
  runDefinition: PublicationContract, invocation: PublicationContract,
  definitions: readonly PublicationContract[],
  artifacts: readonly PublicationContract[],
  manifest: PublicationContract, receipt: PublicationContract,
  snapshots: readonly CapturedResultSnapshot[], authoring: RunEvidence,
  models: readonly RunEvidence[], limits: PublicationLimits):
  PublicationContract;

/** A checked snapshot grants neither execution, authorization nor input custody. */
export function inspectTaskProgress(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, authority: string,
  durableWires: readonly string[]): Readonly<{
    nextTask: number | undefined; executionComplete: boolean;
    cleanupComplete: boolean; resultTasks: readonly number[];
    tasks: readonly Readonly<{ordinal: number; taskKey: string;
      execution: 'unobserved' | 'accepted' | 'provisioning' | 'running' |
        'settled' | 'failed' | 'cancelled' | 'unknown';
      cleanup: 'unobserved' | 'active' | 'releasing' | 'released' |
        'unknown' | 'force_lost' | 'recovered_after_loss';
      revision: number; dispatchCid: string | undefined;
      executionScope: readonly string[]}>[];
  }>;

/** Authenticated storage is supplied by the Host; this grants no execution. */
export function projectSiteRun(prepared: PreparedProgram,
  compilation: ValuesCompilation | TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, authority: string, durableWire: string,
  observedAt: string, cancellationRequested?: boolean,
  physicalStartClaimed?: boolean): Readonly<{stateWire: string;
    execution: 'unobserved' | 'running' | 'settled' | 'failed' |
      'cancelled' | 'unknown';
    cleanup: 'complete' | 'pending'; revision: number;
    nextWork: 'none' | 'cleanup' | 'publication' | 'reconcile' | 'cancel' | 'release'}>;

export function prepareRunPhysicalStart(requested: RequestIdentity,
  retained: RequestIdentity, definition: RunDefinition, definitionCid: string,
  reserved: boolean, unstarted: boolean, authorized: boolean,
  cancelled: boolean, failed?: boolean): boolean;
export function prepareRunPreStartFailure(requested: RequestIdentity,
  retained: RequestIdentity, definition: RunDefinition, definitionCid: string,
  reserved: boolean, unstarted: boolean, admissionDenied: boolean,
  cancelled: boolean): boolean;
export function prepareRunCancellation(definition: RunDefinition,
  definitionCid: string, authorized: boolean, terminal: boolean,
  requested: boolean): 'accepted' | 'already_requested' | 'already_terminal';
export function issueRunControlObservation(revision: number,
  observation: Readonly<{requested: boolean; unstarted: boolean;
    stopped: boolean}>): Readonly<{
    revision: number; cancellation_requested: boolean;
    physical_stop: 'unknown' | 'confirmed'}>;
