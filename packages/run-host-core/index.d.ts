declare const retainedInputCurrentQueryBrand: unique symbol;
declare const retainedInputCurrentReplyBrand: unique symbol;
declare const environmentBrand: unique symbol;
declare const preparedBrand: unique symbol;
declare const compilationBrand: unique symbol;
declare const taskCompilationBrand: unique symbol;
declare const effectPreparationBrand: unique symbol;
declare const effectCompilationBrand: unique symbol;
declare const effectAllowedBrand: unique symbol;
declare const effectPreviewIdentityBrand: unique symbol;
declare const effectCheckpointBindingBrand: unique symbol;
declare const issuedEffectMaterialsBrand: unique symbol;
declare const requestBrand: unique symbol;
declare const admissionBrand: unique symbol;
declare const definitionBrand: unique symbol;
declare const publicationBrand: unique symbol;
declare const deliveryContractBrand: unique symbol;
declare const resultOccurrenceBrand: unique symbol;
declare const runEvidenceBrand: unique symbol;
declare const originalRunPlanBrand: unique symbol;
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

/** In-process first-capture provenance; saved metadata cannot recreate it. */
export interface OriginalRunPlan {
  readonly [originalRunPlanBrand]: true;
}

export interface StoredRunPlanOriginal {
  readonly compiledPlanWire: string;
  readonly planViewWire: string;
}

/** No new Run, preparation or execution. Persist in the first admission CAS. */
export function captureOriginalRunPlan(prepared: PreparedProgram,
  compilation: ValuesCompilation | TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, limits: PublicationLimits): OriginalRunPlan;
export function originalRunPlanAdmissionEvidence(selection: OriginalRunPlan,
  definition: RunDefinition, programCid: string,
  evidence: Readonly<{prepared: string; authorization: string}>): StoredRunPlanOriginal;
/** Metadata only; current RunRead and the saved Run/request/context join remain
 * with the Host. Missing legacy originals are unavailable, never recompiled. */
export function readStoredRunPlanOriginal(original: StoredRunPlanOriginal | undefined,
  definition: RunDefinition, programCid: string, limits: PublicationLimits): string;

export interface ValuesCompilation {
  readonly [compilationBrand]: true;
}

export interface TaskCompilation {
  readonly [taskCompilationBrand]: true;
}

/** Static checked Effect computation; never an approval or apply permit. */
export interface PreparedEffectProgram {
  readonly [effectPreparationBrand]: true;
}
export interface EffectCompilation {
  readonly [effectCompilationBrand]: true;
}
export interface AllowedEffectRun {
  readonly [effectAllowedBrand]: true;
}
/** Static preparation selection; never permission to acquire or apply. */
export function prepareProgram(document: string, format: 'json' | 'yaml',
  environment: CheckEnvironment, parametersWire?: string):
  Readonly<{kind: 'effect_free'; prepared: PreparedProgram}> |
  Readonly<{kind: 'effect'; prepared: PreparedEffectProgram}>;
/** Same original submitted SQL/AQL and trusted installation publication.
 * Static preparation is not Source access, current authorization or capacity. */
export type PreparedSourceProgram =
  Readonly<{kind: 'effect_free'; prepared: PreparedProgram; originalIntent: SubmittedIntent}> |
  Readonly<{kind: 'effect'; prepared: PreparedEffectProgram; originalIntent: SubmittedIntent}>;
export interface SourceProgramOriginals {
  /** Absent on historical originals; restore never upgrades their primary. */
  readonly primaryResultRecipe?: 'public-main';
  readonly intentWire: string;
  readonly intentCid: string;
  readonly environmentCid: string;
  readonly publicationWire: string;
}
export function prepareSourceProgram(intent: SubmittedIntent,
  environment: CheckEnvironment, publicationWire: string): PreparedSourceProgram;
export function sourceProgramOriginals(prepared: PreparedProgram | PreparedEffectProgram): SourceProgramOriginals;
export function sourceProgramSourceInput(prepared: PreparedProgram | PreparedEffectProgram): Readonly<{
  document: string; format: string; parametersWire?: string; parameterDeclarationsWire?: string}>;
export function sourceProgramMaterialInput(prepared: PreparedProgram | PreparedEffectProgram,
  environmentWire: string): SourceFreeRunMaterialsInput;
/** Host-authenticated saved originals; never rediscover publication on restore. */
export function restoreSourceProgram(originals: SourceProgramOriginals,
  environment: CheckEnvironment): PreparedSourceProgram;
export function prepareSourceRequest(prepared: PreparedProgram | PreparedEffectProgram,
  intent: SubmittedIntent, authorityScopeCid: string, requestId: string): RequestIdentity;
export function admitSourceRequestFields(prepared: PreparedProgram | PreparedEffectProgram,
  intent: SubmittedIntent, fields: RequestFields): RequestIdentity;
export function prepareEffect(document: string, format: 'json' | 'yaml',
  environment: CheckEnvironment, parametersWire?: string): PreparedEffectProgram;
/** Explicit finite normalization selected by the original checked create/update kind.
 * Actual semantic completions refuse; current authority/approval stay separate. */
export function compileEffect(prepared: PreparedEffectProgram,
  options?: Readonly<{normalizationProfile?: 'completion-free'}>): EffectCompilation;
export function effectExecutionShape(prepared: PreparedEffectProgram,
  compilation: EffectCompilation): Readonly<{taskCount: number; acquisitionCount: number; effectCount: number}>;
/** Checked coordinates only; these grant no acquisition, start or approval. */
export function effectTaskKeys(prepared: PreparedEffectProgram,
  compilation: EffectCompilation): readonly string[];
export function effectResultDefinitions(prepared: PreparedEffectProgram,
  compilation: EffectCompilation): readonly Readonly<{name: string; cid: string; wire: string}>[];
export function effectResultSchema(prepared: PreparedEffectProgram,
  compilation: EffectCompilation, resultName: string): Readonly<{
    cid: string; wire: string; fields: readonly string[]}>;
/** Metadata binding to the original checked Effect Run/unit/window only.
 * Does not confirm Native custody, current authority, waiting or approval. */
export interface EffectReviewCheckpointBinding {
    readonly [effectCheckpointBindingBrand]: true;
    readonly checkpointCid: string; readonly checkpointWire: string;
    readonly runId: string; readonly unitId: string;
    readonly runDefinitionCid: string; readonly previewCid: string;
    readonly reviewProjectionCid: string; readonly continuationCid: string;
}
export function effectReviewCheckpointBinding(allowed: AllowedEffectRun,
  definition: RunDefinition, checkpointWire: string): EffectReviewCheckpointBinding;
/** Same admitted original only; no wire admission, persistence or current grant. */
export function effectReviewCheckpointBindingFacts(binding: EffectReviewCheckpointBinding,
  allowed: AllowedEffectRun, definition: RunDefinition): EffectReviewCheckpointBinding;
/** Derive authoring context from the original checked Effect owner and bind
 * the actual stored Checkpoint/Preview. No current permission or ACK follows. */
export function effectReviewCheckpointPreview(binding: EffectReviewCheckpointBinding,
  allowed: AllowedEffectRun, definition: RunDefinition, storedWire: string,
  previewWire: string, limits: PublicationLimits): EffectPreviewIdentity;
/** Same nominal binding and actual stored wire, not a persistence/current grant. */
export function effectReviewCheckpointWaitingState(binding: EffectReviewCheckpointBinding,
  allowed: AllowedEffectRun, definition: RunDefinition, storedWire: string,
  updatedAt: string, declaredResults: readonly string[]): string;
/** Pure complete-Unknown receipt projection; no current/physical authority. */
export function effectReviewCheckpointReconciliationState(binding: EffectReviewCheckpointBinding,
  allowed: AllowedEffectRun, definition: RunDefinition, storedWire: string,
  previewWire: string, invocationWire: string, setReceiptWire: string,
  memberReceiptWires: readonly string[], updatedAt: string,
  declaredResults: readonly string[]): string;
/** Pure confirmed-cancellation DATA; whole-Run premises stay with the Host. */
export function effectReviewCheckpointCancelledState(binding: EffectReviewCheckpointBinding,
  allowed: AllowedEffectRun, definition: RunDefinition, storedWire: string,
  updatedAt: string, declaredResults: readonly string[]): string;
/** Project only the members of the original checked unit/Checkpoint. */
export function effectReviewCheckpointMembers(allowed: AllowedEffectRun,
  definition: RunDefinition, checkpointWire: string): readonly string[];
/** Original Catalog evidence; current read authority remains a separate check. */
export function effectSourceEvidenceFacts(prepared: PreparedEffectProgram,
  compilation: EffectCompilation, stage: number, sourceIndex: number): Readonly<{
    sourceRef: string; sourceContractCid: string; carrierSchemaContractCid: string;
    sourceDataPolicyCid: string; dataClassification: string; sourceViewContractCid: string;
  }> | undefined;
export function privateEffectCompilationWires(compilation: EffectCompilation):
  Readonly<{boundTemplate: string; compiledPlan: string}>;
/** Current Host authorization precedes issuance; Effect approval is separate. */
export function issueAllowedEffectRun(prepared: PreparedEffectProgram,
  compilation: EffectCompilation, policy: Readonly<{executionContextCid: string;
    hostPolicyCid: string; expiresAt: string}>): AllowedEffectRun;
export function privateEffectRunEvidence(allowed: AllowedEffectRun):
  Readonly<{preparedInvocationWire: string; authorizationWire: string}>;
export function issueEffectRunDefinition(allowed: AllowedEffectRun,
  scopeId: string, runId: string, createdAt: string, validUntil: string): RunDefinition;
export function issueEffectRunMaterials(allowed: AllowedEffectRun,
  definition: RunDefinition, retained: Readonly<{format: 'json'; document: string;
    environment: CheckEnvironment; environmentWire: string;
    parametersWire?: string}>, request?: RequestIdentity): string;
/** Process-local opaque issuance proof. Copying its visible wire loses custody. */
export interface IssuedEffectRunMaterials {
  readonly [issuedEffectMaterialsBrand]: true;
  readonly wire: string;
}
/** Original checked preparation owns completion-free issuance; no replacement inputs. */
export function issuePreparedEffectRunMaterials(allowed: AllowedEffectRun,
  definition: RunDefinition, request?: RequestIdentity): IssuedEffectRunMaterials;
export type RestoredEffectRun = Readonly<{prepared: PreparedEffectProgram;
  compilation: EffectCompilation; allowed: AllowedEffectRun;
  definition: RunDefinition; request?: RequestIdentity}>;
/** Bind the exact process-local issuer/Run/request originals without preparing
 * or compiling again. Current authorization and durable custody are separate. */
export function bindPreparedEffectRunMaterials(allowed: AllowedEffectRun,
  definition: RunDefinition, issued: IssuedEffectRunMaterials,
  request: RequestIdentity): RestoredEffectRun;
/** definitionCid and expectedRequest must come from trusted original durable
 * context, independently of candidate wire. This is not current authorization. */
export function admitEffectRunMaterials(wire: string, definitionCid: string,
  profiles: ProfileSelection,
  original?: IssuedEffectRunMaterials, expectedRequest?: RequestIdentity,
  sourcePrepared?: PreparedEffectProgram): RestoredEffectRun;
/** Requires the exact admitted material object; does not grant approval. */
export function restoreEffectRunNormalization(materials: RestoredEffectRun): RunEvidence;
/** Original saved policy lifetime, not current Host authority or approval. */
export function effectRunStartCurrent(allowed: AllowedEffectRun,
  definition: RunDefinition, at: string): boolean;

/** Caller identity only; no Source permission or Effect approval. */
export function prepareEffectRequest(prepared: PreparedEffectProgram,
  compilation: EffectCompilation, authorityScopeCid: string, requestId: string): RequestIdentity;
export function effectSourceInputBinding(compilation: EffectCompilation, request?: RequestIdentity): string;
export function issueEffectSourceDispatch(allowed: AllowedEffectRun,
  definition: RunDefinition, request: RequestIdentity,
  selection: ValuesSiteSelection): Readonly<{cid: string; wire: string}>;
export function prepareEffectRetainedTaskInputEdge(allowed: AllowedEffectRun,
  definition: RunDefinition): RetainedTaskInputEdge;
export function issueEffectRetainedTaskDispatch(allowed: AllowedEffectRun,
  definition: RunDefinition, request: RequestIdentity,
  selection: ValuesSiteSelection, input: RetainedTaskInput): Readonly<{cid: string; wire: string}>;

/** Count physical checked tasks separately from Result Plan transformations. */
export function taskExecutionShape(prepared: PreparedProgram,
  compilation: TaskCompilation): Readonly<{taskCount: number; acquisitionCount: number}>;

export interface RequestIdentity {
  readonly [requestBrand]: true;
}

export interface RunAdmission {
  readonly [admissionBrand]: true;
}

declare const cancellationIdentityBrand: unique symbol;
export interface RunCancellationIdentity {
  readonly [cancellationIdentityBrand]: true;
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

declare const issuedDeliveryAttemptBrand: unique symbol;
export interface IssuedDeliveryAttemptOriginal {
  readonly [issuedDeliveryAttemptBrand]: true;
}
export interface IssuedDeliveryAttemptFacts {
  readonly index: IndexView;
  readonly manifest: ManifestView;
  readonly grant: GrantView;
  readonly attempt: AttemptView;
  readonly request: Readonly<{resultName: string; format: string;
    attemptId: string; requestedAt: string}>;
  readonly limits: PublicationLimits;
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
  /** Reuse an original publication from this module without wire admission. */
  fromPublication<Kind extends string>(original: PublicationContract<Kind>):
    DeliveryContractView<Kind>;
  fromPublication<Kind extends string>(original: PublicationContract,
    expectedName: Kind): DeliveryContractView<Kind>;
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
  /** Capture this issuer's exact immutable inputs; no authority or durable ACK. */
  captureIssuedDeliveryAttempt(attempt: AttemptView, index: IndexView,
    manifest: ManifestView, grant: GrantView, limits: PublicationLimits):
    IssuedDeliveryAttemptOriginal | undefined;
  readIssuedDeliveryAttempt(original: IssuedDeliveryAttemptOriginal):
    IssuedDeliveryAttemptFacts;
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
  /** Exact installed numeric reduction profile; omission enables none. */
  readonly numericProfileCid?: string;
}

/** Validate the closed profile selection contract and normalize omitted booleans
 * to false; an omitted numeric profile remains unavailable. Returns a detached
 * frozen value suitable for retained Run input;
 * it does not admit a Check Environment or grant execution authority. */
export function admitProfileSelection(profiles: unknown):
  Readonly<Required<Omit<ProfileSelection, 'numericProfileCid'>> &
    Pick<ProfileSelection, 'numericProfileCid'>>;

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
/** Project an unpublished candidate from retained physical facts. The Host must
 * complete its state observation using the original Run row and confirmed CAS. */
export function issueUnpublishedRunStateWire(prepared: PreparedProgram,
  compilation: ValuesCompilation | TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, observedAt: string,
  observation: Readonly<{dispatchReserved: boolean;
    preDispatchFailureConfirmed: boolean; cancelledBeforeStart?: boolean;
    executionUnknown?: boolean}>): string;
/** Project an unpublished candidate for a committed Run with current availability.
 * The Host completes its state observation through the same original Run row. */
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
/** A fresh receiver query; never an execution attempt or physical borrow. */
export interface RetainedInputCurrentQuery {
  readonly [retainedInputCurrentQueryBrand]: true;
}
export interface RetainedInputCurrentReply {
  readonly [retainedInputCurrentReplyBrand]: true;
}
export function prepareRetainedInputCurrentQuery(plan: RetainedInputPlan,
  queryId: string): RetainedInputCurrentQuery;
export function retainedInputCurrentEnvelope(query: RetainedInputCurrentQuery): string;
export function admitRetainedInputCurrentReply(query: RetainedInputCurrentQuery,
  saved: Readonly<{cid: string; wire: string}>,
  limits: RetainedInputPlanLimits): RetainedInputCurrentReply;
/** Historical snapshot of the live query, never replayed as current authority. */
export function retainedInputCurrentReplyFacts(reply: RetainedInputCurrentReply): Readonly<{
  cid: string; wire: string; transferRecordWire: string;
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
/** Pure binding DATA from the same admitted public Review, never a grant. */
export function effectReviewProjectionBindingFacts(review: RunEvidence): Readonly<{
  previewCid: string;
  authoringContextCid: string;
  authorityScopeCid: string;
  approvalClaims: readonly string[];
}>;
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
/** Historical Preview DATA from this module's Common admission; no Allow,
 * physical outcome, claim, Store commit or acknowledgement is supplied. */
export interface EffectPreviewIdentity {
  readonly [effectPreviewIdentityBrand]: true;
}
/** Expected original identity/context come independently from trusted custody. */
export function admitEffectPreviewIdentity(wire: string,
  expectedRunIdentityCid: string, expectedAuthoringContextCid: string,
  limits: PublicationLimits): EffectPreviewIdentity;
/** Existing semantic identity for joining the original Checkpoint Preview;
 * this pure observer is not a Store digest or current authority. */
export function effectPreviewIdentityCid(preview: EffectPreviewIdentity): string;
/** Derive only from the complete original computation/capture/Effect receipts. */
export function issueEffectfulFinalRunReceipt(runDefinition: PublicationContract,
  computationReceipt: PublicationContract, capturedRun: PublicationContract,
  preview: EffectPreviewIdentity, setReceiptWire: string,
  memberReceiptWires: readonly string[], limits: PublicationLimits): PublicationContract;
export interface EffectfulPublicationCommitEvidence {
  readonly runDefinition: PublicationContract;
  readonly invocation: PublicationContract;
  readonly definitions: readonly PublicationContract[];
  readonly artifacts: readonly PublicationContract[];
  readonly derivations: readonly PublicationContract[];
  readonly orderings: readonly PublicationContract[];
  readonly retentions: readonly PublicationContract[];
  readonly durableBindings: readonly PublicationContract[];
  readonly manifest: PublicationContract;
  readonly computationReceipt: PublicationContract;
  readonly capturedRun: PublicationContract;
  readonly preview: EffectPreviewIdentity;
  readonly setReceiptWire: string;
  readonly memberReceiptWires: readonly string[];
  readonly finalReceipt: PublicationContract;
}
/** Complete Common Effectful/Result-evidence validation before the separate
 * current Store CAS; successful validation is not a commit acknowledgement. */
export function validateEffectfulPublicationCommit(evidence: EffectfulPublicationCommitEvidence,
  request: PublicationRequestContract, attempt: PublicationAttemptContract,
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

/** Computation/output facts only; no Effect outcome or public Run state. */
export function inspectEffectTaskProgress(allowed: AllowedEffectRun,
  definition: RunDefinition, authority: string,
  durableWires: readonly string[]): Readonly<{
    nextTask: number | undefined; computationComplete: boolean;
    taskCleanupComplete: boolean; resultTasks: readonly number[];
    tasks: ReturnType<typeof inspectTaskProgress>['tasks'];
  }>;
/** Unpublished same-Run observation only. No Effect outcome, whole-Run stop,
 * approval, publication or release acknowledgement follows from task facts.
 * The Host supplies the complete original saved claim set, not copied keys. */
export function projectEffectSiteRun(allowed: AllowedEffectRun,
  definition: RunDefinition, authority: string, durableWires: readonly string[],
  observedAt: string, cancellationRequested: boolean,
  savedClaims: readonly Readonly<{taskKey: string; dispatchCid: string | null;
    dispatchReserved: boolean; physicalStartClaimed: boolean}>[]): Readonly<
    Omit<ReturnType<typeof inspectEffectTaskProgress>, 'tasks'> & {
      stateWire: string; publicationReady: false;
      execution: 'unobserved' | 'running' | 'settled' | 'failed' | 'cancelled' | 'unknown';
      tasks: readonly Readonly<ReturnType<typeof inspectTaskProgress>['tasks'][number] & {
        nextWork: 'none' | 'cleanup' | 'publication' | 'reconcile' | 'cancel' | 'release'}>[];
    }>;
/** Prepare a saved task claim; current input/Source custody remains separate. */
export function prepareEffectTaskPhysicalStart(allowed: AllowedEffectRun,
  definition: RunDefinition, authority: string, durableWires: readonly string[],
  requested: RequestIdentity, retained: RequestIdentity,
  claim: Readonly<{taskKey: string; dispatchCid: string; definitionCid: string;
    reserved: boolean; unstarted: boolean; authorized: boolean;
    cancelled: boolean; failed: boolean}>): boolean;

/** An unpublished snapshot. Start claims must come from trusted saved Host state.
 * This does not commit a Run, publish a Result, stop execution or release custody. */
export function projectTaskSiteRun(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, authority: string, durableWires: readonly string[],
  observedAt: string, cancellationRequested?: boolean,
  claimedTaskKeys?: readonly string[]): Readonly<{
    stateWire: string; publicationReady: boolean;
    nextTask: number | undefined; executionComplete: boolean; cleanupComplete: boolean;
    resultTasks: readonly number[];
    execution: 'unobserved' | 'running' | 'settled' | 'failed' | 'cancelled' | 'unknown';
    tasks: readonly Readonly<{ordinal: number; taskKey: string;
      execution: 'unobserved' | 'accepted' | 'provisioning' | 'running' |
        'settled' | 'failed' | 'cancelled' | 'unknown';
      cleanup: 'unobserved' | 'active' | 'releasing' | 'released' |
        'unknown' | 'force_lost' | 'recovered_after_loss';
      revision: number; dispatchCid: string | undefined; executionScope: readonly string[];
      nextWork: 'none' | 'cleanup' | 'publication' | 'reconcile' | 'cancel' | 'release'}>[];
  }>;

/** Prepares eligibility only. Atomically persist the task claim in the existing
 * Run/cancellation CAS domain before sending; this grants no input custody. */
export function prepareTaskPhysicalStart(prepared: PreparedProgram,
  compilation: TaskCompilation, admission: RunAdmission, definition: RunDefinition,
  authority: string, durableWires: readonly string[], requested: RequestIdentity,
  retained: RequestIdentity, claim: Readonly<{taskKey: string; dispatchCid: string;
    definitionCid: string; reserved: boolean; unstarted: boolean;
    authorized: boolean; cancelled: boolean; failed: boolean}>): boolean;

/** Project an unpublished candidate from the admitted original Site record.
 * Its outer revision belongs to the Coordinator observation, not public Run state.
 * Authenticated storage and the final same-Run observation/CAS belong to the Host. */
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
/** Identity only; persist its original outcome in the existing Run CAS.
 * Admission does not authorize physical stop, execution or resource release. */
export function prepareRunCancellationIdentity(definition: RunDefinition,
  scope: Readonly<{namespaceId: string; authorityScopeCid: string;
    cancelId: string; expectedRevision: number}>): RunCancellationIdentity;
/** Checksum only, not storage provenance or authorization. */
export function runCancellationIntentCid(identity: RunCancellationIdentity): string;
/** Exact replay returns replay_original: read the saved outcome unchanged.
 * Recheck authorization and Run revision after asynchronous work and before CAS. */
export function prepareRunCancellationOperation(definition: RunDefinition,
  requested: RunCancellationIdentity, facts: Readonly<{
    retained?: RunCancellationIdentity; currentRevision: number;
    currentAuthorization: boolean; terminalObserved: boolean;
    cancellationRequested: boolean;
  }>): 'accepted' | 'already_requested' | 'already_terminal' | 'replay_original';
export function issueRunControlObservation(revision: number,
  observation: Readonly<{requested: boolean; unstarted: boolean;
    stopped: boolean}>): Readonly<{
    revision: number; cancellation_requested: boolean;
    physical_stop: 'unknown' | 'confirmed'}>;


declare const submissionEpochBrand: unique symbol;
export interface SubmissionEpoch {readonly [submissionEpochBrand]: true;}
declare const submittedIntentBrand: unique symbol;
export interface SubmittedIntent {readonly [submittedIntentBrand]: true;}
/** Identity only: the physical Host must authenticate and retain validation custody. */
export function prepareSubmissionEpoch(scope: Readonly<{authorityScopeCid: string;
  epochNonce: string; notBefore: number; expiresAt: number}>): SubmissionEpoch;
export function submissionEpochFacts(epoch: SubmissionEpoch): Readonly<{wire: string; cid: string}>;
export function submissionEpochValidity(epoch: SubmissionEpoch, now: number):
  'admissible' | 'not_yet_valid' | 'expired';
/** Same original epoch and nonce retain the original request identity on replay. */
export function submissionRequestId(epoch: SubmissionEpoch, nonce: string): string;
/** Original submitted content only; this does not issue a Run or grant permission. */
export function prepareSubmittedIntent(wire: string, limits: Readonly<{
  maxWireBytes: number; maxNodes: number; maxDepth: number}>): SubmittedIntent;
export function submittedIntentFacts(intent: SubmittedIntent): Readonly<{wire: string; cid: string}>;
export function submittedIntentTransition(before: string, after: string): boolean;
