import {runtimeField, runtimeIsError, runtimeIsBoxedNone, runtimeIsOk, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import * as owner from './dist/client_values_host_abi.js';

declare const retainedInputCurrentQueryBrand: unique symbol;

declare const retainedInputCurrentReplyBrand: unique symbol;

declare const environmentBrand: unique symbol;

declare const publishedEnvironmentBrand: unique symbol;

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

export interface CheckEnvironment {
  readonly [environmentBrand]: true;
}

/** Static publication/Catalog facts for one original admitted Environment.
 * No Program values, current permission, Run or physical custody is retained. */
export interface PreparedPublishedEnvironment {
  readonly [publishedEnvironmentBrand]: true;
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

/** Metadata binding to the original checked Effect Run/unit/window only.
 * Does not confirm Native custody, current authority, waiting or approval. */
export interface EffectReviewCheckpointBinding {
    readonly [effectCheckpointBindingBrand]: true;
    readonly checkpointCid: string; readonly checkpointWire: string;
    readonly runId: string; readonly unitId: string;
    readonly runDefinitionCid: string; readonly previewCid: string;
    readonly reviewProjectionCid: string; readonly continuationCid: string;
}

/** Process-local opaque issuance proof. Copying its visible wire loses custody. */
export interface IssuedEffectRunMaterials {
  readonly [issuedEffectMaterialsBrand]: true;
  readonly wire: string;
}

export type RestoredEffectRun = Readonly<{prepared: PreparedEffectProgram;
  compilation: EffectCompilation; allowed: AllowedEffectRun;
  definition: RunDefinition; request?: RequestIdentity}>;

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

export type PublicationIndexObservation =
  | Readonly<{kind: 'absent'}>
  | Readonly<{kind: 'unknown'}>
  | Readonly<{kind: 'committed'; entry: PublicationContract}>;

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

export interface PrivateCompilationWires {
  readonly executablePlan: string;
  readonly factManifest: string;
  readonly boundTemplate: string;
  readonly compiledPlan: string;
}

/** Project an unpublished candidate for a committed Run with current availability.
 * The Host completes its state observation through the same original Run row. */
type RunResultStateObservation = Readonly<{name: string;
    state: 'available' | 'unavailable' | 'unknown';
    reason: 'confirmed_present' | 'retention_expired' | 'deleted' |
      'policy_unavailable' | 'integrity_failed' | 'not_published' |
      'store_query_failed' | 'clock_uncertain' | 'verification_pending';
    observedAt: string}>;

/** Original JSON input retained alongside a Run; not new authority. */
export interface SourceFreeRunMaterialsInput {
  readonly document: string;
  readonly format: 'json';
  readonly environment: CheckEnvironment;
  readonly environmentWire: string;
  readonly parametersWire?: string;
}

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

/** A checked edge, not producer completion, physical custody or permission. */
export interface RetainedTaskInputEdge {
  readonly [retainedInputEdgeBrand]: true;
}

/** Accepted producer evidence; independent current Transfer custody is required. */
export interface RetainedInputProducer {
  readonly [retainedInputProducerBrand]: true;
}

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

/** Historical protocol evidence; no reservation, borrow or execution authority. */
export interface RetainedInputResult {
  readonly [retainedInputResultBrand]: true;
}

/** A fresh receiver query; never an execution attempt or physical borrow. */
export interface RetainedInputCurrentQuery {
  readonly [retainedInputCurrentQueryBrand]: true;
}

export interface RetainedInputCurrentReply {
  readonly [retainedInputCurrentReplyBrand]: true;
}

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

/** Historical Preview DATA from this module's Common admission; no Allow,
 * physical outcome, claim, Store commit or acknowledgement is supplied. */
export interface EffectPreviewIdentity {
  readonly [effectPreviewIdentityBrand]: true;
}

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

declare const submissionEpochBrand: unique symbol;

export interface SubmissionEpoch {readonly [submissionEpochBrand]: true;}

declare const submittedIntentBrand: unique symbol;

export interface SubmittedIntent {readonly [submittedIntentBrand]: true;}

const retainedInputEdges = new WeakMap<RetainedTaskInputEdge, owner.ClientRetainedInputEdge>();
const retainedInputProducers = new WeakMap<RetainedInputProducer, owner.ClientRetainedInputProducer>();
const retainedInputIntents = new WeakMap<RetainedInputIntent, {producer: owner.ClientRetainedInputProducer; value: owner.RemoteRetainedInputIntent}>();
const retainedInputPlans = new WeakMap<RetainedInputPlan, owner.ClientValuesHostRetainedInputPlan>();
const retainedInputResults = new WeakMap<RetainedInputResult, owner.RemoteRetainedInputResult>();
const retainedInputCurrentQueries = new WeakMap<RetainedInputCurrentQuery, owner.ClientValuesHostRetainedInputQuery>();
const retainedInputCurrentReplies = new WeakMap<RetainedInputCurrentReply, owner.RemoteRetainedCurrentReply>();
const retainedTaskInputs = new WeakMap<RetainedTaskInput, owner.ClientValuesHostRetainedTaskInput>();
import {publicationAction} from './publication-action.mjs';

const environments = new WeakMap<CheckEnvironment, owner.CheckEnvironment>();
const publishedEnvironments = new WeakMap<PreparedPublishedEnvironment, {value: owner.PreparedPublishedQueryEnvironment; environment: CheckEnvironment; publicationWire: string}>();
const preparations = new WeakMap<PreparedProgram, owner.PreparedClientProgram>();
const sourcePreparations = new WeakMap<PreparedProgram | PreparedEffectProgram, {value: owner.ClientSourcePreparation; intent: SubmittedIntent; environment: CheckEnvironment; primaryResultRecipe: SourceProgramOriginals['primaryResultRecipe']}>();
const compilations = new WeakMap<ValuesCompilation, {value: owner.ClientValuesCompilation; prepared: PreparedProgram}>();
const taskCompilations = new WeakMap<TaskCompilation, {value: owner.ClientTaskCompilation; prepared: PreparedProgram}>();
const effectPreparations = new WeakMap<PreparedEffectProgram, owner.PreparedClientEffectComputation>();
const effectCompilations = new WeakMap<EffectCompilation, {value: owner.ClientEffectCompilation; prepared: PreparedEffectProgram}>();
const effectAllowedRuns = new WeakMap<AllowedEffectRun, {value: owner.ClientEffectAllowedRun; prepared: PreparedEffectProgram; compilation: EffectCompilation}>();
const effectPreviewIdentities = new WeakMap<EffectPreviewIdentity, {value: owner.EffectPreviewIdentity; memberCount: number}>();
const effectCheckpointBindings = new WeakMap<EffectReviewCheckpointBinding, {original: owner.SealedCheckpoint; allowed: AllowedEffectRun; definition: RunDefinition}>();
const effectMaterialOwners = new WeakMap<RestoredEffectRun, owner.ClientEffectRunMaterials>();
const issuedEffectMaterials = new WeakMap<IssuedEffectRunMaterials, owner.ClientEffectIssuedNormalizationMaterials>();
const requests = new WeakMap<RequestIdentity, owner.ClientRequestIdentity>();
const cancellationIdentities = new WeakMap<RunCancellationIdentity, owner.ClientCancellationIdentity>();
const submissionEpochs = new WeakMap<SubmissionEpoch, owner.SubmissionEpoch>();
const submittedIntents = new WeakMap<SubmittedIntent, owner.ClientSubmittedIntent>();
const admissions = new WeakMap<RunAdmission, {value: owner.RunPublicationAdmission; prepared: PreparedProgram}>();
const definitions = new WeakMap<RunDefinition, owner.PublicationContract>();
const publicationContracts = new WeakMap<PublicationContract['token'], owner.PublicationContract>();
type EffectFinalCustody = {
  value: owner.EffectfulFinalRunEvidence;
  original: EffectFinalOriginals;
  validatedPublication: owner.PublicationContract | undefined;
};
const publicationOriginals = new WeakMap<PublicationContract, Readonly<{
  value: owner.PublicationContract; cid: string; wire: string; effect?: EffectFinalCustody;
}>>();
const runEvidences = new WeakMap<RunEvidence['token'], owner.RunEvidenceValue>();
const originalRunPlans = new WeakMap<OriginalRunPlan, {original: StoredRunPlanOriginal; definitionCid: string; programCid: string; prepared: string; authorization: string}>();
const resultOccurrences = new WeakMap<ResultOccurrenceEvidence['token'], owner.ResultOrderingEvidence>();
const capturedSnapshots = new WeakMap<CapturedResultSnapshot, owner.CapturedResultSnapshot>();
const materialHolds = new WeakMap<ResultMaterialHolds, owner.ResultMaterialHolds>();
const profileKeys = new Set(['textTime', 'veca', 'rela', 'sga', 'tea',
  'calendar', 'textRank']);

function checked<Value>(result: owner.Result<Value>, code: string): Value {
  if (runtimeIsOk(result)) return runtimeField(result, 0) as Value;
  if (runtimeIsError(result)) {
    throw Object.assign(new Error(code, {cause: runtimeField(result, 0)}), {code});
  }
  throw Object.assign(new Error('InvalidRunHostOwnerResult'),
    {code: 'InvalidRunHostOwnerResult'});
}

// The original Map membership selects matching Values and Task compiler ports.
type CombinedParameters<Left extends readonly unknown[], Right extends readonly unknown[]> = {
  [Index in keyof Left]: Left[Index] | Right[Index & keyof Right];
};
type SelectedOwnerCall<Left extends (...args: never[]) => unknown, Right extends (...args: never[]) => unknown> =
  (...args: CombinedParameters<Parameters<Left>, Parameters<Right>>) => ReturnType<Left | Right>;

type CustodyMap = WeakMap<object, unknown>;
type CustodyKey<Map> = Map extends WeakMap<infer Key, unknown> ? Key : never;
type CustodyValue<Map> = Map extends WeakMap<object, infer Value> ? Value : never;

function handle<Map extends CustodyMap>(map: Map, value: CustodyValue<Map>, kind: string): CustodyKey<Map> {
  const token = Object.freeze({kind}) as unknown as CustodyKey<Map>;
  map.set(token, value);
  return token;
}

function requireHandle<Map extends CustodyMap>(map: Map, token: object | undefined): CustodyValue<Map> {
  const value = map.get(token as object);
  if (value === undefined) throw new TypeError('ForeignRunHostHandle');
  return value as CustodyValue<Map>;
}

/** Shared Result-generation hold decisions; physical CAS stays in the Host. */
export function beginResultMaterialHolds(bindingCid: string, materialGenerationCid: string): ResultMaterialHolds {
  return handle(materialHolds, deliveryResult(
    'clientValuesHostBeginResultMaterialHolds', bindingCid,
    materialGenerationCid), 'result-material-holds');
}

export function admitResultMaterialHolds(wire: string): ResultMaterialHolds {
  if (typeof wire !== 'string') throw new TypeError('InvalidMaterialHoldsWire');
  return handle(materialHolds, deliveryResult(
    'clientValuesHostAdmitResultMaterialHolds', wire),
  'result-material-holds');
}

export function resultMaterialHoldsWire(value: ResultMaterialHolds): string {
  return deliveryResult('clientValuesHostResultMaterialHoldsWire',
    requireHandle(materialHolds, value));
}

export function resultMaterialHoldsFacts(value: ResultMaterialHolds): Readonly<{bindingCid: string; materialGenerationCid: string;
    revision: number; reclaimable: boolean}> {
  const ownerValue = requireHandle(materialHolds, value);
  return Object.freeze({
    bindingCid: owner.clientValuesHostResultMaterialHoldsBinding(ownerValue),
    materialGenerationCid:
      owner.clientValuesHostResultMaterialHoldsGeneration(ownerValue),
    revision: owner.clientValuesHostResultMaterialHoldsRevision(ownerValue),
    reclaimable:
      owner.clientValuesHostResultMaterialHoldsReclaimable(ownerValue),
  });
}

export function prepareResultMaterialHoldsStep(value: ResultMaterialHolds, operation: 'add_consumer' | 'release_consumer' | 'begin_reader' |
    'end_reader' | 'stop_readers', identity: string): ResultMaterialHolds {
  if (!['add_consumer', 'release_consumer', 'begin_reader',
    'end_reader', 'stop_readers'].includes(operation) ||
    typeof identity !== 'string') {
    throw new TypeError('InvalidMaterialHoldsStep');
  }
  return handle(materialHolds, deliveryResult(
    'clientValuesHostPrepareResultMaterialHoldsStep',
    requireHandle(materialHolds, value), operation, identity),
  'result-material-holds');
}

function checkedProfileSelection(profiles: Parameters<typeof admitProfileSelection>[0], error: string) {
  if (profiles === null || typeof profiles !== 'object' ||
      Array.isArray(profiles)) {
    throw new TypeError(error);
  }
  let numericProfileCid;
  for (const [key, value] of Object.entries(profiles)) {
    if (key === 'numericProfileCid') {
      if (typeof value !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(value)) {
        throw new TypeError(error);
      }
      numericProfileCid = value;
    } else if (!profileKeys.has(key) || typeof value !== 'boolean') {
      throw new TypeError(error);
    }
  }
  return Object.freeze({
    textTime: (profiles as ProfileSelection).textTime === true,
    veca: (profiles as ProfileSelection).veca === true,
    rela: (profiles as ProfileSelection).rela === true,
    sga: (profiles as ProfileSelection).sga === true,
    tea: (profiles as ProfileSelection).tea === true,
    calendar: (profiles as ProfileSelection).calendar === true,
    textRank: (profiles as ProfileSelection).textRank === true,
    ...(numericProfileCid === undefined ? {} : {numericProfileCid}),
  });
}

/** Admit the existing profile contract and make omitted selections explicit. */
export function admitProfileSelection(profiles: unknown): Readonly<Required<Omit<ProfileSelection, 'numericProfileCid'>> &
    Pick<ProfileSelection, 'numericProfileCid'>> {
  return checkedProfileSelection(profiles, 'InvalidRunHostProfileSelection');
}

export function admitEnvironment(body: string, evidenceBundleCid: string, profiles: ProfileSelection): CheckEnvironment {
  if (typeof body !== 'string' || typeof evidenceBundleCid !== 'string') {
    throw new TypeError('InvalidRunHostEnvironment');
  }
  const selected = checkedProfileSelection(profiles, 'InvalidRunHostEnvironment');
  const value = owner.clientValuesHostEnvironment(body, evidenceBundleCid,
    selected.textTime, selected.veca, selected.rela, selected.sga,
    selected.tea, selected.calendar, selected.textRank, selected.numericProfileCid);
  if (value === undefined) {
    throw Object.assign(new Error('RunHostEnvironmentRejected'),
      {code: 'RunHostEnvironmentRejected'});
  }
  return handle(environments, value, 'check-environment');
}

/** Retain only static metadata under its original admitted Environment. */
export function preparePublishedEnvironment(environment: CheckEnvironment, publicationWire: string): PreparedPublishedEnvironment {
  if (typeof publicationWire !== 'string') throw new TypeError('InvalidRunHostSourcePublication');
  if (typeof owner.clientValuesHostPreparePublishedEnvironment !== 'function') {
    throw new Error('RunHostPreparedEnvironmentUnavailable');
  }
  const value = checked(owner.clientValuesHostPreparePublishedEnvironment(
    requireHandle(environments, environment), publicationWire),
  'RunHostPublishedEnvironmentRejected');
  return handle(publishedEnvironments, {value, environment, publicationWire},
    'prepared-published-environment');
}

function requirePublishedEnvironment(prepared: PreparedPublishedEnvironment | undefined,
  environment: CheckEnvironment, publicationWire?: string) {
  if (prepared === undefined) return undefined;
  const original = requireHandle(publishedEnvironments, prepared);
  if (original.environment !== environment || publicationWire !== undefined &&
      original.publicationWire !== publicationWire) {
    throw new TypeError('ForeignRunHostPublishedEnvironment');
  }
  return original.value;
}

/** A nominal/full-wire join only; never current authorization or custody. */
export function publishedEnvironmentMatches(prepared: PreparedPublishedEnvironment, environment: CheckEnvironment, publicationWire: string): boolean {
  const original = requireHandle(publishedEnvironments, prepared);
  requireHandle(environments, environment);
  return original.environment === environment && original.publicationWire === publicationWire;
}

export function prepare(document: string, format: 'json' | 'yaml', environment: CheckEnvironment, parametersWire?: string, publishedEnvironment?: PreparedPublishedEnvironment): PreparedProgram {
  if (typeof document !== 'string' || !['json', 'yaml'].includes(format) ||
      parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new TypeError('InvalidRunHostPreparation');
  }
  const value = checked(owner.clientValuesHostPrepare(document, format,
    requireHandle(environments, environment), parametersWire,
    requirePublishedEnvironment(publishedEnvironment, environment)),
  'RunHostPreparationRejected');
  return handle(preparations, value, 'prepared-program');
}

/** Select the existing preparation Owner from one ordinary parsed Program. */
export function prepareProgram(document: string, format: 'json' | 'yaml', environment: CheckEnvironment, parametersWire?: string, publishedEnvironment?: PreparedPublishedEnvironment): Readonly<{kind: 'effect_free'; prepared: PreparedProgram}> |
  Readonly<{kind: 'effect'; prepared: PreparedEffectProgram}> {
  if (typeof document !== 'string' || !['json', 'yaml'].includes(format) ||
      parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new TypeError('InvalidRunHostPreparation');
  }
  const selected = checked(owner.clientValuesHostPrepareProgram(document, format,
    requireHandle(environments, environment), parametersWire,
    requirePublishedEnvironment(publishedEnvironment, environment)), 'RunHostProgramPreparationRejected');
  const kind = owner.clientValuesHostProgramPreparationKind(selected);
  if (kind === 'effect_free') {
    const value = owner.clientValuesHostProgramPreparationEffectFree(selected);
    if (value === undefined) throw new Error('InvalidRunHostOwnerResult');
    return Object.freeze({kind, prepared: handle(preparations, value, 'prepared-program')});
  }
  if (kind === 'effect') {
    const value = owner.clientValuesHostProgramPreparationEffect(selected);
    if (value === undefined) throw new Error('InvalidRunHostOwnerResult');
    return Object.freeze({kind, prepared: handle(effectPreparations, value, 'prepared-effect-program')});
  }
  throw new Error('InvalidRunHostOwnerResult');
}

/** One original submitted source and trusted installation publication. */
export function prepareSourceProgram(intent: SubmittedIntent, environment: CheckEnvironment, publicationWire: string, publishedEnvironment?: PreparedPublishedEnvironment): PreparedSourceProgram {
  return prepareSourceProgramOriginal(intent, environment, publicationWire,
    'public-main', publishedEnvironment);
}

function prepareSourceProgramOriginal(intent: SubmittedIntent, environment: CheckEnvironment,
  publicationWire: string, primaryResultRecipe: SourceProgramOriginals['primaryResultRecipe'], publishedEnvironment?: PreparedPublishedEnvironment) {
  if (typeof publicationWire !== 'string') throw new TypeError('InvalidRunHostSourcePublication');
  const originalIntent = requireHandle(submittedIntents, intent);
  const originalEnvironment = requireHandle(environments, environment);
  const prepare = primaryResultRecipe === undefined
    ? owner.clientValuesHostPrepareSourceProgram : owner.clientValuesHostPreparePublicSourceProgram;
  const value = checked(Reflect.apply(prepare, owner, [originalIntent,
    originalEnvironment, publicationWire,
    requirePublishedEnvironment(publishedEnvironment, environment, publicationWire)]),
  'RunHostSourcePreparationRejected');
  const kind = owner.clientValuesHostSourceProgramKind(value);
  const raw = kind === 'effect_free' ? owner.clientValuesHostSourceProgramPure(value)
    : kind === 'effect' ? owner.clientValuesHostSourceProgramEffect(value): undefined;
  if (raw === undefined) throw new Error('InvalidRunHostOwnerResult');
  const prepared = handle(kind === 'effect_free' ? preparations : effectPreparations,
    raw, kind === 'effect_free' ? 'prepared-program' : 'prepared-effect-program');
  sourcePreparations.set(prepared, {value, intent, environment, primaryResultRecipe});
  // The discriminator chooses the corresponding preparation issuer immediately above.
  return Object.freeze({kind, prepared, originalIntent: intent}) as PreparedSourceProgram;
}

/** Retained original DATA for authenticated Host storage, never authority. */
export function sourceProgramOriginals(prepared: PreparedProgram | PreparedEffectProgram): SourceProgramOriginals {
  const original = sourcePreparations.get(prepared);
  if (original === undefined) throw new TypeError('ForeignRunHostSourcePreparation');
  const facts = owner.clientValuesHostSourceProgramOriginals(original.value);
  if (!Array.isArray(facts) || facts.length !== 4 || facts.some(x => typeof x !== 'string')) {
    throw new Error('InvalidRunHostOwnerResult');
  }
  return Object.freeze({intentWire: facts[0], intentCid: facts[1],
    environmentCid: facts[2], publicationWire: facts[3],
    ...(original.primaryResultRecipe === undefined ? {} :
      {primaryResultRecipe: original.primaryResultRecipe})});
}

/** Original lowerer projection for the existing JSON Run material codec. */
export function sourceProgramMaterialInput(prepared: PreparedProgram | PreparedEffectProgram, environmentWire: string): SourceFreeRunMaterialsInput {
  const original = sourcePreparations.get(prepared);
  if (original === undefined) throw new TypeError('ForeignRunHostSourcePreparation');
  if (typeof environmentWire !== 'string') throw new TypeError('InvalidRunHostRunMaterialsInput');
  const document = owner.clientValuesHostSourceProgramDocument(original.value);
  const parametersWire = owner.clientValuesHostSourceProgramParameters(original.value);
  if (typeof document !== 'string' || parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new Error('InvalidRunHostOwnerResult');
  }
  return Object.freeze({format: 'json', document, environment: original.environment,
    environmentWire, ...(parametersWire === undefined ? {} : {parametersWire})});
}

/** Exact authored input projection for saved-source correspondence. */
export function sourceProgramSourceInput(prepared: PreparedProgram | PreparedEffectProgram): Readonly<{
  document: string; format: string; parametersWire?: string; parameterDeclarationsWire?: string}> {
  const original = sourcePreparations.get(prepared);
  if (original === undefined) throw new TypeError('ForeignRunHostSourcePreparation');
  const fields = owner.clientValuesHostSourceProgramInput(original.value);
  const parametersWire = owner.clientValuesHostSourceProgramParameters(original.value);
  const parameterDeclarationsWire = owner.clientValuesHostSourceProgramDeclarations(original.value);
  if (!Array.isArray(fields) || fields.length !== 2 || fields.some(x => typeof x !== 'string') ||
      [parametersWire, parameterDeclarationsWire].some(x => x !== undefined && typeof x !== 'string')) {
    throw new Error('InvalidRunHostOwnerResult');
  }
  return Object.freeze({document: fields[0], format: fields[1],
    ...(parametersWire === undefined ? {} : {parametersWire}),
    ...(parameterDeclarationsWire === undefined ? {} : {parameterDeclarationsWire})});
}

/** Re-admit saved originals; the Host still verifies current custody and Run. */
export function restoreSourceProgram(originals: SourceProgramOriginals, environment: CheckEnvironment, publishedEnvironment?: PreparedPublishedEnvironment): PreparedSourceProgram {
  const keys: (keyof SourceProgramOriginals)[] = ['intentWire', 'intentCid', 'environmentCid', 'publicationWire'];
  const recipe = originals === null || typeof originals !== 'object' ? undefined
    : Object.getOwnPropertyDescriptor(originals, 'primaryResultRecipe');
  if (recipe !== undefined) {
    if (!Object.hasOwn(recipe, 'value') || recipe.value !== 'public-main') {
      throw new TypeError('InvalidRunHostSourceOriginals');
    }
    keys.push('primaryResultRecipe');
  }
  if (originals === null || typeof originals !== 'object' || Array.isArray(originals) ||
      Reflect.ownKeys(originals).length !== keys.length || keys.some(key => {
        const d = Object.getOwnPropertyDescriptor(originals, key);
        return d === undefined || !Object.hasOwn(d, 'value') || typeof d.value !== 'string';
      })) throw new TypeError('InvalidRunHostSourceOriginals');
  const intent = prepareSubmittedIntent(originals.intentWire,
    {maxWireBytes: 1048576, maxNodes: 65536, maxDepth: 64});
  // Absence means the exact historical configured-primary recipe. Never
  // upgrade a saved source preparation merely because new public input uses
  // main. Run restoration independently checks its saved request/materials.
  const selected = prepareSourceProgramOriginal(intent, environment,
    originals.publicationWire, recipe?.value, publishedEnvironment);
  const actual = sourceProgramOriginals(selected.prepared);
  if (keys.some(key => actual[key] !== originals[key])) throw new TypeError('ForeignRunHostSourceOriginals');
  return selected;
}

export function prepareSourceRequest(prepared: PreparedProgram | PreparedEffectProgram, intent: SubmittedIntent, authorityScopeCid: string, requestId: string): RequestIdentity {
  const original = sourcePreparations.get(prepared);
  if (original === undefined || original.intent !== intent) throw new TypeError('ForeignRunHostSourcePreparation');
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') throw new TypeError('InvalidRunHostRequest');
  return handle(requests, checked(owner.clientValuesHostSourceProgramRequest(original.value,
    requireHandle(submittedIntents, intent), requireHandle(environments, original.environment),
    authorityScopeCid, requestId), 'RunHostRequestRejected'), 'request-identity');
}

/** Restore only a request that belongs to this original source preparation. */
export function admitSourceRequestFields(prepared: PreparedProgram | PreparedEffectProgram, intent: SubmittedIntent, fields: RequestFields): RequestIdentity {
  const retained = admitRequestFields(fields);
  const current = prepareSourceRequest(prepared, intent, fields.authorityScopeCid, fields.requestId);
  if (requestRelation(current, retained) !== 'same_request') {
    throw Object.assign(new Error('RunHostRequestRecordRejected'), {code: 'RunHostRequestRecordRejected'});
  }
  return retained;
}

export function compileValues(prepared: PreparedProgram): ValuesCompilation {
  const value = checked(owner.clientValuesHostCompile(
    requireHandle(preparations, prepared)), 'RunHostCompilationRejected');
  return handle(compilations, {value, prepared}, 'values-compilation');
}

export function compileTasks(prepared: PreparedProgram): TaskCompilation {
  const value = checked(owner.clientValuesHostCompileTasks(
    requireHandle(preparations, prepared)), 'RunHostTaskCompilationRejected');
  return handle(taskCompilations, {value, prepared}, 'task-compilation');
}

/** Static Effect closure; no acquisition, approval or physical apply. */
export function prepareEffect(document: string, format: 'json' | 'yaml', environment: CheckEnvironment, parametersWire?: string, publishedEnvironment?: PreparedPublishedEnvironment): PreparedEffectProgram {
  if (typeof document !== 'string' || !['json', 'yaml'].includes(format) ||
      parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new TypeError('InvalidRunHostPreparation');
  }
  return handle(effectPreparations, checked(owner.clientValuesHostPrepareEffect(
    document, format, requireHandle(environments, environment), parametersWire,
    requirePublishedEnvironment(publishedEnvironment, environment)),
  'RunHostEffectPreparationRejected'), 'prepared-effect-program');
}

export function compileEffect(prepared: PreparedEffectProgram, options: Readonly<{normalizationProfile?: 'completion-free'}> = {}): EffectCompilation {
  if (options === null || typeof options !== 'object' ||
      options.normalizationProfile !== undefined &&
      options.normalizationProfile !== 'completion-free') {
    throw new TypeError('InvalidRunHostEffectCompilationProfile');
  }
  const value = checked(owner.clientValuesHostCompileEffect(
    requireHandle(effectPreparations, prepared),
    options.normalizationProfile === 'completion-free'), 'RunHostEffectCompilationRejected');
  return handle(effectCompilations, {value, prepared}, 'effect-compilation');
}

function effectCompilationFor(prepared: PreparedEffectProgram, compilation: EffectCompilation) {
  const retained = requireHandle(effectCompilations, compilation);
  if (retained.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  return retained.value;
}

/** Checked counts only; this does not select or schedule an executable task. */
export function effectExecutionShape(prepared: PreparedEffectProgram, compilation: EffectCompilation): Readonly<{taskCount: number; acquisitionCount: number; effectCount: number}> {
  const counts = owner.clientValuesHostEffectShape(effectCompilationFor(prepared, compilation));
  if (!Array.isArray(counts) || counts.length !== 3 ||
      counts.some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new Error('InvalidRunHostEffectExecutionProjection');
  }
  return Object.freeze({taskCount: counts[0], acquisitionCount: counts[1],
    effectCount: counts[2]});
}

/** Original checked dispatch coordinates, not execution or approval permits. */
export function effectTaskKeys(prepared: PreparedEffectProgram, compilation: EffectCompilation): readonly string[] {
  const keys = checked(owner.clientValuesHostEffectTaskKeys(
    effectCompilationFor(prepared, compilation)), 'RunHostTaskKeysRejected');
  if (!Array.isArray(keys) || keys.some(key => typeof key !== 'string') ||
      new Set(keys).size !== keys.length) throw new Error('InvalidRunHostTaskKeyProjection');
  return Object.freeze([...keys]);
}

/** Result inventory owned by the original Effect computation. */
export function effectResultDefinitions(prepared: PreparedEffectProgram, compilation: EffectCompilation): readonly Readonly<{name: string; cid: string; wire: string}>[] {
  const value = effectCompilationFor(prepared, compilation);
  const fields = checked(owner.clientValuesHostEffectResultDefinitions(value),
    'RunHostResultInventoryRejected');
  const names = owner.clientValuesHostEffectResultNames(value);
  if (!Array.isArray(fields) || fields.length !== names.length * 3 ||
      !fields.every(field => typeof field === 'string')) {
    throw new Error('InvalidRunHostResultInventory');
  }
  return Object.freeze(names.map((name, index) => {
    if (fields[index * 3] !== name) throw new Error('InvalidRunHostResultInventory');
    return Object.freeze({name, cid: fields[index * 3 + 1], wire: fields[index * 3 + 2]});
  }));
}

export function effectResultSchema(prepared: PreparedEffectProgram, compilation: EffectCompilation, resultName: string): Readonly<{
    cid: string; wire: string; fields: readonly string[]}> {
  const value = effectCompilationFor(prepared, compilation);
  if (typeof resultName !== 'string') throw new TypeError('InvalidRunHostResultSelection');
  const result = owner.clientValuesHostEffectResultNames(value).indexOf(resultName);
  if (result < 0) throw new RangeError('UnknownRunHostResult');
  const facts = checked(owner.clientValuesHostEffectResultSchema(value, result),
    'RunHostResultSchemaRejected');
  if (!Array.isArray(facts) || facts.length < 2 ||
      !facts.every(field => typeof field === 'string') ||
      !/^sha256:[0-9a-f]{64}$/u.test(facts[0])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  const fields = Object.freeze(facts.slice(2));
  // JavaScript enumerates integer-like keys numerically; the Owner uses UTF-16.
  const schemaFields = Object.keys(JSON.parse(facts[1])).sort();
  if (schemaFields.length !== fields.length ||
      schemaFields.some((field, index) => field !== fields[index])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  return Object.freeze({cid: facts[0], wire: facts[1], fields});
}

/** Exact original Catalog evidence, never a read grant or Effect approval. */
export function effectSourceEvidenceFacts(prepared: PreparedEffectProgram, compilation: EffectCompilation, stage: number, sourceIndex: number): Readonly<{
    sourceRef: string; sourceContractCid: string; carrierSchemaContractCid: string;
    sourceDataPolicyCid: string; dataClassification: string; sourceViewContractCid: string;
  }> | undefined {
  const value = effectCompilationFor(prepared, compilation);
  if (![stage, sourceIndex].every(index => Number.isSafeInteger(index) &&
      index >= 0 && index <= 2147483647)) {
    throw new TypeError('InvalidRunHostSourceSelection');
  }
  const option = owner.clientValuesHostEffectSourceEvidenceFacts(value, stage, sourceIndex);
  if (runtimeIsBoxedNone(option)) return undefined;
  if (!runtimeIsBoxedSome(option)) throw new Error('InvalidRunHostSourceEvidenceProjection');
  const facts = runtimeField(option, 0);
  if (!Array.isArray(facts) || facts.length !== 6 ||
      facts.some(field => typeof field !== 'string')) {
    throw new Error('InvalidRunHostSourceEvidenceProjection');
  }
  return Object.freeze({sourceRef: facts[0], sourceContractCid: facts[1],
    carrierSchemaContractCid: facts[2], sourceDataPolicyCid: facts[3],
    dataClassification: facts[4], sourceViewContractCid: facts[5]});
}

export function privateEffectCompilationWires(compilation: EffectCompilation): Readonly<{boundTemplate: string; compiledPlan: string}> {
  const {value} = requireHandle(effectCompilations, compilation);
  return Object.freeze({boundTemplate: owner.clientValuesHostEffectTemplateWire(value),
    compiledPlan: owner.clientValuesHostEffectCompiledPlanWire(value)});
}

/** Current Host authorization precedes this call; Effect approval is separate. */
export function issueAllowedEffectRun(prepared: PreparedEffectProgram, compilation: EffectCompilation, {
  executionContextCid, hostPolicyCid, expiresAt,
}: Readonly<{executionContextCid: string;
    hostPolicyCid: string; expiresAt: string}>): AllowedEffectRun {
  if ([executionContextCid, hostPolicyCid, expiresAt]
    .some(value => typeof value !== 'string')) throw new TypeError('InvalidRunHostEvidence');
  const value = checked(owner.clientValuesHostIssueAllowedEffectRun(
    effectCompilationFor(prepared, compilation), executionContextCid,
    hostPolicyCid, expiresAt), 'RunHostEffectAdmissionRejected');
  return handle(effectAllowedRuns, {value, prepared, compilation}, 'allowed-effect-run');
}

export function privateEffectRunEvidence(allowed: AllowedEffectRun): Readonly<{preparedInvocationWire: string; authorizationWire: string}> {
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return Object.freeze({preparedInvocationWire: owner.clientValuesHostAllowedEffectPreparedWire(value),
    authorizationWire: owner.clientValuesHostAllowedEffectAuthorizationWire(value)});
}

export function issueEffectRunDefinition(allowed: AllowedEffectRun, scopeId: string, runId: string, createdAt: string, validUntil: string): RunDefinition {
  if ([scopeId, runId, createdAt, validUntil].some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return handle(definitions, checked(owner.clientValuesHostIssueEffectRunDefinition(
    value, scopeId, runId, createdAt, validUntil), 'RunHostEffectDefinitionRejected'), 'run-definition');
}

/** Project the original Effect materials using the existing bounded codec. */
export function issueEffectRunMaterials(allowed: AllowedEffectRun, definition: RunDefinition, retained: Readonly<{format: 'json'; document: string;
    environment: CheckEnvironment; environmentWire: string;
    parametersWire?: string}>, request?: RequestIdentity): string {
  validateRunMaterialsInput(retained);
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return checked(owner.clientValuesHostIssueEffectRunMaterials(value,
    requireHandle(definitions, definition), requireHandle(environments, retained.environment),
    retained.environmentWire, retained.document, retained.parametersWire,
    request === undefined ? undefined : requireHandle(requests, request)), 'RunHostEffectRunMaterialsRejected');
}

/** Issue original materials and checked normalization without replacement inputs.
 * This finite profile refuses actual completions and unsupported operations. */
export function issuePreparedEffectRunMaterials(allowed: AllowedEffectRun, definition: RunDefinition, request?: RequestIdentity): IssuedEffectRunMaterials {
  const {value, prepared} = requireHandle(effectAllowedRuns, allowed);
  const issued = checked(owner.clientValuesHostIssuePreparedEffectRunMaterials(
    requireHandle(effectPreparations, prepared), value,
    requireHandle(definitions, definition),
    request === undefined ? undefined : requireHandle(requests, request)),
  'RunHostEffectOriginalMaterialsRejected');
  const material = Object.freeze({wire: owner.clientValuesHostIssuedEffectRunMaterialsWire(issued)}) as IssuedEffectRunMaterials;
  issuedEffectMaterials.set(material, issued);
  return material;
}

/** Bind the same live issuer originals; no preparation, compilation or approval.
 * The existing Common Owner verifies the Run, request and normalization custody. */
export function bindPreparedEffectRunMaterials(allowed: AllowedEffectRun, definition: RunDefinition, issued: IssuedEffectRunMaterials, request: RequestIdentity): RestoredEffectRun {
  const original = requireHandle(effectAllowedRuns, allowed);
  const bound = checked(owner.clientValuesHostBindPreparedEffectRunMaterials(
    original.value, requireHandle(definitions, definition),
    requireHandle(issuedEffectMaterials, issued), requireHandle(requests, request)),
  'RunHostEffectOriginalMaterialsRejected');
  const materials = Object.freeze({prepared: original.prepared,
    compilation: original.compilation, allowed, definition, request});
  effectMaterialOwners.set(materials, bound);
  return materials;
}

/** Restore saved journal bytes from this exact material admission; no approval. */
export function restoreEffectRunNormalization(materials: RestoredEffectRun): RunEvidence {
  return runEvidence(checked(owner.clientValuesHostRestoreEffectRunNormalization(
    requireHandle(effectMaterialOwners, materials)), 'RunHostEffectNormalizationRejected'));
}

/** Saved evidence is re-admitted, not reissued with a fresh policy or lifetime. */
export function admitEffectRunMaterials(wire: string, definitionCid: string, profiles: ProfileSelection, original?: IssuedEffectRunMaterials, expectedRequest?: RequestIdentity, sourcePrepared?: PreparedEffectProgram): RestoredEffectRun {
  if (typeof wire !== 'string' || typeof definitionCid !== 'string') {
    throw new TypeError('InvalidRunHostRunMaterialsInput');
  }
  const selected = checkedProfileSelection(profiles, 'InvalidRunHostProfiles');
  const source = sourcePrepared === undefined ? undefined : sourcePreparations.get(sourcePrepared);
  if (sourcePrepared !== undefined && (source === undefined || !effectPreparations.has(sourcePrepared))) {
    throw new TypeError('ForeignRunHostSourcePreparation');
  }
  const restored = checked(owner.clientValuesHostAdmitEffectRunMaterials(wire,
    definitionCid, selected.textTime, selected.veca, selected.rela, selected.sga,
    selected.tea, selected.calendar, selected.textRank,
    original === undefined ? undefined : requireHandle(issuedEffectMaterials, original),
    expectedRequest === undefined ? undefined : requireHandle(requests, expectedRequest),
    source?.value, selected.numericProfileCid), 'RunHostEffectRestorationRejected');
  const prepared = handle(effectPreparations, owner.clientValuesHostRestoredEffectPrepared(restored), 'prepared-effect-program');
  if (source !== undefined) sourcePreparations.set(prepared, source);
  const originalRequest = owner.clientValuesHostRestoredEffectRequest(restored);
  if (!Array.isArray(originalRequest) || originalRequest.length > 1) throw new Error('InvalidRunHostOriginalRequest');
  const request = originalRequest.length === 1 ? handle(requests, originalRequest[0], 'request-identity'): undefined;
  const compilation = handle(effectCompilations,
    {value: owner.clientValuesHostRestoredEffectCompilation(restored), prepared}, 'effect-compilation');
  const materials = Object.freeze({prepared, ...(request === undefined ? {} : {request}), compilation,
    allowed: handle(effectAllowedRuns,
      {value: owner.clientValuesHostRestoredEffectAllowed(restored), prepared, compilation}, 'allowed-effect-run'),
    definition: handle(definitions, owner.clientValuesHostRestoredEffectDefinition(restored), 'run-definition')});
  effectMaterialOwners.set(materials, restored);
  return materials;
}

/** Original policy/Run expiry check only; current Host authority is independent. */
export function effectRunStartCurrent(allowed: AllowedEffectRun, definition: RunDefinition, at: string): boolean {
  if (typeof at !== 'string') throw new TypeError('InvalidRunHostCurrentTime');
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return owner.clientValuesHostEffectStartCurrent(value, requireHandle(definitions, definition), at);
}

/** Original Run/unit/window binding only. Native custody, current authority,
 * waiting commit and Effect approval must be confirmed independently. */
export function effectReviewCheckpointBinding(allowed: AllowedEffectRun, definition: RunDefinition, wire: string): EffectReviewCheckpointBinding {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostCheckpointWire');
  const {value} = requireHandle(effectAllowedRuns, allowed);
  const original = checked(owner.clientValuesHostAdmitEffectCheckpointBinding(value,
    requireHandle(definitions, definition), wire), 'RunHostEffectCheckpointBindingRejected');
  const fields = checked(owner.clientValuesHostEffectCheckpointBindingFields(original),
    'RunHostEffectCheckpointBindingRejected');
  if (!Array.isArray(fields) || fields.length !== 8 ||
      fields.some(field => typeof field !== 'string') ||
      [0, 4, 5, 6, 7].some(index => !/^sha256:[0-9a-f]{64}$/u.test(fields[index]))) {
    throw new Error('InvalidRunHostCheckpointBinding');
  }
  const binding = Object.freeze({checkpointCid: fields[0], checkpointWire: fields[1],
    runId: fields[2], unitId: fields[3], runDefinitionCid: fields[4],
    previewCid: fields[5], reviewProjectionCid: fields[6], continuationCid: fields[7]}) as EffectReviewCheckpointBinding;
  // Only this returned binding retains its nominal Checkpoint and exact
  // original roots. It is neither a persistence receipt nor current authority.
  effectCheckpointBindings.set(binding, {original, allowed, definition});
  return binding;
}

/** Pure same-original facts; helpers and awaits do not re-admit the wire.
 * Restored operations must obtain their own original binding. */
export function effectReviewCheckpointBindingFacts(binding: EffectReviewCheckpointBinding, allowed: AllowedEffectRun, definition: RunDefinition): EffectReviewCheckpointBinding {
  const original = effectCheckpointBindings.get(binding);
  if (original === undefined || original.allowed !== allowed ||
      original.definition !== definition) throw new TypeError('ForeignRunHostCheckpointBinding');
  return binding;
}

/** Original authoring/Preview binding through the same Common Checkpoint owner.
 * This historical DATA is not current permission or an outcome/Store ACK. */
export function effectReviewCheckpointPreview(binding: EffectReviewCheckpointBinding, allowed: AllowedEffectRun, definition: RunDefinition,
  storedWire: string, previewWire: string, limits: PublicationLimits): EffectPreviewIdentity {
  effectReviewCheckpointBindingFacts(binding, allowed, definition);
  if (typeof storedWire !== 'string' || typeof previewWire !== 'string') {
    throw new TypeError('InvalidRunHostCheckpointPreviewInput');
  }
  const {original} = effectCheckpointBindings.get(binding)!;
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(owner.clientValuesHostAdmitEffectCheckpointPreview(original,
    requireHandle(effectAllowedRuns, allowed).value, requireHandle(definitions, definition),
    storedWire, previewWire, maxWireBytes, maxNodes, maxDepth),
  'RunHostEffectCheckpointPreviewRejected');
  return handle(effectPreviewIdentities, {value,
    memberCount: owner.clientValuesHostEffectPreviewMemberCount(value)},
  'effect-preview-identity');
}

/** Same original plus actual stored bytes, through the existing waiting writer.
 * Physical read/revision/current gates remain with the restoration operation. */
export function effectReviewCheckpointWaitingState(binding: EffectReviewCheckpointBinding, allowed: AllowedEffectRun, definition: RunDefinition,
  storedWire: string, updatedAt: string, declaredResults: readonly string[]): string {
  effectReviewCheckpointBindingFacts(binding, allowed, definition);
  const {original} = effectCheckpointBindings.get(binding)!;
  if (typeof storedWire !== 'string' || typeof updatedAt !== 'string') {
    throw new TypeError('InvalidRunHostCheckpointWaitingInput');
  }
  const results = effectProjectionArray(declaredResults, 65536);
  let textUnits = 0;
  for (const name of results) {
    if (typeof name !== 'string') throw new TypeError('InvalidRunHostCheckpointWaitingInput');
    textUnits += name.length;
    // A necessary lower bound only; Common meters the complete emitted wire.
    if (textUnits > 1048576) throw new TypeError('InvalidRunHostCheckpointWaitingInput');
  }
  return checked(owner.clientValuesHostEffectCheckpointWaitingState(original,
    storedWire, updatedAt, results), 'RunHostEffectCheckpointWaitingRejected');
}

/** Same original review plus complete authenticated receipt DATA. Journal
 * custody/current/CAS and physical outcomes remain the caller's obligations. */
export function effectReviewCheckpointReconciliationState(binding: EffectReviewCheckpointBinding, allowed: AllowedEffectRun, definition: RunDefinition,
  storedWire: string, previewWire: string, invocationWire: string, setReceiptWire: string, memberReceiptWires: readonly string[],
  updatedAt: string, declaredResults: readonly string[]): string {
  effectReviewCheckpointBindingFacts(binding, allowed, definition);
  const {original} = effectCheckpointBindings.get(binding)!;
  const wires = [storedWire, previewWire, invocationWire, setReceiptWire, updatedAt];
  if (wires.some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostCheckpointReconciliationInput');
  }
  const snapshot = (value: readonly string[]) => {
    if (!Array.isArray(value)) {
      throw new TypeError('InvalidRunHostCheckpointReconciliationInput');
    }
    const length = value.length;
    if (!Number.isSafeInteger(length) || length < 0 || length > 65536) {
      throw new TypeError('InvalidRunHostCheckpointReconciliationInput');
    }
    const result = [];
    for (let index = 0; index < length; index++) {
      const field = Object.getOwnPropertyDescriptor(value, String(index));
      if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') {
        throw new TypeError('InvalidRunHostCheckpointReconciliationInput');
      }
      result.push(field.value);
    }
    return result;
  };
  const members = snapshot(memberReceiptWires), results = snapshot(declaredResults);
  // Necessary lower bound only. Common meters UTF-8, complete schemas and the
  // emitted state; this guard does not certify any receipt or physical fact.
  let textUnits = 0;
  for (const text of [...wires, ...members, ...results]) {
    textUnits += text.length;
    if (textUnits > 1048576) throw new TypeError('InvalidRunHostCheckpointReconciliationInput');
  }
  return checked(owner.clientValuesHostEffectCheckpointReconciliationState(original,
    requireHandle(effectAllowedRuns, allowed).value, requireHandle(definitions, definition),
    storedWire, previewWire, invocationWire, setReceiptWire, members, updatedAt, results),
  'RunHostEffectCheckpointReconciliationRejected');
}

/** Pure confirmed-cancellation DATA for this same original review. The Host
 * retains every whole-Run no-grant/stop/publication/current/CAS obligation. */
export function effectReviewCheckpointCancelledState(binding: EffectReviewCheckpointBinding, allowed: AllowedEffectRun, definition: RunDefinition,
  storedWire: string, updatedAt: string, declaredResults: readonly string[]): string {
  effectReviewCheckpointBindingFacts(binding, allowed, definition);
  const {original} = effectCheckpointBindings.get(binding)!;
  if (typeof storedWire !== 'string' || typeof updatedAt !== 'string' ||
      !Array.isArray(declaredResults)) {
    throw new TypeError('InvalidRunHostCheckpointCancelledInput');
  }
  const length = declaredResults.length;
  if (!Number.isSafeInteger(length) || length < 0 || length > 65536) {
    throw new TypeError('InvalidRunHostCheckpointCancelledInput');
  }
  const names = []; let textUnits = 0;
  for (let index = 0; index < length; index++) {
    const field = Object.getOwnPropertyDescriptor(declaredResults, String(index));
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') {
      throw new TypeError('InvalidRunHostCheckpointCancelledInput');
    }
    names.push(field.value); textUnits += field.value.length;
    if (textUnits > 1048576) throw new TypeError('InvalidRunHostCheckpointCancelledInput');
  }
  return checked(owner.clientValuesHostEffectCheckpointCancelledState(original,
    requireHandle(effectAllowedRuns, allowed).value, requireHandle(definitions, definition),
    storedWire, updatedAt, names), 'RunHostEffectCheckpointCancelledRejected');
}

/** Original checked member IDs, not Source grants or Effect authority. */
export function effectReviewCheckpointMembers(allowed: AllowedEffectRun, definition: RunDefinition, wire: string): readonly string[] {
  if (typeof wire !== 'string' || wire.length > 65536 || new TextEncoder().encode(wire).length > 65536) {
    throw new TypeError('InvalidRunHostCheckpointWire');
  }
  const {value} = requireHandle(effectAllowedRuns, allowed);
  const members = checked(owner.clientValuesHostEffectCheckpointMembers(value,
    requireHandle(definitions, definition), wire), 'RunHostEffectCheckpointMembersRejected');
  if (!Array.isArray(members) || members.length === 0 || members.length > 64 ||
      members.some(value => typeof value !== 'string' || value.length === 0) ||
      new Set(members).size !== members.length) throw new Error('InvalidRunHostCheckpointMembers');
  return Object.freeze([...members]);
}

/** Original Effect caller; capture is not a newly submitted input Artifact. */
export function prepareEffectRequest(prepared: PreparedEffectProgram, compilation: EffectCompilation, authorityScopeCid: string, requestId: string): RequestIdentity {
  effectCompilationFor(prepared, compilation);
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) return prepareSourceRequest(prepared, source.intent, authorityScopeCid, requestId);
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') {
    throw new TypeError('InvalidRunHostRequest');
  }
  const value = checked(owner.clientValuesHostEffectRequestIdentity(
    requireHandle(effectPreparations, prepared), authorityScopeCid, requestId),
  'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

/** Logical Source binding from the original checked Effect graph, no I/O. */
export function effectSourceInputBinding(compilation: EffectCompilation, request?: RequestIdentity): string {
  const {value} = requireHandle(effectCompilations, compilation);
  return checked(owner.clientValuesHostEffectSourceInputBinding(value,
    request === undefined ? undefined : requireHandle(requests, request)),
    'RunHostEffectSourceBindingRejected');
}

function effectSiteSelection(selection: ValuesSiteSelection) {
  if (selection === null || typeof selection !== 'object' || Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !== [...siteSelectionKeys].sort().join('\0')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  // Capture once: validation and the ABI must consume exactly the same values.
  const args = siteSelectionKeys.map(key => selection[key]) as [
    number, string, string, number, string, string, string, string, string, string, string, string
  ];
  const [taskAttempt, , , siteGeneration] = args;
  if (!Number.isSafeInteger(taskAttempt) || taskAttempt <= 0 ||
      taskAttempt > 2147483647 ||
      !Number.isSafeInteger(siteGeneration) || siteGeneration < 0 ||
      siteGeneration > 2147483647 ||
      args.some((value, index) => index !== 0 && index !== 3 && typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  return args;
}

/** The Host saves the original envelope before the existing Coordinator sends. */
export function issueEffectSourceDispatch(allowed: AllowedEffectRun, definition: RunDefinition, request: RequestIdentity, selection: ValuesSiteSelection): Readonly<{cid: string; wire: string}> {
  const args = effectSiteSelection(selection);
  const {value} = requireHandle(effectAllowedRuns, allowed);
  const dispatch = checked(owner.clientValuesHostPrepareEffectSourceDispatch(
    value, requireHandle(definitions, definition), requireHandle(requests, request),
    ...args), 'RunHostEffectSourceDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostEffectSourceDispatchRejected')});
}

/** Checked topology only; use existing producer/Transfer/current custody owners. */
export function prepareEffectRetainedTaskInputEdge(allowed: AllowedEffectRun, definition: RunDefinition): RetainedTaskInputEdge {
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return handle(retainedInputEdges, checked(owner.clientValuesHostEffectRetainedInputEdge(
    value, requireHandle(definitions, definition)), 'RunHostEffectRetainedInputEdgeRejected'),
  'retained-input-edge');
}

/** Exact original consumer; current input and destination are read again. */
export function issueEffectRetainedTaskDispatch(allowed: AllowedEffectRun, definition: RunDefinition, request: RequestIdentity, selection: ValuesSiteSelection, input: RetainedTaskInput): Readonly<{cid: string; wire: string}> {
  const args = effectSiteSelection(selection);
  const {value} = requireHandle(effectAllowedRuns, allowed);
  const dispatch = checked(owner.clientValuesHostPrepareEffectRetainedTaskDispatch(
    value, requireHandle(definitions, definition), requireHandle(requests, request),
    ...args, requireHandle(retainedTaskInputs, input)), 'RunHostEffectRetainedTaskDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostEffectRetainedTaskDispatchRejected')});
}

export function privateTaskCompilationWires(compilation: TaskCompilation): PrivateCompilationWires {
  const {value} = requireHandle(taskCompilations, compilation);
  return Object.freeze({
    executablePlan: owner.clientValuesHostTaskPlanWire(value),
    factManifest: owner.clientValuesHostTaskFactManifestWire(value),
    boundTemplate: owner.clientValuesHostTaskTemplateWire(value),
    compiledPlan: owner.clientValuesHostTaskCompiledPlanWire(value),
  });
}

export function taskResultNames(compilation: TaskCompilation): readonly string[] {
  const {value} = requireHandle(taskCompilations, compilation);
  return Object.freeze([...owner.clientValuesHostTaskResultNames(value)]);
}

export function taskExecutionShape(prepared: PreparedProgram, compilation: TaskCompilation): Readonly<{taskCount: number; acquisitionCount: number}> {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const counts = owner.clientValuesHostTaskExecutionShape(requireHandle(preparations, prepared));
  if (!Array.isArray(counts) || counts.length !== 2 ||
      counts.some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new Error('InvalidRunHostTaskExecutionProjection');
  }
  return Object.freeze({taskCount: counts[0], acquisitionCount: counts[1]});
}

/** Dispatch keys from checked task fragments, excluding Result transforms. */
export function taskKeys(prepared: PreparedProgram, compilation: TaskCompilation): readonly string[] {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const keys = checked(owner.clientValuesHostTaskKeys(requireHandle(preparations, prepared)),
    'RunHostTaskKeysRejected');
  if (!Array.isArray(keys) || keys.some(key => typeof key !== 'string') ||
      new Set(keys).size !== keys.length) throw new Error('InvalidRunHostTaskKeyProjection');
  return Object.freeze([...keys]);
}

export function privateCompilationWires(compilation: ValuesCompilation): PrivateCompilationWires {
  const {value} = requireHandle(compilations, compilation);
  return Object.freeze({
    executablePlan: owner.clientValuesHostPlanWire(value),
    factManifest: owner.clientValuesHostFactManifestWire(value),
    boundTemplate: owner.clientValuesHostTemplateWire(value),
    compiledPlan: owner.clientValuesHostCompiledPlanWire(value),
  });
}

export function compiledPlanCid(compilation: ValuesCompilation): string {
  const {value} = requireHandle(compilations, compilation);
  return owner.clientValuesHostCompiledPlanCid(value);
}

export function executionShape(compilation: ValuesCompilation): Readonly<{
  planNodeId: string;
  outputContractCid: string;
  resultNames: readonly string[];
}> {
  const {value} = requireHandle(compilations, compilation);
  return Object.freeze({
    planNodeId: owner.clientValuesHostPlanNodeId(value),
    outputContractCid: owner.clientValuesHostOutputContractCid(value),
    resultNames: Object.freeze([...owner.clientValuesHostResultNames(value)]),
  });
}

export function resultDefinitions(prepared: PreparedProgram, compilation: ValuesCompilation): readonly Readonly<{
  name: string;
  cid: string;
  wire: string;
}>[] {
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const fields = checked(owner.clientValuesHostResultDefinitions(
    requireHandle(preparations, prepared), compiled.value),
  'RunHostResultInventoryRejected');
  const names = owner.clientValuesHostResultNames(compiled.value);
  if (!Array.isArray(fields) || fields.length !== names.length * 3 ||
      !fields.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostResultInventory');
  }
  return Object.freeze(names.map((name, index) => {
    if (fields[index * 3] !== name) {
      throw new Error('InvalidRunHostResultInventory');
    }
    return Object.freeze({name, cid: fields[index * 3 + 1],
      wire: fields[index * 3 + 2]});
  }));
}

export function taskResultDefinitions(prepared: PreparedProgram, compilation: TaskCompilation): readonly Readonly<{
  name: string;
  cid: string;
  wire: string;
}>[] {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const fields = checked(owner.clientValuesHostTaskResultDefinitions(
    requireHandle(preparations, prepared), compiled.value),
  'RunHostResultInventoryRejected');
  const names = owner.clientValuesHostTaskResultNames(compiled.value);
  if (!Array.isArray(fields) || fields.length !== names.length * 3 ||
      !fields.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostResultInventory');
  }
  return Object.freeze(names.map((name, index) => {
    if (fields[index * 3] !== name) {
      throw new Error('InvalidRunHostResultInventory');
    }
    return Object.freeze({name, cid: fields[index * 3 + 1],
      wire: fields[index * 3 + 2]});
  }));
}

export function resultSchema(prepared: PreparedProgram, compilation: ValuesCompilation): Readonly<{
    cid: string;
    wire: string;
    fields: readonly string[];
  }> {
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const facts = checked(owner.clientValuesHostResultSchema(
    requireHandle(preparations, prepared)),
  'RunHostResultSchemaRejected');
  if (!Array.isArray(facts) || facts.length < 2 ||
      !facts.every(value => typeof value === 'string') ||
      !/^sha256:[0-9a-f]{64}$/u.test(facts[0])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  const fields = Object.freeze(facts.slice(2));
  // JavaScript enumerates integer-like keys numerically; the Owner uses UTF-16.
  const schemaFields = Object.keys(JSON.parse(facts[1])).sort();
  if (schemaFields.length !== fields.length ||
      schemaFields.some((field, index) => field !== fields[index])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  return Object.freeze({cid: facts[0], wire: facts[1], fields});
}

export function taskResultSchema(prepared: PreparedProgram, compilation: TaskCompilation, resultName: string): Readonly<{
    cid: string;
    wire: string;
    fields: readonly string[];
  }> {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared || typeof resultName !== 'string') {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const names = owner.clientValuesHostTaskResultNames(compiled.value);
  const result = names.indexOf(resultName);
  if (result < 0) throw new RangeError('UnknownRunHostResult');
  const facts = checked(owner.clientValuesHostTaskResultSchema(
    requireHandle(preparations, prepared), result),
  'RunHostResultSchemaRejected');
  if (!Array.isArray(facts) || facts.length < 2 ||
      !facts.every(value => typeof value === 'string') ||
      !/^sha256:[0-9a-f]{64}$/u.test(facts[0])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  const fields = Object.freeze(facts.slice(2));
  // JavaScript enumerates integer-like keys numerically; the Owner uses UTF-16.
  const schemaFields = Object.keys(JSON.parse(facts[1])).sort();
  if (schemaFields.length !== fields.length ||
      schemaFields.some((field, index) => field !== fields[index])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  return Object.freeze({cid: facts[0], wire: facts[1], fields});
}

// The Host must establish scope and admitted input intent before calling this
// pure identity operation. The returned handle is not a Run or a grant.
export function prepareRequest(prepared: PreparedProgram, authorityScopeCid: string, requestId: string,
  admittedInputIntentCid: string): RequestIdentity {
  if ([authorityScopeCid, requestId, admittedInputIntentCid]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostRequest');
  }
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) {
    if (sourceProgramOriginals(prepared).intentCid !== admittedInputIntentCid) throw new TypeError('ForeignRunHostSourceIntent');
    return prepareSourceRequest(prepared, source.intent, authorityScopeCid, requestId);
  }
  const value = checked(owner.clientValuesHostRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId,
    admittedInputIntentCid), 'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

export function prepareSourceFreeRequest(prepared: PreparedProgram, compilation: ValuesCompilation,
  authorityScopeCid: string, requestId: string): RequestIdentity {
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') {
    throw new TypeError('InvalidRunHostRequest');
  }
  const {prepared: compiledFrom} = requireHandle(compilations, compilation);
  if (compiledFrom !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) return prepareSourceRequest(prepared, source.intent, authorityScopeCid, requestId);
  const value = checked(owner.clientValuesHostSourceFreeRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId),
  'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

// A later provider capture is not a caller-supplied Run-start Artifact.
export function prepareTaskRequest(prepared: PreparedProgram, compilation: TaskCompilation,
  authorityScopeCid: string, requestId: string): RequestIdentity {
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') {
    throw new TypeError('InvalidRunHostRequest');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) return prepareSourceRequest(prepared, source.intent, authorityScopeCid, requestId);
  const value = checked(owner.clientValuesHostSourceFreeRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId),
  'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

export function sourceEvidenceFacts(prepared: PreparedProgram, stage: number, sourceIndex: number): Readonly<{sourceRef: string; sourceContractCid: string;
    carrierSchemaContractCid: string; sourceDataPolicyCid: string;
    dataClassification: string; sourceViewContractCid: string}> | undefined {
  if (![stage, sourceIndex].every(value => Number.isSafeInteger(value) &&
      value >= 0 && value <= 2147483647)) {
    throw new TypeError('InvalidRunHostSourceSelection');
  }
  const option = owner.clientValuesHostSourceEvidenceFacts(
    requireHandle(preparations, prepared), stage, sourceIndex);
  if (runtimeIsBoxedNone(option)) return undefined;
  if (!runtimeIsBoxedSome(option)) throw new Error('InvalidRunHostSourceEvidenceProjection');
  const facts = runtimeField(option, 0);
  if (!Array.isArray(facts) || facts.length !== 6 ||
      facts.some(value => typeof value !== 'string')) {
    throw new Error('InvalidRunHostSourceEvidenceProjection');
  }
  return Object.freeze({sourceRef: facts[0], sourceContractCid: facts[1],
    carrierSchemaContractCid: facts[2], sourceDataPolicyCid: facts[3],
    dataClassification: facts[4], sourceViewContractCid: facts[5]});
}

export function taskInputBinding(prepared: PreparedProgram, task: number): string {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647) {
    throw new TypeError('InvalidRunHostTaskSelection');
  }
  return checked(owner.clientValuesHostTaskInputBinding(
    requireHandle(preparations, prepared), task), 'RunHostTaskBindingRejected');
}

export function requestFields(request: RequestIdentity): RequestFields {
  const value = requireHandle(requests, request);
  return Object.freeze({
    authorityScopeCid: owner.clientValuesHostRequestAuthorityScopeCid(value),
    requestId: owner.clientValuesHostRequestCallerId(value),
    logicalRequestScopeCid: owner.clientValuesHostRequestScopeCid(value),
    intentFingerprintCid: owner.clientValuesHostRequestIntentCid(value),
    programDefinitionCid: owner.clientValuesHostRequestProgramCid(value),
    parameterValuesCid: owner.clientValuesHostRequestParametersCid(value),
    callerInputIntentCid: owner.clientValuesHostRequestInputCid(value),
  });
}

const requestKeys = ['authorityScopeCid', 'requestId',
  'logicalRequestScopeCid', 'intentFingerprintCid', 'programDefinitionCid',
  'parameterValuesCid', 'callerInputIntentCid'] as const;

export function admitRequestFields(fields: RequestFields): RequestIdentity {
  if (fields === null || typeof fields !== 'object' || Array.isArray(fields) ||
      Object.keys(fields).sort().join('\0') !==
        [...requestKeys].sort().join('\0') ||
      requestKeys.some(key => typeof fields[key] !== 'string')) {
    throw new TypeError('InvalidRunHostRequestRecord');
  }
  const value = checked(owner.clientValuesHostAdmitRequestIdentity(
    fields.authorityScopeCid, fields.requestId,
    fields.programDefinitionCid, fields.parameterValuesCid,
    fields.callerInputIntentCid, fields.logicalRequestScopeCid,
    fields.intentFingerprintCid), 'RunHostRequestRecordRejected');
  return handle(requests, value, 'request-identity');
}

export function admitSourceFreeRequestFields(prepared: PreparedProgram, compilation: ValuesCompilation, fields: RequestFields): RequestIdentity {
  if (fields === null || typeof fields !== 'object' || Array.isArray(fields) ||
      Object.keys(fields).sort().join('\0') !==
        [...requestKeys].sort().join('\0') ||
      requestKeys.some(key => typeof fields[key] !== 'string')) {
    throw new TypeError('InvalidRunHostRequestRecord');
  }
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) {
    const compiled = requireHandle(compilations, compilation);
    if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
    return admitSourceRequestFields(prepared, source.intent, fields);
  }
  const value = checked(owner.clientValuesHostAdmitSourceFreeRequestIdentity(
    fields.authorityScopeCid, fields.requestId,
    fields.programDefinitionCid, fields.parameterValuesCid,
    fields.callerInputIntentCid, fields.logicalRequestScopeCid,
    fields.intentFingerprintCid), 'RunHostRequestRecordRejected');
  const current = prepareSourceFreeRequest(prepared, compilation,
    fields.authorityScopeCid, fields.requestId);
  if (owner.clientValuesHostRequestRelation(
    requireHandle(requests, current), value) !== 1) {
    throw Object.assign(new Error('RunHostRequestRecordRejected'),
      {code: 'RunHostRequestRecordRejected'});
  }
  return handle(requests, value, 'request-identity');
}

export function requestRelation(requested: RequestIdentity, retained: RequestIdentity): 'different_request' | 'same_request' |
    'changed_intent' {
  const relation = owner.clientValuesHostRequestRelation(
    requireHandle(requests, requested), requireHandle(requests, retained));
  switch (relation) {
    case 0: return 'different_request';
    case 1: return 'same_request';
    case 2: return 'changed_intent';
    default: throw new Error('InvalidRunHostRequestRelation');
  }
}

export function admitRun(prepared: PreparedProgram, compilation: ValuesCompilation, preparedInvocationWire: string,
  authorizationWire: string): RunAdmission {
  if (typeof preparedInvocationWire !== 'string' ||
      typeof authorizationWire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitRun(
    requireHandle(preparations, prepared),
    compiled.value,
    preparedInvocationWire, authorizationWire),
  'RunHostAdmissionRejected');
  return handle(admissions, {value, prepared}, 'run-admission');
}

// Host authorization must precede this call. These owner-issued wires bind
// the selected policy context to the exact checked Values compilation.
export function issueAllowedRun(prepared: PreparedProgram, compilation: ValuesCompilation, {
  executionContextCid, hostPolicyCid, expiresAt,
}: Readonly<{
    executionContextCid: string;
    hostPolicyCid: string;
    expiresAt: string;
  }>): Readonly<{
    admission: RunAdmission;
    preparedInvocationWire: string;
    authorizationWire: string;
  }> {
  if ([executionContextCid, hostPolicyCid, expiresAt]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const issued = checked(owner.clientValuesHostIssueAllowedRun(
    requireHandle(preparations, prepared), compiled.value,
    executionContextCid, hostPolicyCid, expiresAt),
  'RunHostAdmissionRejected');
  return Object.freeze({
    admission: handle(admissions, {
      value: owner.clientValuesHostAllowedRunAdmission(issued), prepared,
    }, 'run-admission'),
    preparedInvocationWire:
      owner.clientValuesHostAllowedRunPreparedWire(issued),
    authorizationWire:
      owner.clientValuesHostAllowedRunAuthorizationWire(issued),
  });
}

export function issueAllowedTaskRun(prepared: PreparedProgram, compilation: TaskCompilation, {
  executionContextCid, hostPolicyCid, expiresAt,
}: Readonly<{
    executionContextCid: string;
    hostPolicyCid: string;
    expiresAt: string;
  }>): Readonly<{
    admission: RunAdmission;
    preparedInvocationWire: string;
    authorizationWire: string;
  }> {
  if ([executionContextCid, hostPolicyCid, expiresAt]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const issued = checked(owner.clientValuesHostIssueAllowedTaskRun(
    requireHandle(preparations, prepared), compiled.value,
    executionContextCid, hostPolicyCid, expiresAt),
  'RunHostAdmissionRejected');
  return Object.freeze({
    admission: handle(admissions, {
      value: owner.clientValuesHostAllowedRunAdmission(issued), prepared,
    }, 'run-admission'),
    preparedInvocationWire:
      owner.clientValuesHostAllowedRunPreparedWire(issued),
    authorizationWire:
      owner.clientValuesHostAllowedRunAuthorizationWire(issued),
  });
}

export function admitTaskRun(prepared: PreparedProgram, compilation: TaskCompilation,
  preparedInvocationWire: string, authorizationWire: string): RunAdmission {
  if ([preparedInvocationWire, authorizationWire]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitTaskRun(
    requireHandle(preparations, prepared), compiled.value,
    preparedInvocationWire, authorizationWire),
  'RunHostAdmissionRejected');
  return handle(admissions, {value, prepared}, 'run-admission');
}

export function issueRunDefinition(admission: RunAdmission, scopeId: string, runId: string,
  inputArtifactSetCid: string, createdAt: string, validUntil: string): RunDefinition {
  if ([scopeId, runId, inputArtifactSetCid, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueRunDefinition(
    requireHandle(admissions, admission).value, scopeId, runId,
    inputArtifactSetCid, createdAt, validUntil),
  'RunHostDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function issueSourceFreeRunDefinition(prepared: PreparedProgram, compilation: ValuesCompilation,
  admission: RunAdmission, scopeId: string, runId: string, createdAt: string, validUntil: string): RunDefinition {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([scopeId, runId, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueSourceFreeRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    scopeId, runId, createdAt, validUntil),
  'RunHostSourceFreeDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function issueTaskRunDefinition(prepared: PreparedProgram, compilation: TaskCompilation,
  admission: RunAdmission, scopeId: string, runId: string, createdAt: string, validUntil: string): RunDefinition {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([scopeId, runId, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueTaskRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    scopeId, runId, createdAt, validUntil),
  'RunHostTaskDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function admitTaskRunDefinition(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission,
  wire: string): RunDefinition {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitTaskRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    wire), 'RunHostTaskDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function privateRunDefinition(definition: RunDefinition): Readonly<{
  wire: string;
  cid: string;
}> {
  const value = requireHandle(definitions, definition);
  return Object.freeze({
    wire: owner.clientValuesHostRunDefinitionWire(value),
    cid: owner.clientValuesHostRunDefinitionCid(value),
  });
}

/** Capture once from the same checked compilation/admission used by the Host.
 * The Host persists the two original wires in its first admission transaction. */
export function captureOriginalRunPlan(prepared: PreparedProgram, compilation: ValuesCompilation | TaskCompilation, admission: RunAdmission, definition: RunDefinition, limits: PublicationLimits): OriginalRunPlan {
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const task = taskCompilations.has(compilation as TaskCompilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const fields = checked(((task
    ? owner.clientValuesHostCaptureOriginalTaskRunPlan
    : owner.clientValuesHostCaptureOriginalValuesRunPlan) as SelectedOwnerCall<
      typeof owner.clientValuesHostCaptureOriginalTaskRunPlan, typeof owner.clientValuesHostCaptureOriginalValuesRunPlan
    >)(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), maxWireBytes, maxNodes, maxDepth),
  'RunHostOriginalPlanRejected');
  if (!Array.isArray(fields) || fields.length !== 5 ||
      fields.some(value => typeof value !== 'string')) {
    throw new Error('InvalidRunHostOriginalPlanProjection');
  }
  const original = Object.freeze({compiledPlanWire: fields[0], planViewWire: fields[1]});
  readStoredRunPlanOriginal(original, definition, fields[2], limits);
  return handle(originalRunPlans, Object.freeze({original,
    definitionCid: privateRunDefinition(definition).cid,
    programCid: fields[2], prepared: fields[3], authorization: fields[4]}),
  'original-run-plan');
}

/** Only a genuine first-capture token can supply admission evidence. */
export function originalRunPlanAdmissionEvidence(selection: OriginalRunPlan, definition: RunDefinition, programCid: string, evidence: Readonly<{prepared: string; authorization: string}>): StoredRunPlanOriginal {
  const retained = requireHandle(originalRunPlans, selection);
  if (retained.definitionCid !== privateRunDefinition(definition).cid ||
      retained.programCid !== programCid || retained.prepared !== evidence?.prepared ||
      retained.authorization !== evidence?.authorization) {
    throw new TypeError('ForeignRunHostOriginalPlanAdmission');
  }
  return retained.original;
}

/** Validate authenticated saved metadata without preparation, recompilation or
 * reissuing capture custody. The Host separately checks current RunRead and its
 * original Run/request/context join before and after durable lookup. */
export function readStoredRunPlanOriginal(original: StoredRunPlanOriginal | undefined, definition: RunDefinition, programCid: string, limits: PublicationLimits): string {
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const run = privateRunDefinition(definition);
  if (original === undefined) {
    throw Object.assign(new Error('RunHostOriginalPlanUnavailable'),
      {code: 'RunHostOriginalPlanUnavailable'});
  }
  if (original === null || typeof original !== 'object' || Array.isArray(original)) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  const names = Reflect.ownKeys(original);
  const expected = ['compiledPlanWire', 'planViewWire'];
  if (names.length !== expected.length || names.some(name => typeof name !== 'string') ||
      names.sort().some((name, index) => name !== expected[index])) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  // Snapshot data fields once; accessors cannot replace bytes between checks.
  const descriptors = Object.getOwnPropertyDescriptors(original);
  if (Reflect.ownKeys(descriptors).length !== expected.length ||
      expected.some(name => !descriptors[name]?.enumerable ||
        !Object.hasOwn(descriptors[name], 'value'))) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  const compiledPlanWire = descriptors.compiledPlanWire.value as string;
  const planViewWire = descriptors.planViewWire.value as string;
  if (typeof programCid !== 'string' ||
      [compiledPlanWire, planViewWire].some(wire => typeof wire !== 'string' ||
        wire.length > maxWireBytes)) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  const plan = admitPublicationContract('compiled_plan', compiledPlanWire, limits);
  if (plan.wire !== compiledPlanWire) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  checked(owner.clientValuesHostCheckStoredPlanView(planViewWire,
    maxWireBytes, maxNodes, maxDepth), 'RunHostOriginalPlanRejected');
  const view = JSON.parse(planViewWire);
  if (JSON.parse(run.wire).compiled_plan_cid !== plan.cid ||
      view.compiled_plan_cid !== plan.cid ||
      JSON.parse(plan.wire).program_definition_cid !== programCid) {
    throw new TypeError('ForeignRunHostOriginalPlan');
  }
  const map = admitRunEvidenceValue('logical_map', JSON.stringify(view.logical_map), limits);
  checked(owner.clientValuesHostCheckLogicalMapBinding(
    requireHandle(runEvidences, map.token), publicationToken(plan),
    maxWireBytes, maxNodes, maxDepth), 'RunHostOriginalMapRejected');
  return planViewWire;
}

// The caller must retain the checked admission and the current physical
// observation. A state wire is a projection, never Run or read authority.
export function issueUnpublishedRunStateWire(prepared: PreparedProgram, compilation: ValuesCompilation | TaskCompilation,
  admission: RunAdmission, definition: RunDefinition, observedAt: string, observation: Readonly<{dispatchReserved: boolean;
    preDispatchFailureConfirmed: boolean; cancelledBeforeStart?: boolean;
    executionUnknown?: boolean}>): string {
  const task = taskCompilations.has(compilation as TaskCompilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const {dispatchReserved, preDispatchFailureConfirmed,
    cancelledBeforeStart = false, executionUnknown = false} =
    observation ?? {};
  if (typeof observedAt !== 'string' ||
      observation === null || typeof observation !== 'object' ||
      Array.isArray(observation) ||
      typeof dispatchReserved !== 'boolean' ||
      typeof preDispatchFailureConfirmed !== 'boolean' ||
      typeof cancelledBeforeStart !== 'boolean' ||
      typeof executionUnknown !== 'boolean') {
    throw new TypeError('InvalidRunHostStateObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const issue = (task ? owner.clientValuesHostIssueTaskUnpublishedRunStateWire
    : owner.clientValuesHostIssueUnpublishedRunStateWire) as SelectedOwnerCall<
      typeof owner.clientValuesHostIssueTaskUnpublishedRunStateWire, typeof owner.clientValuesHostIssueUnpublishedRunStateWire
    >;
  const wire = issue(
    requireHandle(definitions, definition), compiled.value, observedAt,
    dispatchReserved, preDispatchFailureConfirmed, cancelledBeforeStart,
    executionUnknown);
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostStateProjectionRejected'),
      {code: 'RunHostStateProjectionRejected'});
  }
  return wire;
}

export function issueSucceededRunStateWire(prepared: PreparedProgram,
  compilation: ValuesCompilation | TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, observedAt: string,
  observations: readonly RunResultStateObservation[]): string;
/** Requires the same admitted successful Effect outcome and checked publication
 * inputs. The Host still supplies the actual committed index/current observations. */
export function issueSucceededRunStateWire(prepared: PreparedEffectProgram,
  compilation: EffectCompilation, admission: AllowedEffectRun,
  definition: RunDefinition, observedAt: string,
  observations: readonly RunResultStateObservation[], finalReceipt: PublicationContract): string;
export function issueSucceededRunStateWire(prepared: PreparedProgram | PreparedEffectProgram,
  compilation: ValuesCompilation | TaskCompilation | EffectCompilation, admission: RunAdmission | AllowedEffectRun,
  definition: RunDefinition, observedAt: string, observations: readonly RunResultStateObservation[],
  effectFinalReceipt?: PublicationContract): string {
  const task = taskCompilations.has(compilation as TaskCompilation);
  const effect = effectCompilations.has(compilation as EffectCompilation);
  const compiled = requireHandle(effect ? effectCompilations : task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(effect ? effectAllowedRuns : admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared ||
      effect && (admitted as CustodyValue<typeof effectAllowedRuns>).compilation !== compilation) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof observedAt !== 'string' || !Array.isArray(observations) ||
      !observations.every(value => value !== null &&
        typeof value === 'object' &&
        ['name', 'state', 'reason', 'observedAt'].every(key =>
          typeof value[key] === 'string'))) {
    throw new TypeError('InvalidRunHostStateObservation');
  }
  if (effect) {
    const retained = retainedEffectFinal(effectFinalReceipt);
    if (retained.validatedPublication === undefined) {
      throw new TypeError('RunHostEffectPublicationEvidenceRequired');
    }
    const wire = owner.clientValuesHostIssueEffectSucceededRunStateWire(
      requireHandle(effectPreparations, prepared), (admitted as CustodyValue<typeof effectAllowedRuns>).value,
      requireHandle(definitions, definition), retained.value, observedAt,
      observations.map(value => value.name), observations.map(value => value.state),
      observations.map(value => value.reason), observations.map(value => value.observedAt));
    if (typeof wire !== 'string') {
      throw Object.assign(new Error('RunHostStateProjectionRejected'), {code:'RunHostStateProjectionRejected'});
    }
    return wire;
  }
  checkRunBinding(prepared as PreparedProgram, admission as RunAdmission, definition);
  const issue = (task ? owner.clientValuesHostIssueTaskSucceededRunStateWire
    : owner.clientValuesHostIssueSucceededRunStateWire) as SelectedOwnerCall<
      typeof owner.clientValuesHostIssueTaskSucceededRunStateWire, typeof owner.clientValuesHostIssueSucceededRunStateWire
    >;
  const wire = issue(
    requireHandle(definitions, definition), compiled.value as owner.ClientValuesCompilation | owner.ClientTaskCompilation, observedAt,
    observations.map(value => value.name),
    observations.map(value => value.state),
    observations.map(value => value.reason),
    observations.map(value => value.observedAt));
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostStateProjectionRejected'),
      {code: 'RunHostStateProjectionRejected'});
  }
  return wire;
}

export function resultReadAvailability(manifest: PublicationContract, resultName: string, retention: PublicationContract,
  observedAt: string): 'available' | 'retention_expired' | 'delete_due' {
  if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
    throw new TypeError('InvalidRunHostAvailabilityObservation');
  }
  return checked(owner.clientValuesHostResultReadAvailability(
    publicationToken(manifest), resultName, publicationToken(retention),
    observedAt), 'RunHostAvailabilityRejected') as ReturnType<typeof resultReadAvailability>;
}

// The common publication owner selects and checks every listed binding.
// CIDs returned here identify physical custody; they grant no read access.
export function projectCommittedResultRead(index: PublicationContract, manifest: PublicationContract, resultName: string,
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
  }> {
  if (typeof resultName !== 'string' || !Array.isArray(bindings)) {
    throw new TypeError('InvalidRunHostResultSelection');
  }
  const wire = owner.clientValuesHostProjectCommittedResultReadWire(
    publicationToken(index), publicationToken(manifest), resultName,
    publicationItems(bindings));
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostResultSelectionRejected'),
      {code: 'RunHostResultSelectionRejected'});
  }
  const value = JSON.parse(wire) as {
    result_name: string; result_artifact_cid: string; result_definition_cid: string;
    logical_result_cid: string; result_schema_cid: string; ordering_evidence_cid: string;
    effective_retention_policy_cid: string; durable_result_binding_cid: string;
    material_generation_cid: string; store_authority_cid: string; codec_contract_cid: string;
    result_fields: readonly string[]; row_count: number; byte_count: number; physical_sha256: string;
  };
  const cid = (value: unknown) => typeof value === 'string' &&
    /^sha256:[0-9a-f]{64}$/u.test(value);
  if (value === null || typeof value !== 'object' ||
      !(['codec_contract_cid', 'durable_result_binding_cid',
        'effective_retention_policy_cid', 'logical_result_cid',
        'material_generation_cid', 'ordering_evidence_cid',
        'result_artifact_cid', 'result_definition_cid',
        'result_schema_cid', 'store_authority_cid'] as const).every(key =>
        cid(value[key])) ||
      typeof value.physical_sha256 !== 'string' ||
      !/^[0-9a-f]{64}$/u.test(value.physical_sha256) ||
      value.result_name !== resultName ||
      !Array.isArray(value.result_fields) ||
      !value.result_fields.every((field: unknown) => typeof field === 'string') ||
      !Number.isSafeInteger(value.row_count) || value.row_count < 0 ||
      !Number.isSafeInteger(value.byte_count) || value.byte_count < 0) {
    throw new Error('RunHostResultSelectionInvalid');
  }
  return Object.freeze({resultName: value.result_name,
    resultArtifactCid: value.result_artifact_cid,
    resultDefinitionCid: value.result_definition_cid,
    logicalResultCid: value.logical_result_cid,
    resultSchemaCid: value.result_schema_cid,
    orderingEvidenceCid: value.ordering_evidence_cid,
    effectiveRetentionPolicyCid: value.effective_retention_policy_cid,
    durableResultBindingCid: value.durable_result_binding_cid,
    materialGenerationCid: value.material_generation_cid,
    storeAuthorityCid: value.store_authority_cid,
    codecContractCid: value.codec_contract_cid,
    resultFields: Object.freeze([...value.result_fields]),
    rowCount: value.row_count, byteCount: value.byte_count,
    physicalSha256: value.physical_sha256});
}

export function describeCommittedResult(index: PublicationContract, manifest: PublicationContract, resultName: string,
  bindings: readonly PublicationContract[], definition: PublicationContract, schemaWire: string, format: string, limits: PublicationLimits): Omit<import('@actql/client-wire').WireResultDescription, 'ref'> {
  const bounds = publicationLimits(limits);
  const wire = owner.clientValuesHostDescribeCommittedResult(
    publicationToken(index), publicationToken(manifest), resultName,
    publicationItems(bindings), publicationToken(definition), schemaWire,
    format, bounds.maxWireBytes, bounds.maxNodes, bounds.maxDepth);
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostResultDescriptionRejected'),
      {code: 'RunHostResultDescriptionRejected'});
  }
  return JSON.parse(wire);
}

export function admitRunDefinition(wire: string): RunDefinition {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const value = checked(owner.clientValuesHostAdmitRunDefinition(wire),
    'RunHostDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function admitSourceFreeRunDefinition(prepared: PreparedProgram, compilation: ValuesCompilation,
  admission: RunAdmission, wire: string): RunDefinition {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const value = checked(owner.clientValuesHostAdmitSourceFreeRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    wire), 'RunHostSourceFreeAdmissionRejected');
  return handle(definitions, value, 'run-definition');
}

/** Project the original Run; this does not compile or issue authorization. */
export function issueSourceFreeRunMaterials(prepared: PreparedProgram, compilation: ValuesCompilation, admission: RunAdmission,
  definition: RunDefinition, retained: SourceFreeRunMaterialsInput): string {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  validateRunMaterialsInput(retained);
  return checked(owner.clientValuesHostIssueSourceFreeRunMaterials(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition),
    requireHandle(environments, retained.environment),
    retained.environmentWire, retained.document, retained.parametersWire),
  'RunHostRunMaterialsRejected');
}

/** Project the original checked task Run; Source bindings stay at the Site. */
export function issueTaskRunMaterials(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, retained: SourceFreeRunMaterialsInput): string {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  validateRunMaterialsInput(retained);
  return checked(owner.clientValuesHostIssueTaskRunMaterials(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition),
    requireHandle(environments, retained.environment),
    retained.environmentWire, retained.document, retained.parametersWire),
  'RunHostRunMaterialsRejected');
}

function validateRunMaterialsInput(retained: SourceFreeRunMaterialsInput) {
  if (retained === null || typeof retained !== 'object' ||
      Array.isArray(retained) || retained.format !== 'json' ||
      typeof retained.document !== 'string' ||
      typeof retained.environmentWire !== 'string' ||
      retained.parametersWire !== undefined &&
        typeof retained.parametersWire !== 'string' ||
      Object.keys(retained).some(key => !['format', 'document',
        'environment', 'environmentWire', 'parametersWire'].includes(key))) {
    throw new TypeError('InvalidRunHostRunMaterialsInput');
  }
}

export function prepareRunStart(requested: RequestIdentity, retained: RequestIdentity, definition: RunDefinition,
  retainedRunDefinitionCid: string, dispatchReserved: boolean, currentAuthorization: boolean): 'reserve_dispatch' |
  'reconcile_reserved_dispatch' {
  if (typeof retainedRunDefinitionCid !== 'string' ||
      typeof dispatchReserved !== 'boolean' ||
      typeof currentAuthorization !== 'boolean') {
    throw new TypeError('InvalidRunHostStart');
  }
  const action = checked(owner.clientValuesHostPrepareRunStart(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), retainedRunDefinitionCid,
    dispatchReserved, currentAuthorization), 'RunHostStartRejected');
  switch (action) {
    case 0: return 'reserve_dispatch';
    case 1: return 'reconcile_reserved_dispatch';
    default: throw new Error('InvalidRunHostStartAction');
  }
}

export function checkRunBinding(prepared: PreparedProgram, admission: RunAdmission, definition: RunDefinition): void {
  const admitted = requireHandle(admissions, admission);
  if (admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostAdmission');
  }
  checked(owner.clientValuesHostCheckRunBinding(
    requireHandle(preparations, prepared), admitted.value,
    requireHandle(definitions, definition)), 'RunHostBindingRejected');
}

export function issueSourceFreeInvocation(prepared: PreparedProgram, compilation: ValuesCompilation, admission: RunAdmission,
  definition: RunDefinition, dataPolicyCid: string, limits: PublicationLimits): Readonly<{
    observation: RunEvidence;
    invocation: PublicationContract;
  }> {
  if (typeof dataPolicyCid !== 'string') {
    throw new TypeError('InvalidRunHostDataPolicy');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueSourceFreeInvocation(
    compiled.value, dataPolicyCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostInvocationProjection');
  }
  return Object.freeze({observation, invocation});
}

export function issueSourceFreeTaskInvocation(prepared: PreparedProgram, compilation: TaskCompilation,
  admission: RunAdmission, definition: RunDefinition, dataPolicyCid: string, limits: PublicationLimits): Readonly<{
    observation: RunEvidence;
    invocation: PublicationContract;
  }> {
  if (typeof dataPolicyCid !== 'string') {
    throw new TypeError('InvalidRunHostDataPolicy');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueSourceFreeTaskInvocation(
    compiled.value, dataPolicyCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostTaskInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  return Object.freeze({observation, invocation});
}

// Source Evidence may enter an acquired task Run only when the admitted
// logical input, checked source, and current Host scope agree. The Host still
// owns authorization and the live capture; this identity grants neither.
export function admitCompletedSourceObservation({sourceEvidenceWire,
  inputLogicalWire, sourceRef, sourceContractCid, authorityScopeCid,
  effectiveDataPolicyCid,
  limits}: Readonly<{
  sourceEvidenceWire: string;
  inputLogicalWire: string;
  sourceRef: string;
  sourceContractCid: string;
  authorityScopeCid: string;
  effectiveDataPolicyCid: string;
  limits: PublicationLimits;
}>): string {
  if ([sourceEvidenceWire, inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, effectiveDataPolicyCid].some(value =>
    typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostSourceObservation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostAdmitCompletedSourceObservation(
    sourceEvidenceWire, inputLogicalWire, sourceRef, sourceContractCid,
    authorityScopeCid, effectiveDataPolicyCid, maxWireBytes, maxNodes,
    maxDepth),
  'RunHostSourceObservationRejected');
}

export function issueTaskInvocation(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, {sourceEvidenceWire, inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, dataPolicyCid,
    captureStartedAt, captureCompletedAt}: Readonly<{
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
  }> {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  if ([sourceEvidenceWire, inputLogicalWire, sourceRef, sourceContractCid,
    authorityScopeCid, dataPolicyCid, captureStartedAt, captureCompletedAt]
    .some(value => typeof value !== 'string') ||
    ![captureStartedAt, captureCompletedAt].every(value =>
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(value) &&
      Number.isFinite(Date.parse(value)) &&
      new Date(value).toISOString() === value) ||
    captureStartedAt > captureCompletedAt) {
    throw new TypeError('InvalidRunHostTaskObservation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueTaskInvocation(
    requireHandle(preparations, prepared), compiled.value,
    requireHandle(admissions, admission).value,
    requireHandle(definitions, definition), sourceEvidenceWire,
    inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, dataPolicyCid,
    captureStartedAt, captureCompletedAt, maxWireBytes, maxNodes,
    maxDepth), 'RunHostTaskInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  return Object.freeze({observation, invocation});
}

const siteSelectionKeys = ['taskAttempt', 'dispatchId', 'siteKey',
  'siteGeneration', 'runtimeBundleCid', 'connectorRegistration',
  'connectorRevision', 'strategyRevision', 'obligationsCid', 'budgetCid',
  'evidenceIssuerCapabilityCid', 'grantCid'] as const;

/** Checked topology only: no producer completion, holding or start authority. */
export function prepareRetainedTaskInputEdge(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, consumerTask: number, inputIndex: number): RetainedTaskInputEdge {
  if (![consumerTask, inputIndex].every(value => Number.isSafeInteger(value) &&
      value >= 0 && value <= 2147483647)) {
    throw new TypeError('InvalidRunHostRetainedInputEdge');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const edge = checked(owner.clientValuesHostRetainedInputEdge(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), consumerTask, inputIndex),
  'RunHostRetainedInputEdgeRejected');
  return handle(retainedInputEdges, edge, 'retained-input-edge');
}

/** Carrier port identity and physical schema identity remain distinct. */
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
}> {
  const values = owner.clientValuesHostRetainedInputEdgeFacts(
    requireHandle(retainedInputEdges, edge));
  if (!Array.isArray(values) || values.length !== 9 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputEdgeProjection');
  }
  const [runDefinitionCid, producerTaskKey, producerOutputPort,
    producerLogicalCid, carrierContractCid, consumerTaskKey,
    consumerLogicalCid, consumerInputPort, physicalSchemaCid] = values;
  return Object.freeze({runDefinitionCid, producerTaskKey, producerOutputPort,
    producerLogicalCid, carrierContractCid, consumerTaskKey,
    consumerLogicalCid, consumerInputPort, physicalSchemaCid});
}

/** The trusted Host must read its current durable Coordinator owner here. */
export function prepareRetainedInputProducer(edge: RetainedTaskInputEdge, readCurrent: () => Readonly<{authority: string;
    durableRecordWire: string}>): RetainedInputProducer {
  const ownedEdge = requireHandle(retainedInputEdges, edge);
  if (typeof readCurrent !== 'function') {
    throw new TypeError('InvalidRunHostRetainedProducerCurrent');
  }
  const current = () => {
    const value = readCurrent();
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.keys(value).sort().join('\0') !== 'authority\0durableRecordWire' ||
        typeof value.authority !== 'string' ||
        typeof value.durableRecordWire !== 'string') {
      throw new TypeError('InvalidRunHostRetainedProducerCurrent');
    }
    return [value.authority, value.durableRecordWire];
  };
  const producer = checked(owner.clientValuesHostRetainedInputProducer(
    ownedEdge, current), 'RunHostRetainedProducerRejected');
  return handle(retainedInputProducers, producer, 'retained-input-producer');
}

export function retainedInputProducerAvailable(producer: RetainedInputProducer): boolean {
  return owner.clientValuesHostRetainedInputProducerAvailable(
    requireHandle(retainedInputProducers, producer));
}

/** Historical canonical evidence; it grants no read, borrow or dispatch. */
export function retainedInputProducerFacts(producer: RetainedInputProducer): Readonly<{
  dispatch: Readonly<{cid: string; wire: string}>;
  evidence: Readonly<{cid: string; wire: string}>;
  subject: Readonly<{cid: string; wire: string}>;
}> {
  const values = checked(owner.clientValuesHostRetainedInputProducerFacts(
    requireHandle(retainedInputProducers, producer)),
  'RunHostRetainedProducerRejected');
  if (!Array.isArray(values) || values.length !== 6 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedProducerProjection');
  }
  const [dispatchCid, dispatchWire, evidenceCid, evidenceWire,
    subjectCid, subjectWire] = values;
  return Object.freeze({dispatch: Object.freeze({cid: dispatchCid, wire: dispatchWire}),
    evidence: Object.freeze({cid: evidenceCid, wire: evidenceWire}),
    subject: Object.freeze({cid: subjectCid, wire: subjectWire})});
}

const retainedPlanPolicyKeys = ['destinationGrantCid', 'routeCapabilityCid',
  'sourceGrantCid', 'transferAttempt', 'transferExpiresUnixMs', 'transferMaxBytes'] as const;
const retainedPlanCurrentKeys = ['siteBindingCurrent', 'authority', 'nowUnixMs', 'authorized'] as const;
const retainedPlanLimitKeys = ['maxChunks', 'maxManifestBytes', 'maxReferencedBytes'] as const;
const retainedInt64Maximum = 9223372036854775807n;
const exactRetainedFields = <Key extends string>(value: unknown, keys: readonly Key[]): value is Record<Key, unknown> => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const retainedWire = (value: unknown): value is Readonly<{cid: string; wire: string}> => exactRetainedFields(value, ['cid', 'wire']) &&
  typeof value.cid === 'string' && typeof value.wire === 'string';

/** The checked producer supplies every edge and completion field. */
export function prepareRetainedInputIntent(producer: RetainedInputProducer, policy: RetainedInputTransferPolicy): RetainedInputIntent {
  const owned = requireHandle(retainedInputProducers, producer);
  if (!exactRetainedFields(policy, retainedPlanPolicyKeys) ||
      retainedPlanPolicyKeys.slice(0, 4).some(key => typeof policy[key] !== 'string') ||
      (['transferExpiresUnixMs', 'transferMaxBytes'] as const).some(key =>
        typeof policy[key] !== 'bigint' || policy[key] < 1n ||
        policy[key] > retainedInt64Maximum)) {
    throw new TypeError('InvalidRunHostRetainedInputPolicy');
  }
  const value = checked(owner.clientValuesHostPrepareRetainedInputIntent(owned,
    policy.destinationGrantCid, policy.routeCapabilityCid, policy.sourceGrantCid,
    policy.transferAttempt, policy.transferExpiresUnixMs, policy.transferMaxBytes),
  'RunHostRetainedInputIntentRejected');
  return handle(retainedInputIntents, {producer: owned, value}, 'retained-input-intent');
}

/** Restore original saved bytes, not another intent or refreshed lifetime. */
export function admitRetainedInputIntent(producer: RetainedInputProducer, saved: Readonly<{cid: string; wire: string}>): RetainedInputIntent {
  const owned = requireHandle(retainedInputProducers, producer);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputIntentWire');
  const value = checked(owner.clientValuesHostAdmitRetainedInputIntent(
    owned, saved.wire, saved.cid), 'RunHostRetainedInputIntentRejected');
  return handle(retainedInputIntents, {producer: owned, value}, 'retained-input-intent');
}

/** Historical projection only; it is not current delivery permission. */
export function retainedInputIntentFacts(intent: RetainedInputIntent): Readonly<{
  cid: string; wire: string;
}> {
  const values = owner.clientValuesHostRetainedInputIntentFacts(
    requireHandle(retainedInputIntents, intent).value);
  if (!Array.isArray(values) || values.length !== 2 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputIntentProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1]});
}

/** Checked original poll envelope, before the Native physical manifest exists. */
export function retainedInputPlanEnvelope(intent: RetainedInputIntent): string {
  const owned = requireHandle(retainedInputIntents, intent);
  return checked(owner.clientValuesHostRetainedInputPlanEnvelope(
    owned.producer, owned.value), 'RunHostRetainedInputIntentRejected');
}

/** Current trusted scope is required even when restoring a saved Native plan. */
export function admitRetainedInputPlan(intent: RetainedInputIntent, saved: Readonly<{cid: string; wire: string}>, current: RetainedInputPlanCurrent, limits: RetainedInputPlanLimits): RetainedInputPlan {
  const owned = requireHandle(retainedInputIntents, intent);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputPlanWire');
  if (!exactRetainedFields(current, retainedPlanCurrentKeys) ||
      retainedPlanCurrentKeys.some(key => typeof current[key] !== 'function')) {
    throw new TypeError('InvalidRunHostRetainedPlanCurrent');
  }
  if (!exactRetainedFields(limits, retainedPlanLimitKeys) ||
      (['maxChunks', 'maxManifestBytes'] as const).some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > 2147483647) ||
      typeof limits.maxReferencedBytes !== 'bigint' || limits.maxReferencedBytes < 1n ||
      limits.maxReferencedBytes > retainedInt64Maximum) {
    throw new TypeError('InvalidRunHostRetainedPlanLimits');
  }
  // Capture ports, not their first successful answers. Every validation reads
  // current trusted state; changing an object's properties cannot swap ports.
  const {siteBindingCurrent, authority, nowUnixMs, authorized} = current;
  const booleanResult = (value: unknown, code: string) => {
    if (typeof value !== 'boolean') throw new TypeError(code);
    return value;
  };
  const value = checked(owner.clientValuesHostAdmitRetainedInputPlan(
    owned.producer, owned.value, saved.wire, saved.cid,
    (key, generation, bundle) => booleanResult(
      siteBindingCurrent(key, Number(generation), bundle), 'InvalidRunHostRetainedSiteCurrent'),
    () => {
      const value = authority();
      if (typeof value !== 'string') throw new TypeError('InvalidRunHostRetainedAuthority');
      return value;
    },
    () => {
      const value = nowUnixMs();
      if (typeof value !== 'bigint' || value < 0n || value > retainedInt64Maximum) {
        throw new TypeError('InvalidRunHostRetainedClock');
      }
      return value;
    },
    (dispatchCid, requestWire) => booleanResult(authorized(dispatchCid, requestWire),
      'InvalidRunHostRetainedAuthorization'),
    limits.maxChunks, limits.maxManifestBytes, limits.maxReferencedBytes),
  'RunHostRetainedInputPlanRejected');
  return handle(retainedInputPlans, value, 'retained-input-plan');
}

/** Revalidate after persistence and immediately before delivery. */
export function validateRetainedInputPlan(plan: RetainedInputPlan): void {
  checked(owner.clientValuesHostValidateRetainedInputPlan(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
}

/** Immutable originals only; no reservation, borrow, payload or start claim. */
export function retainedInputPlanFacts(plan: RetainedInputPlan): Readonly<{
  cid: string; wire: string;
  transfer: Readonly<{cid: string; wire: string}>;
  manifest: Readonly<{cid: string; wire: string}>;
}> {
  const values = checked(owner.clientValuesHostRetainedInputPlanFacts(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
  if (!Array.isArray(values) || values.length !== 6 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputPlanProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1],
    transfer: Object.freeze({cid: values[2], wire: values[3]}),
    manifest: Object.freeze({cid: values[4], wire: values[5]})});
}

/** Revalidate the original checked plan against live Owners before delivery. */
export function retainedInputTransferEnvelope(plan: RetainedInputPlan): string {
  return checked(owner.clientValuesHostRetainedInputTransferEnvelope(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
}

/** Historical committed receipt, never current custody or consumer authority. */
export function admitRetainedInputResult(plan: RetainedInputPlan, saved: Readonly<{cid: string; wire: string}>): RetainedInputResult {
  const owned = requireHandle(retainedInputPlans, plan);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputResultWire');
  const value = checked(owner.clientValuesHostAdmitRetainedInputResult(
    owned, saved.wire, saved.cid), 'RunHostRetainedInputResultRejected');
  return handle(retainedInputResults, value, 'retained-input-result');
}

/** These immutable facts must be persisted and joined to current trusted Owners. */
export function retainedInputResultFacts(result: RetainedInputResult): Readonly<{
  cid: string; wire: string; planCid: string;
  transferReply: Readonly<{requestCid: string; wire: string}>;
  receipt: Readonly<{cid: string; wire: string}>;
}> {
  const values = checked(owner.clientValuesHostRetainedInputResultFacts(
    requireHandle(retainedInputResults, result)), 'RunHostRetainedInputResultRejected');
  if (!Array.isArray(values) || values.length !== 7 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputResultProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1], planCid: values[2],
    transferReply: Object.freeze({requestCid: values[3], wire: values[4]}),
    receipt: Object.freeze({cid: values[5], wire: values[6]})});
}

/** The caller uses a new challenge for each authenticated live receiver query. */
export function prepareRetainedInputCurrentQuery(plan: RetainedInputPlan, queryId: string): RetainedInputCurrentQuery {
  if (typeof queryId !== 'string') throw new TypeError('InvalidRunHostRetainedInputQuery');
  const value = checked(owner.clientValuesHostPrepareRetainedInputCurrentQuery(
    requireHandle(retainedInputPlans, plan), queryId), 'RunHostRetainedInputCurrentRejected');
  return handle(retainedInputCurrentQueries, value, 'retained-input-current-query');
}

/** Revalidate current plan authority before offering the same exact query. */
export function retainedInputCurrentEnvelope(query: RetainedInputCurrentQuery): string {
  return checked(owner.clientValuesHostRetainedInputCurrentEnvelope(
    requireHandle(retainedInputCurrentQueries, query)), 'RunHostRetainedInputCurrentRejected');
}

/** Admit an exact live response; a stored reply never becomes current authority. */
export function admitRetainedInputCurrentReply(query: RetainedInputCurrentQuery, saved: Readonly<{cid: string; wire: string}>, limits: RetainedInputPlanLimits): RetainedInputCurrentReply {
  const owned = requireHandle(retainedInputCurrentQueries, query);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputCurrentWire');
  if (!exactRetainedFields(limits, retainedPlanLimitKeys) ||
      (['maxChunks', 'maxManifestBytes'] as const).some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > 2147483647) ||
      typeof limits.maxReferencedBytes !== 'bigint' || limits.maxReferencedBytes < 1n ||
      limits.maxReferencedBytes > retainedInt64Maximum) {
    throw new TypeError('InvalidRunHostRetainedInputCurrentLimits');
  }
  const value = checked(owner.clientValuesHostAdmitRetainedInputCurrentReply(
    owned, saved.wire, saved.cid, limits.maxChunks, limits.maxManifestBytes,
    limits.maxReferencedBytes), 'RunHostRetainedInputCurrentRejected');
  return handle(retainedInputCurrentReplies, value, 'retained-input-current-reply');
}

/** Immutable snapshot, not permission to borrow, reserve, start or replay. */
export function retainedInputCurrentReplyFacts(reply: RetainedInputCurrentReply): Readonly<{
  cid: string; wire: string; transferRecordWire: string;
  receipt: Readonly<{cid: string; wire: string}>;
}> {
  const values = checked(owner.clientValuesHostRetainedInputCurrentReplyFacts(
    requireHandle(retainedInputCurrentReplies, reply)), 'RunHostRetainedInputCurrentRejected');
  if (!Array.isArray(values) || values.length !== 5 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputCurrentProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1], transferRecordWire: values[2],
    receipt: Object.freeze({cid: values[3], wire: values[4]})});
}

const retainedCurrentKeys = ['readTransfer', 'siteBindingCurrent', 'authority',
  'nowUnixMs', 'authorized'] as const;

/** Ports must query existing current owners, never the saved binding itself. */
export function prepareRetainedTaskInput(producer: RetainedInputProducer, receipt: Readonly<{cid: string; wire: string}>, destinationUseId: string,
  current: RetainedInputCurrent, limits: RetainedInputLimits): RetainedTaskInput {
  const owned = requireHandle(retainedInputProducers, producer);
  if (receipt === null || typeof receipt !== 'object' || Array.isArray(receipt) ||
      Object.keys(receipt).sort().join('\0') !== 'cid\0wire' ||
      typeof receipt.cid !== 'string' || typeof receipt.wire !== 'string' ||
      typeof destinationUseId !== 'string' || !destinationUseId ||
      current === null || typeof current !== 'object' || Array.isArray(current) ||
      Object.keys(current).sort().join('\0') !== [...retainedCurrentKeys].sort().join('\0') ||
      retainedCurrentKeys.some(key => typeof current[key] !== 'function')) {
    throw new TypeError('InvalidRunHostRetainedInputCurrent');
  }
  if (limits === null || typeof limits !== 'object' || Array.isArray(limits) ||
      Object.keys(limits).sort().join('\0') !==
        'maxBindingBytes\0maxChunks\0maxManifestBytes\0maxReferencedBytes' ||
      (['maxBindingBytes', 'maxChunks', 'maxManifestBytes'] as const).some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > 2147483647) ||
      typeof limits.maxReferencedBytes !== 'bigint' || limits.maxReferencedBytes < 1n ||
      limits.maxReferencedBytes > 9223372036854775807n) {
    throw new TypeError('InvalidRunHostRetainedInputLimits');
  }
  // Capture the installed functions so replacing properties cannot replace an
  // Owner port; each invocation still reads that Owner's current live state.
  const {readTransfer, siteBindingCurrent, authority, nowUnixMs, authorized} = current;
  const stringResult = (read: () => unknown, code: string) => () => {
    const value = read();
    if (typeof value !== 'string') throw new TypeError(code);
    return value;
  };
  const booleanResult = (value: unknown, code: string) => {
    if (typeof value !== 'boolean') throw new TypeError(code);
    return value;
  };
  const input = checked(owner.clientValuesHostPrepareRetainedTaskInput(owned,
    stringResult(readTransfer, 'InvalidRunHostRetainedTransferCurrent'),
    receipt.wire, receipt.cid, destinationUseId,
    (key, generation, bundle) => booleanResult(
      siteBindingCurrent(key, Number(generation), bundle),
      'InvalidRunHostRetainedSiteCurrent'),
    stringResult(authority, 'InvalidRunHostRetainedAuthority'),
    () => {
      const value = nowUnixMs();
      if (typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) {
        throw new TypeError('InvalidRunHostRetainedClock');
      }
      return value;
    },
    (dispatchCid, transferRequestWire) => booleanResult(
      authorized(dispatchCid, transferRequestWire),
      'InvalidRunHostRetainedAuthorization'),
    limits.maxChunks, limits.maxManifestBytes, limits.maxReferencedBytes,
    limits.maxBindingBytes), 'RunHostRetainedTaskInputRejected');
  return handle(retainedTaskInputs, input, 'retained-task-input');
}

/** Restore the exact saved binding against newly installed current owners. */
export function admitRetainedTaskInput(producer: RetainedInputProducer, saved: Readonly<{cid: string; wire: string}>, receipt: Readonly<{cid: string; wire: string}>,
  destinationUseId: string, current: RetainedInputCurrent, limits: RetainedInputLimits): RetainedTaskInput {
  if (saved === null || typeof saved !== 'object' || Array.isArray(saved) ||
      Object.keys(saved).sort().join('\0') !== 'cid\0wire' ||
      typeof saved.cid !== 'string' || typeof saved.wire !== 'string') {
    throw new TypeError('InvalidRunHostRetainedTaskInputWire');
  }
  const restored = prepareRetainedTaskInput(producer, receipt, destinationUseId,
    current, limits);
  const value = checked(owner.clientValuesHostAdmitRetainedTaskInput(
    requireHandle(retainedTaskInputs, restored), saved.wire, saved.cid),
  'RunHostRetainedTaskInputRejected');
  return handle(retainedTaskInputs, value, 'retained-task-input');
}

export function validateRetainedTaskInput(input: RetainedTaskInput): void {
  checked(owner.clientValuesHostValidateRetainedTaskInput(
    requireHandle(retainedTaskInputs, input)), 'RunHostRetainedTaskInputRejected');
}

/** Historical wire grants no physical material access or start claim. */
export function retainedTaskInputFacts(input: RetainedTaskInput): Readonly<{
  cid: string; wire: string;
}> {
  const values = owner.clientValuesHostRetainedTaskInputFacts(
    requireHandle(retainedTaskInputs, input));
  if (!Array.isArray(values) || values.length !== 2 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedTaskInputProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1]});
}

export function issueRetainedTaskDispatch(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, request: RequestIdentity, task: number, selection: ValuesSiteSelection, input: RetainedTaskInput): Readonly<{
  cid: string; wire: string;
}> {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647 ||
      selection === null || typeof selection !== 'object' || Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !== [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const source = sourcePreparations.get(prepared);
  const args = [
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    task, selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid, selection.budgetCid,
    selection.evidenceIssuerCapabilityCid, selection.grantCid,
    requireHandle(retainedTaskInputs, input)] as const;
  const dispatch = checked(source === undefined
    ? owner.clientValuesHostPrepareRetainedTaskDispatch(...args)
    : owner.clientValuesHostPrepareRetainedTaskDispatchWithSource(...args, source.value), 'RunHostRetainedTaskDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostRetainedTaskDispatchRejected')});
}

export function issueTaskDispatch(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, request: RequestIdentity, task: number, selection: ValuesSiteSelection): Readonly<{cid: string; wire: string}> {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647 ||
      selection === null || typeof selection !== 'object' ||
      Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !==
        [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const source = sourcePreparations.get(prepared);
  const args = [
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    task, selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid,
    selection.budgetCid, selection.evidenceIssuerCapabilityCid,
    selection.grantCid] as const;
  const dispatch = checked(source === undefined
    ? owner.clientValuesHostPrepareTaskDispatch(...args)
    : owner.clientValuesHostPrepareTaskDispatchWithSource(...args, source.value), 'RunHostDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostDispatchRejected')});
}

// The current Host authorization and Site policy decision precede issuance.
// The returned canonical wire is identity material, not a Site credential.
export function issueSourceFreeDispatch(prepared: PreparedProgram, compilation: ValuesCompilation, admission: RunAdmission,
  definition: RunDefinition, request: RequestIdentity, selection: ValuesSiteSelection): Readonly<{cid: string; wire: string}> {
  if (selection === null || typeof selection !== 'object' ||
      Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !==
        [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const dispatch = checked(owner.clientValuesHostPrepareDispatch(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid,
    selection.budgetCid, selection.evidenceIssuerCapabilityCid,
    selection.grantCid), 'RunHostDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostDispatchRejected')});
}

function publicationLimits(limits: PublicationLimits) {
  if (limits === null || typeof limits !== 'object' ||
      !(['maxWireBytes', 'maxNodes', 'maxDepth'] as const).every(key =>
        Number.isSafeInteger(limits[key]) && limits[key] > 0 &&
        limits[key] <= 2147483647)) {
    throw new TypeError('InvalidRunHostPublicationLimits');
  }
  return limits;
}

function publicationContract<Kind extends string = string>(value: owner.PublicationContract): PublicationContract<Kind> {
  const token = handle(publicationContracts, value, 'publication-contract') as PublicationContract<Kind>['token'];
  const contract = Object.freeze({token,
    cid: owner.clientValuesHostPublicationContractIdentity(value),
    wire: owner.clientValuesHostPublicationContractWire(value)});
  publicationOriginals.set(contract, Object.freeze({value,
    cid: contract.cid, wire: contract.wire}));
  return contract;
}

function runEvidence(value: owner.RunEvidenceValue) {
  const token = handle(runEvidences, value, 'run-evidence');
  return Object.freeze({token,
    cid: owner.clientValuesHostRunEvidenceValueIdentity(value),
    wire: owner.clientValuesHostRunEvidenceValueWire(value)});
}

export function admitRunEvidenceValue(name: string, wire: string, limits: PublicationLimits): RunEvidence {
  if (typeof name !== 'string' || typeof wire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return runEvidence(checked(owner.clientValuesHostAdmitRunEvidenceValue(
    name, wire, maxWireBytes, maxNodes, maxDepth),
  'RunHostEvidenceRejected'));
}

/** Binding DATA from the same admitted Review. No parsing, admission, current
 * permission or outcome follows from this immutable projection. */
export function effectReviewProjectionBindingFacts(review: RunEvidence): Readonly<{
  previewCid: string;
  authoringContextCid: string;
  authorityScopeCid: string;
  approvalClaims: readonly string[];
}> {
  const fields = owner.clientValuesHostEffectReviewProjectionBindingFacts(
    requireHandle(runEvidences, review?.token));
  if (!Array.isArray(fields) || fields.length < 3 ||
      fields.some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostReviewProjection');
  }
  return Object.freeze({previewCid: fields[0], authoringContextCid: fields[1],
    authorityScopeCid: fields[2], approvalClaims: Object.freeze(fields.slice(3))});
}

export function sealRunEvidenceValue(name: string, bodyWire: string, limits: PublicationLimits): RunEvidence {
  if (typeof name !== 'string' || typeof bodyWire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return runEvidence(checked(owner.clientValuesHostSealRunEvidenceValue(
    name, bodyWire, maxWireBytes, maxNodes, maxDepth),
  'RunHostEvidenceRejected'));
}

// Canonical admission and chain decisions belong to the portable owner.
// A contract handle is in-process only and conveys no publication authority.
export function admitPublicationContract<Name extends string>(name: Name, wire: string, limits: PublicationLimits): PublicationContract<Name> {
  if (typeof name !== 'string' || typeof wire !== 'string') {
    throw new TypeError('InvalidRunHostPublicationContract');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(owner.clientValuesHostAdmitPublicationContract(
    name, wire, maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationContractRejected');
  return publicationContract(value);
}

function publicationToken(contract: PublicationContract) {
  return requireHandle(publicationContracts, contract?.token);
}

export function projectPublicationSnapshot(record: PublicationContract | undefined, index: PublicationIndexObservation): Readonly<{
    state: 'not_started' | 'preparing' | 'committing' |
      'publication_unknown' | 'succeeded' | 'failed' | 'cancelled';
    evidenceCid: string | undefined;
  }> {
  if (index === null || typeof index !== 'object' ||
      Array.isArray(index) ||
      !['absent', 'unknown', 'committed'].includes(index.kind) ||
      Object.keys(index).sort().join('\0') !==
        (index.kind === 'committed' ? 'entry\0kind' : 'kind')) {
    throw new TypeError('InvalidRunHostIndexObservation');
  }
  const mode = index.kind === 'absent' ? 0 :
    index.kind === 'unknown' ? 1 : 2;
  const facts = checked(owner.clientValuesHostProjectPublicationSnapshot(
    record === undefined ? undefined : publicationToken(record), mode,
    mode === 2 ? publicationToken((index as Extract<PublicationIndexObservation, {kind: 'committed'}>).entry): undefined),
  'RunHostPublicationSnapshotRejected');
  if (!Array.isArray(facts) || facts.length !== 2 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostPublicationSnapshot');
  }
  return Object.freeze({state: facts[0] as ReturnType<typeof projectPublicationSnapshot>['state'],
    evidenceCid: facts[1] || undefined});
}

export function publicationIndexScopeKey(ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>, limits: PublicationLimits): string {
  if (ref === null || typeof ref !== 'object' || Array.isArray(ref) ||
      Object.keys(ref).sort().join('\0') !==
        'authorityScopeCid\0namespaceId\0runDefinitionCid' ||
      !(['namespaceId', 'authorityScopeCid', 'runDefinitionCid'] as const)
        .every(key => typeof ref[key] === 'string')) {
    throw new TypeError('InvalidRunHostPublicationIndexScope');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostPublicationIndexScopeKey(
    ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid,
    maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationIndexScopeRejected');
}

function nonnegativeCount(value: number): number;
function nonnegativeCount(value: bigint): bigint;
function nonnegativeCount(value: bigint | number): bigint | number;
function nonnegativeCount(value: bigint | number) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 2147483647) {
    throw new TypeError('InvalidRunHostPublicationCount');
  }
  return value;
}

export function issueResultOccurrenceEvidence(definition: PublicationContract, facts: Readonly<{
    logicalValueCid: string;
    resultSchemaCid: string;
    computationContractCid: string;
    inputRelationCids: readonly string[];
    scopeCid: string;
    effectiveDataPolicyCid: string;
    issuerId: string;
    authorityScopeCid: string;
  }>, limits: PublicationLimits): ResultOccurrenceEvidence {
  if (facts === null || typeof facts !== 'object' ||
      !(['logicalValueCid', 'resultSchemaCid', 'computationContractCid',
        'scopeCid', 'effectiveDataPolicyCid', 'issuerId',
        'authorityScopeCid'] as const).every(key => typeof facts[key] === 'string') ||
      !Array.isArray(facts.inputRelationCids) ||
      !facts.inputRelationCids.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostResultEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(owner.clientValuesHostIssueResultOccurrenceEvidence(
    publicationToken(definition), facts.logicalValueCid,
    facts.resultSchemaCid, facts.computationContractCid,
    facts.inputRelationCids, facts.scopeCid,
    facts.effectiveDataPolicyCid, facts.issuerId,
    facts.authorityScopeCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostResultEvidenceRejected');
  return resultOccurrence(value);
}

/** Admit the original saved evidence against independently observed facts.
 * This does not issue replacement scope, issuer, derivation or ordering. */
export function admitOriginalResultOccurrenceEvidence(definition: PublicationContract, artifact: PublicationContract,
  derivation: PublicationContract, ordering: PublicationContract, retention: PublicationContract, facts: Readonly<{logicalValueCid: string; resultSchemaCid: string;
    effectiveDataPolicyCid: string}>): ResultOccurrenceEvidence {
  if (facts === null || typeof facts !== 'object' ||
      Object.keys(facts).sort().join('\0') !==
        'effectiveDataPolicyCid\0logicalValueCid\0resultSchemaCid') {
    throw new TypeError('InvalidRunHostOriginalResultEvidence');
  }
  const selected = Object.getOwnPropertyDescriptors(facts);
  const fields = ['logicalValueCid','resultSchemaCid','effectiveDataPolicyCid'].map(name => {
    const field = selected[name];
    if (!field?.enumerable || !Object.hasOwn(field,'value') || typeof field.value !== 'string') {
      throw new TypeError('InvalidRunHostOriginalResultEvidence');
    }
    return field.value;
  }) as [string, string, string];
  return resultOccurrence(checked(owner.clientValuesHostAdmitOriginalResultOccurrenceEvidence(
    publicationToken(definition), publicationToken(artifact), publicationToken(derivation),
    publicationToken(ordering), publicationToken(retention), ...fields),
  'RunHostOriginalResultEvidenceRejected'));
}

function resultOccurrence(value: owner.ResultOrderingEvidence) {
  const token = handle(resultOccurrences, value, 'result-occurrence');
  return Object.freeze({token,
    derivation: publicationContract(
      owner.clientValuesHostResultOccurrenceDerivation(value)),
    ordering: publicationContract(
      owner.clientValuesHostResultOccurrenceOrdering(value))});
}

export function issueCheckedValuesResultOccurrenceEvidence(prepared: PreparedProgram,
  compilation: ValuesCompilation, definition: PublicationContract, facts: Readonly<{
    logicalValueCid: string;
    resultSchemaCid: string;
    scopeCid: string;
    effectiveDataPolicyCid: string;
    issuerId: string;
    authorityScopeCid: string;
  }>, limits: PublicationLimits): ResultOccurrenceEvidence {
  if (facts === null || typeof facts !== 'object' ||
      Object.keys(facts).sort().join('\0') !==
        ['logicalValueCid', 'resultSchemaCid', 'scopeCid',
          'effectiveDataPolicyCid', 'issuerId', 'authorityScopeCid']
          .sort().join('\0') ||
      Object.values(facts).some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostCheckedResultEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(
    owner.clientValuesHostIssueCheckedValuesResultOccurrenceEvidence(
      requireHandle(preparations, prepared), compiled.value,
      publicationToken(definition), facts.logicalValueCid,
      facts.resultSchemaCid, facts.scopeCid,
      facts.effectiveDataPolicyCid, facts.issuerId,
      facts.authorityScopeCid, maxWireBytes, maxNodes, maxDepth),
    'RunHostCheckedResultEvidenceRejected');
  return resultOccurrence(value);
}

export function issueCompleteResultArtifact(definition: PublicationContract, invocation: PublicationContract,
  evidence: ResultOccurrenceEvidence, retention: PublicationContract, actualRowCount: number, limits: PublicationLimits): PublicationContract {
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueCompleteResultArtifact(
      publicationToken(definition), publicationToken(invocation),
      requireHandle(resultOccurrences, evidence?.token),
      publicationToken(retention), nonnegativeCount(actualRowCount),
      maxWireBytes, maxNodes, maxDepth),
    'RunHostResultArtifactRejected'));
}

export function issueDurableResultBinding(runDefinition: PublicationContract, definition: PublicationContract,
  invocation: PublicationContract, artifact: PublicationContract, ordering: PublicationContract, retention: PublicationContract, physical: Readonly<{
    codecContractCid: string;
    resultFields: readonly string[];
    resultSchemaWire: string;
    materialGenerationCid: string;
    storeAuthorityCid: string;
    rowCount: number;
    byteCount: number;
    physicalSha256: string;
  }>, limits: PublicationLimits): PublicationContract {
  if (physical === null || typeof physical !== 'object' ||
      !(['codecContractCid', 'resultSchemaWire', 'materialGenerationCid',
        'storeAuthorityCid', 'physicalSha256'] as const).every(key =>
        typeof physical[key] === 'string') ||
      !Array.isArray(physical.resultFields) ||
      !physical.resultFields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostDurableBinding');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueDurableResultBinding(
      publicationToken(runDefinition), publicationToken(definition),
      publicationToken(invocation), publicationToken(artifact),
      publicationToken(ordering), publicationToken(retention),
      physical.codecContractCid, physical.resultFields,
      physical.resultSchemaWire, physical.materialGenerationCid,
      physical.storeAuthorityCid, nonnegativeCount(physical.rowCount),
      nonnegativeCount(physical.byteCount), physical.physicalSha256,
      maxWireBytes, maxNodes, maxDepth),
    'RunHostDurableBindingRejected'));
}

export function inspectCanonicalResultRows(rowsWire: string, fields: readonly string[], limits: PublicationLimits): Readonly<{logicalRelationCid: string; rowCount: number}> {
  if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
      !fields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostResultRows');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const result = checked(owner.clientValuesHostInspectCanonicalResultRows(
    rowsWire, fields, maxWireBytes, maxNodes, maxDepth),
  'RunHostResultRowsRejected');
  if (!Array.isArray(result) || result.length !== 2 ||
      typeof result[0] !== 'string' ||
      !/^sha256:[0-9a-f]{64}$/u.test(result[0]) ||
      typeof result[1] !== 'string' ||
      !/^(0|[1-9][0-9]*)$/u.test(result[1])) {
    throw new Error('InvalidRunHostResultRowsProjection');
  }
  const rowCount = Number(result[1]);
  if (!Number.isSafeInteger(rowCount)) {
    throw new Error('InvalidRunHostResultRowsProjection');
  }
  return Object.freeze({logicalRelationCid: result[0], rowCount});
}

export function issueResultManifest(runDefinition: PublicationContract, invocation: PublicationContract,
  definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[], limits: PublicationLimits): PublicationContract {
  if (!Array.isArray(definitions) || !Array.isArray(artifacts)) {
    throw new TypeError('InvalidRunHostPublicationChain');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssueResultManifest(
    publicationToken(runDefinition), publicationToken(invocation),
    definitions.map(publicationToken), artifacts.map(publicationToken),
    maxWireBytes, maxNodes, maxDepth), 'RunHostResultManifestRejected'));
}

export function validatePublicationChain(runDefinition: PublicationContract, invocation: PublicationContract,
  definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[], manifest: PublicationContract, limits: PublicationLimits): void {
  if (!Array.isArray(definitions) || !Array.isArray(artifacts)) {
    throw new TypeError('InvalidRunHostPublicationChain');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  checked(owner.clientValuesHostValidatePublicationChain(
    publicationToken(runDefinition), publicationToken(invocation),
    definitions.map(publicationToken), artifacts.map(publicationToken),
    publicationToken(manifest), maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationChainRejected');
}

export function validatePublicationRecordTransition(previous: PublicationRecordContract | undefined, next: PublicationRecordContract,
  uncommittedConfirmed: boolean): void {
  if (typeof uncommittedConfirmed !== 'boolean') {
    throw new TypeError('InvalidRunHostPublicationTransition');
  }
  checked(owner.clientValuesHostValidatePublicationRecordTransition(
    previous === undefined ? undefined : publicationToken(previous),
    publicationToken(next), uncommittedConfirmed),
  'RunHostPublicationTransitionRejected');
}

function publicationItems(values: readonly PublicationContract[]) {
  if (!Array.isArray(values)) throw new TypeError('InvalidRunHostInventory');
  return values.map(publicationToken);
}

export function issuePublicationRequest(runDefinition: PublicationContract, definitions: readonly PublicationContract[], facts: Readonly<{
    namespaceId: string;
    authorityScopeCid: string;
    publicationPolicyCid: string;
    publicationTargetCid: string;
    requestedAt: string;
  }>,
  limits: PublicationLimits): PublicationRequestContract {
  if (facts === null || typeof facts !== 'object' ||
      (['namespaceId', 'authorityScopeCid', 'publicationPolicyCid',
        'publicationTargetCid', 'requestedAt'] as const).some(key =>
        typeof facts[key] !== 'string')) {
    throw new TypeError('InvalidRunHostPublicationRequest');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssuePublicationRequest(
      publicationToken(runDefinition), publicationItems(definitions),
      facts.namespaceId, facts.authorityScopeCid,
      facts.publicationPolicyCid, facts.publicationTargetCid,
      facts.requestedAt, maxWireBytes, maxNodes, maxDepth),
    'RunHostPublicationRequestRejected'));
}

export function issuePublicationAttempt(request: PublicationRequestContract, runDefinition: PublicationContract, facts: Readonly<{
    attemptId: string;
    fenceCid: string;
    externalIdempotencyKey?: string;
    startedAt: string;
  }>,
  limits: PublicationLimits): PublicationAttemptContract {
  if (facts === null || typeof facts !== 'object' ||
      (['attemptId', 'fenceCid', 'startedAt'] as const).some(key =>
        typeof facts[key] !== 'string') ||
      facts.externalIdempotencyKey !== undefined &&
        typeof facts.externalIdempotencyKey !== 'string') {
    throw new TypeError('InvalidRunHostPublicationAttempt');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssuePublicationAttempt(
      publicationToken(request), publicationToken(runDefinition),
      facts.attemptId, facts.fenceCid, facts.externalIdempotencyKey,
      facts.startedAt, maxWireBytes, maxNodes, maxDepth),
    'RunHostPublicationAttemptRejected'));
}

export function issuePublicIndexEntry(runDefinition: PublicationContract, invocation: PublicationContract, manifest: PublicationContract,
  receipt: PublicationContract, capturedRun: PublicationContract, durableBindings: readonly PublicationContract[], request: PublicationRequestContract, attempt: PublicationAttemptContract, committedAt: string,
  limits: PublicationLimits): PublicIndexEntryContract {
  if (typeof committedAt !== 'string') {
    throw new TypeError('InvalidRunHostPublicIndexEntry');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssuePublicIndexEntry(
    publicationToken(runDefinition), publicationToken(invocation),
    publicationToken(manifest), publicationToken(receipt),
    publicationToken(capturedRun), publicationItems(durableBindings),
    publicationToken(request), publicationToken(attempt), committedAt,
    maxWireBytes, maxNodes, maxDepth), 'RunHostPublicIndexEntryRejected'));
}

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
  attempt: PublicationAttemptContract, indexEntry: PublicIndexEntryContract, limits: PublicationLimits): void {
  if (evidence === null || typeof evidence !== 'object' ||
      !Array.isArray(evidence.definitions) ||
      !Array.isArray(evidence.artifacts) ||
      !Array.isArray(evidence.derivations) ||
      !Array.isArray(evidence.orderings) ||
      !Array.isArray(evidence.retentions) ||
      !Array.isArray(evidence.durableBindings)) {
    throw new TypeError('InvalidRunHostPublicationCommit');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  checked(owner.clientValuesHostValidateEffectFreePublicationCommit(
    publicationToken(evidence.runDefinition),
    publicationToken(evidence.invocation),
    publicationItems(evidence.definitions),
    publicationItems(evidence.artifacts),
    publicationItems(evidence.derivations),
    publicationItems(evidence.orderings),
    publicationItems(evidence.retentions),
    publicationItems(evidence.durableBindings),
    publicationToken(evidence.manifest),
    publicationToken(evidence.receipt),
    publicationToken(evidence.capturedRun),
    publicationToken(request), publicationToken(attempt),
    publicationToken(indexEntry), maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationCommitRejected');
}

// Historical semantic DATA only. Current apply permission, physical outcomes
// and Store commit remain duties of their original owners.
export function admitEffectPreviewIdentity(wire: string, expectedRunIdentityCid: string,
  expectedAuthoringContextCid: string, limits: PublicationLimits): EffectPreviewIdentity {
  if (typeof wire !== 'string' || typeof expectedRunIdentityCid !== 'string' ||
      typeof expectedAuthoringContextCid !== 'string') {
    throw new TypeError('InvalidRunHostEffectPreview');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(
    owner.clientValuesHostAdmitEffectPreviewIdentity(wire,
      expectedRunIdentityCid, expectedAuthoringContextCid,
      maxWireBytes, maxNodes, maxDepth), 'RunHostEffectPreviewRejected');
  return handle(effectPreviewIdentities, {value,
    memberCount: owner.clientValuesHostEffectPreviewMemberCount(value)},
  'effect-preview-identity');
}

export function effectPreviewIdentityCid(preview: EffectPreviewIdentity): string {
  return owner.clientValuesHostEffectPreviewSemanticIdentity(
    requireHandle(effectPreviewIdentities, preview).value);
}

function effectReceiptWires(preview: Readonly<{memberCount: number}>, setReceiptWire: string,
  memberReceiptWires: readonly string[]) {
  if (typeof setReceiptWire !== 'string' || !Array.isArray(memberReceiptWires) ||
      memberReceiptWires.length !== preview.memberCount) {
    throw new TypeError('InvalidRunHostEffectReceipts');
  }
  const members = [];
  for (let index = 0; index < preview.memberCount; index++) {
    const wire = memberReceiptWires[index];
    if (typeof wire !== 'string') {
      throw new TypeError('InvalidRunHostEffectReceipts');
    }
    members.push(wire);
  }
  return {setReceiptWire, memberReceiptWires: members};
}

export function issueEffectfulFinalRunReceipt(runDefinition: PublicationContract, computationReceipt: PublicationContract,
  capturedRun: PublicationContract, preview: EffectPreviewIdentity, setReceiptWire: string, memberReceiptWires: readonly string[], limits: PublicationLimits): PublicationContract {
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const originalPreview = requireHandle(effectPreviewIdentities, preview);
  const receipts = effectReceiptWires(originalPreview, setReceiptWire, memberReceiptWires);
  return publicationContract(checked(
    owner.clientValuesHostIssueEffectfulFinalRunReceipt(
      publicationToken(runDefinition), publicationToken(computationReceipt),
      publicationToken(capturedRun), originalPreview.value,
      receipts.setReceiptWire, receipts.memberReceiptWires,
      maxWireBytes, maxNodes, maxDepth), 'RunHostEffectfulFinalReceiptRejected'));
}

type EffectFinalOriginals = Omit<EffectfulPublicationCommitEvidence, 'durableBindings'>;
function effectFinalOriginals(evidence: EffectFinalOriginals): EffectFinalOriginals {
  if (evidence === null || typeof evidence !== 'object' || Array.isArray(evidence)) {
    throw new TypeError('InvalidRunHostEffectfulPublicationCommit');
  }
  const fields = Object.getOwnPropertyDescriptors(evidence), selected: Partial<Record<keyof EffectFinalOriginals, unknown>> = {};
  const own = (name: keyof EffectFinalOriginals) => {
    const field = fields[name];
    if (!field?.enumerable || !Object.hasOwn(field,'value')) {
      throw new TypeError('InvalidRunHostEffectfulPublicationCommit');
    }
    return field.value;
  };
  for (const name of ['runDefinition','invocation','manifest','computationReceipt',
    'capturedRun','preview','setReceiptWire','finalReceipt'] as const) selected[name] = own(name);
  for (const name of ['definitions','artifacts','derivations','orderings','retentions','memberReceiptWires'] as const) {
    const values = own(name), length = Object.getOwnPropertyDescriptor(values ?? {},'length');
    if (!Array.isArray(values) || !Object.hasOwn(length ?? {},'value') ||
        !Number.isSafeInteger(length!.value) || length!.value < 0 || length!.value > 2147483647) {
      throw new TypeError('InvalidRunHostEffectfulPublicationCommit');
    }
    const items = [];
    for (let index = 0; index < length!.value; index++) {
      const field = Object.getOwnPropertyDescriptor(values,index);
      if (!field?.enumerable || !Object.hasOwn(field,'value')) {
        throw new TypeError('InvalidRunHostEffectfulPublicationCommit');
      }
      items.push(field.value);
    }
    selected[name] = Object.freeze(items);
  }
  return Object.freeze(selected) as EffectFinalOriginals;
}

/** Complete original computation/Result/Set admission once. The returned
 * existing final Receipt retains that proof privately; it grants no action. */
export function admitEffectfulFinalRunEvidence(evidence: Omit<EffectfulPublicationCommitEvidence,'durableBindings'>, limits: PublicationLimits): PublicationContract {
  const {maxWireBytes,maxNodes,maxDepth} = publicationLimits(limits);
  const original = effectFinalOriginals(evidence);
  const preview = requireHandle(effectPreviewIdentities,original.preview);
  const receipts = effectReceiptWires(preview,original.setReceiptWire,original.memberReceiptWires);
  const value = checked(owner.clientValuesHostAdmitEffectfulFinalRunEvidence(
    publicationToken(original.runDefinition),publicationToken(original.invocation),
    publicationItems(original.definitions),publicationItems(original.artifacts),
    publicationItems(original.derivations),publicationItems(original.orderings),
    publicationItems(original.retentions),publicationToken(original.manifest),
    publicationToken(original.computationReceipt),publicationToken(original.capturedRun),preview.value,
    receipts.setReceiptWire,receipts.memberReceiptWires,publicationToken(original.finalReceipt),
    maxWireBytes,maxNodes,maxDepth),'RunHostEffectfulFinalEvidenceRejected');
  const receipt = publicationContract(owner.clientValuesHostEffectfulFinalRunReceipt(value));
  const returned = publicationOriginals.get(receipt)!;
  publicationOriginals.set(receipt,Object.freeze({...returned,effect:{value,original,
    validatedPublication:undefined}}));
  return receipt;
}

function retainedEffectFinal(receipt: PublicationContract | undefined) {
  const retained = publicationOriginals.get(receipt as PublicationContract)?.effect;
  if (retained === undefined) throw new TypeError('ForeignRunHostEffectFinalEvidence');
  return retained;
}

/** Immutable admitted outcome only. No raw receipt parsing, current/permission
 * check, retry, Store observation or physical acknowledgement occurs here. */
export function effectfulFinalRunOutcome(receipt: PublicationContract): Readonly<{
  status: 'succeeded' | 'needs_reconciliation' | 'failed'; allUnattempted: boolean}> {
  const value = retainedEffectFinal(receipt).value;
  const status = owner.clientValuesHostEffectfulFinalRunStatus(value);
  const allUnattempted = owner.clientValuesHostEffectfulFinalRunAllUnattempted(value);
  if (!['succeeded','needs_reconciliation','failed'].includes(status) || typeof allUnattempted !== 'boolean') {
    throw new TypeError('InvalidRunHostEffectFinalOutcome');
  }
  return Object.freeze({status: status as ReturnType<typeof effectfulFinalRunOutcome>['status'], allUnattempted});
}

/** Existing Unknown-only writer over the same complete admitted partition.
 * This is historical Run state DATA, never a retry, current grant or ACK. */
export function effectfulFinalRunReconciliationState(receipt: PublicationContract, updatedAt: string, limits: PublicationLimits): string {
  if (typeof updatedAt !== 'string') throw new TypeError('InvalidRunHostStateObservation');
  const {maxWireBytes,maxNodes,maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostEffectfulFinalRunReconciliationState(
    retainedEffectFinal(receipt).value,updatedAt,maxWireBytes,maxNodes,maxDepth),
  'RunHostEffectReconciliationStateRejected');
}

/** Known failure from the same complete admitted final chain and original
 * manifest. No current grant, publication, resend or cleanup acknowledgement. */
export function effectfulFinalRunFailedState(receipt: PublicationContract, updatedAt: string, limits: PublicationLimits): string {
  if (typeof updatedAt !== 'string') throw new TypeError('InvalidRunHostStateObservation');
  const {maxWireBytes,maxNodes,maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostEffectfulFinalRunFailedState(
    retainedEffectFinal(receipt).value,updatedAt,maxWireBytes,maxNodes,maxDepth),
  'RunHostEffectFailedStateRejected');
}

export function validateEffectfulPublicationCommit(evidence: EffectfulPublicationCommitEvidence, request: PublicationRequestContract,
  attempt: PublicationAttemptContract, indexEntry: PublicIndexEntryContract, limits: PublicationLimits): void {
  if (evidence === null || typeof evidence !== 'object') {
    throw new TypeError('InvalidRunHostEffectfulPublicationCommit');
  }
  // Once this same original is selected, even a later DATA getter or bounds
  // refusal cannot leave an older publication check available as this attempt.
  const selectedReceipt = Object.getOwnPropertyDescriptor(evidence,'finalReceipt');
  const selectedRetained = selectedReceipt !== undefined && Object.hasOwn(selectedReceipt,'value')
    ? publicationOriginals.get(selectedReceipt.value)?.effect : undefined;
  if (selectedRetained !== undefined) selectedRetained.validatedPublication = undefined;
  const {runDefinition, invocation, definitions, artifacts, derivations, orderings,
    retentions, durableBindings, manifest, computationReceipt, capturedRun,
    preview, setReceiptWire, memberReceiptWires, finalReceipt} = evidence;
  const retained = publicationOriginals.get(finalReceipt)?.effect;
  if (retained !== undefined) retained.validatedPublication = undefined;
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  if (retained !== undefined) {
    const selected = effectFinalOriginals(evidence);
    for (const [name,original] of Object.entries(retained.original)) {
      if (name === 'finalReceipt') continue;
      const value = selected[name as keyof EffectFinalOriginals];
      if (Array.isArray(original) ? (value as readonly unknown[]).length !== original.length ||
          original.some((item,index) => item !== (value as readonly unknown[])[index]): original !== value) {
        throw new TypeError('ForeignRunHostEffectFinalEvidence');
      }
    }
    const index = checked(owner.clientValuesHostValidateRetainedEffectfulPublicationCommit(
      retained.value,publicationItems(durableBindings),publicationToken(request),
      publicationToken(attempt),publicationToken(indexEntry)), 'RunHostEffectfulPublicationCommitRejected');
    // Immutable validated index facts are not a Store CAS/commit observation.
    retained.validatedPublication = index;
    return;
  }
  const originalPreview = requireHandle(effectPreviewIdentities, preview);
  const receipts = effectReceiptWires(originalPreview, setReceiptWire, memberReceiptWires);
  checked(owner.clientValuesHostValidateEffectfulPublicationCommit(
    publicationToken(runDefinition), publicationToken(invocation),
    publicationItems(definitions), publicationItems(artifacts),
    publicationItems(derivations), publicationItems(orderings),
    publicationItems(retentions), publicationItems(durableBindings),
    publicationToken(manifest), publicationToken(computationReceipt),
    publicationToken(capturedRun), originalPreview.value,
    receipts.setReceiptWire, receipts.memberReceiptWires,
    publicationToken(finalReceipt), publicationToken(request),
    publicationToken(attempt), publicationToken(indexEntry),
    maxWireBytes, maxNodes, maxDepth), 'RunHostEffectfulPublicationCommitRejected');
}

export function issuePublicationRecord(attempt: PublicationAttemptContract, previous: PublicationRecordContract | undefined, facts: Readonly<{
    state: string;
    observedAt: string;
    publicIndexEntry?: PublicIndexEntryContract;
    failureCid?: string;
    cleanupOwnerCids: readonly string[];
    uncommittedConfirmed: boolean;
  }>, limits: PublicationLimits): PublicationRecordContract {
  if (facts === null || typeof facts !== 'object' ||
      typeof facts.state !== 'string' ||
      typeof facts.observedAt !== 'string' ||
      facts.failureCid !== undefined &&
        typeof facts.failureCid !== 'string' ||
      !Array.isArray(facts.cleanupOwnerCids) ||
      !facts.cleanupOwnerCids.every(value => typeof value === 'string') ||
      typeof facts.uncommittedConfirmed !== 'boolean') {
    throw new TypeError('InvalidRunHostPublicationRecord');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssuePublicationRecord(
    publicationToken(attempt), previous === undefined ? undefined :
      publicationToken(previous), facts.state, facts.observedAt,
    facts.publicIndexEntry === undefined ? undefined :
      publicationToken(facts.publicIndexEntry), facts.failureCid,
    facts.cleanupOwnerCids, facts.uncommittedConfirmed,
    maxWireBytes, maxNodes, maxDepth), 'RunHostPublicationRecordRejected'));
}

function evidenceItems(values: readonly RunEvidence[]) {
  if (!Array.isArray(values)) {
    throw new TypeError('InvalidRunHostEvidenceInventory');
  }
  return values.map(value => requireHandle(runEvidences, value?.token));
}

export function issueEffectFreeRunReceipt(admission: RunAdmission, runDefinition: PublicationContract,
  invocation: PublicationContract, observation: RunEvidence, definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[], manifest: PublicationContract,
  normalizationJournal: RunEvidence, facts: Readonly<{
    bindingNames: readonly string[];
    bindingDigests: readonly string[];
    sourceEvidence: readonly RunEvidence[];
    modelEvidence: readonly RunEvidence[];
    barrierAttemptReceiptCids: readonly string[];
  }>, limits: PublicationLimits): PublicationContract {
  if (facts === null || typeof facts !== 'object' ||
      !Array.isArray(facts.bindingNames) ||
      !facts.bindingNames.every(value => typeof value === 'string') ||
      !Array.isArray(facts.bindingDigests) ||
      !facts.bindingDigests.every(value => typeof value === 'string') ||
      !Array.isArray(facts.barrierAttemptReceiptCids) ||
      !facts.barrierAttemptReceiptCids.every(value =>
        typeof value === 'string')) {
    throw new TypeError('InvalidRunHostReceiptFacts');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueEffectFreeRunReceipt(
      requireHandle(admissions, admission).value,
      publicationToken(runDefinition), publicationToken(invocation),
      requireHandle(runEvidences, observation?.token),
      publicationItems(definitions), publicationItems(artifacts),
      publicationToken(manifest),
      requireHandle(runEvidences, normalizationJournal?.token),
      facts.bindingNames, facts.bindingDigests,
      evidenceItems(facts.sourceEvidence),
      evidenceItems(facts.modelEvidence),
      facts.barrierAttemptReceiptCids,
      maxWireBytes, maxNodes, maxDepth),
    'RunHostReceiptRejected'));
}

export function admitCapturedResultSnapshot(definition: PublicationContract, artifact: PublicationContract, rowsWire: string,
  fields: readonly string[], limits: PublicationLimits): CapturedResultSnapshot {
  if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
      !fields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostCapturedRows');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const snapshot = checked(owner.clientValuesHostAdmitCapturedResultSnapshot(
    publicationToken(definition), publicationToken(artifact), rowsWire,
    fields, maxWireBytes, maxNodes, maxDepth),
  'RunHostCapturedRowsRejected');
  return handle(capturedSnapshots, snapshot, 'captured-result-snapshot');
}

export function issueSourceFreeCapturedRun(runDefinition: PublicationContract, invocation: PublicationContract,
  definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[], manifest: PublicationContract, receipt: PublicationContract, snapshots: readonly CapturedResultSnapshot[], authoring: RunEvidence, models: readonly RunEvidence[],
  limits: PublicationLimits): PublicationContract {
  return issueReadOnlyCapturedRun(runDefinition, invocation, definitions,
    artifacts, manifest, receipt, snapshots, authoring, models, limits);
}

// Read-only Sources, like Values, have no pending source-state advances.
// The same receipt and captured-computation owner validates the full chain.
export function issueReadOnlyCapturedRun(runDefinition: PublicationContract, invocation: PublicationContract,
  definitions: readonly PublicationContract[], artifacts: readonly PublicationContract[], manifest: PublicationContract, receipt: PublicationContract, snapshots: readonly CapturedResultSnapshot[], authoring: RunEvidence, models: readonly RunEvidence[],
  limits: PublicationLimits): PublicationContract {
  if (!Array.isArray(snapshots)) {
    throw new TypeError('InvalidRunHostCapturedInventory');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueSourceFreeCapturedRun(
      publicationToken(runDefinition), publicationToken(invocation),
      publicationItems(definitions), publicationItems(artifacts),
      publicationToken(manifest), publicationToken(receipt),
      snapshots.map(value => requireHandle(capturedSnapshots, value)),
      requireHandle(runEvidences, authoring?.token), evidenceItems(models),
      maxWireBytes, maxNodes, maxDepth),
    'RunHostCapturedRunRejected'));
}

// The portable publication service consumes this shape. Each view keeps its
// MoonBit handle in this instance; wire bytes and CIDs alone grant no access.
const deliveryViews = new WeakMap<DeliveryContractView, PublicationContract>();
const accessProgress = new WeakMap<ResultAccessProgress, owner.ResultAccessProgress>();
const deliverySerializers = new WeakMap<ResultDeliverySerializer, owner.ResultDeliverySerializer>();
const durableRowFrames = new WeakMap<DurableResultRowFrames, owner.DurableResultRowFrames>();

type OwnerMethod = {
  [Name in keyof typeof owner]: (typeof owner)[Name] extends (...arguments_: never[]) => unknown ? Name : never;
}[keyof typeof owner];
type OwnerFunction<Name extends OwnerMethod> = Extract<(typeof owner)[Name], (...arguments_: never[]) => unknown>;
type OwnerArguments<Name extends OwnerMethod> = Parameters<OwnerFunction<Name>>;
type OwnerReturn<Name extends OwnerMethod> = ReturnType<OwnerFunction<Name>>;
type OwnerResultMethod<Value> = {
  [Name in OwnerMethod]: OwnerReturn<Name> extends owner.Result<Value> ? Name : never;
}[OwnerMethod];
type ResultValue<Result> = Extract<Result, {readonly $tag: 1}> extends {readonly _0: infer Value}
  ? Value : never;

function deliveryCall<Name extends OwnerMethod>(method: Name, ...args: OwnerArguments<Name>): OwnerReturn<Name> {
  // The original indexed call retains the namespace receiver and selected ABI signature.
  try { return (owner[method] as (...arguments_: OwnerArguments<Name>) => OwnerReturn<Name>)(...args); }
  catch (cause) {
    throw Object.assign(new Error('RunHostDeliveryRejected', {cause}),
      {code: 'RunHostDeliveryRejected'});
  }
}

function deliveryResult<Name extends OwnerResultMethod<unknown>>(method: Name, ...args: OwnerArguments<Name>): ResultValue<OwnerReturn<Name>> {
  return checked(deliveryCall(method, ...args) as owner.Result<ResultValue<OwnerReturn<Name>>>, 'RunHostDeliveryRejected');
}

function deliveryView<Kind extends string>(contract: PublicationContract<Kind>,
  original?: CustodyValue<typeof publicationOriginals>): DeliveryContractView<Kind> {
  const value = original === undefined
    ? publicationToken(contract): original.value;
  const view = Object.freeze({
    name: owner.clientValuesHostPublicationContractName(value),
    identityField:
      owner.clientValuesHostPublicationContractIdentityField(value),
    identity: original === undefined ? contract.cid : original.cid,
    wire: original === undefined ? contract.wire : original.wire,
  }) as DeliveryContractView<Kind>;
  deliveryViews.set(view, contract);
  return view;
}

function deliveryToken(view: DeliveryContractView) {
  return publicationToken(deliveryContract(view));
}

function deliveryContract(view: DeliveryContractView) {
  const contract = deliveryViews.get(view);
  if (contract === undefined) throw new TypeError('ForeignRunHostDelivery');
  return contract;
}

type IssuedDeliveryKind = {
  clientValuesHostIssueManifestReadGrant: 'manifest_read_grant';
  clientValuesHostIssueResultReadGrant: 'result_read_grant';
  clientValuesHostIssueDeliveryAttempt: 'delivery_attempt';
  clientValuesHostIssueResultDeliveryReceipt: 'result_delivery_receipt';
  clientValuesHostIssueDeliveryRecord: 'delivery_record';
};
function issuedDelivery<Name extends keyof IssuedDeliveryKind>(
  method: Name, ...args: OwnerArguments<Name>
): DeliveryContractView<IssuedDeliveryKind[Name]> {
  return deliveryView(publicationContract(deliveryResult(method, ...args) as owner.PublicationContract)) as DeliveryContractView<IssuedDeliveryKind[Name]>;
}

// This is a semantic port for the existing common Result access service.
// The Host still supplies current authorization, trusted time, Store and sink.
export function openResultDeliveryControl(): ResultDeliveryControl {
  type Bounds = readonly [number, number, number];
  const issuedGrantBounds = new WeakMap<GrantView, Bounds>();
  const issuedAttempts = new WeakMap<AttemptView, {index: PublicationContract; manifest: PublicationContract;
    grant: PublicationContract; bounds: Bounds; original: IssuedDeliveryAttemptOriginal}>();
  const originalAttempts = new WeakMap<IssuedDeliveryAttemptOriginal, IssuedDeliveryAttemptFacts>();
  const sameBounds = (first: Bounds, second: Bounds) => first.length === second.length &&
    first.every((value, index) => value === second[index]);
  const limitsOf = (limits: PublicationLimits) => {
    const value = publicationLimits(limits);
    return [value.maxWireBytes, value.maxNodes, value.maxDepth] as const;
  };
  const progressToken = (progress: ResultAccessProgress) => requireHandle(accessProgress, progress);
  type MarkMethod = Extract<OwnerMethod, `clientValuesHostRecordResultAccess${string}`>;
  const mark = <Name extends MarkMethod>(method: Name, progress: ResultAccessProgress, value: OwnerArguments<Name>[1]) =>
    (deliveryCall as (method: Name, original: owner.ResultAccessProgress, value: OwnerArguments<Name>[1]) =>
      OwnerReturn<Name>)(method, progressToken(progress), value);
  return Object.freeze<ResultDeliveryControl>({
    describeCommittedResult(index, manifest, resultName, bindings,
      definition, schemaWire, format, limits) {
      return describeCommittedResult(deliveryContract(index),
        deliveryContract(manifest), resultName,
        bindings.map(deliveryContract), deliveryContract(definition),
        schemaWire, format, limits);
    },
    resultMetadataRetentionState(retention, observedAt) {
      const value = owner.clientValuesHostResultMetadataRetentionState(
        deliveryToken(retention), observedAt);
      if (!['retained', 'delete_due'].includes(value as string)) {
        throw new Error('RunHostMetadataRetentionRejected');
      }
      return value as ReturnType<ResultDeliveryControl['resultMetadataRetentionState']>;
    },
    issueManifestReadGrant(index, manifest, grant, limits) {
      return issuedDelivery('clientValuesHostIssueManifestReadGrant',
        deliveryToken(index), deliveryToken(manifest),
        grant.principalId, grant.purpose, grant.dataCeilingCid,
        grant.maxBytes, grant.maxUses, grant.expiresAt,
        grant.authorizationContextCid, ...limitsOf(limits));
    },
    manifestReadGrantValidAt(grant, at) {
      return deliveryCall('clientValuesHostManifestReadGrantValidAt',
        deliveryToken(grant), at);
    },
    manifestReadGrantAllowsBytes(grant, bytes) {
      return deliveryCall('clientValuesHostManifestReadGrantAllowsBytes',
        deliveryToken(grant), bytes);
    },
    admit(name, wire, limits) {
      return deliveryView(admitPublicationContract(name, wire, limits));
    },
    fromPublication<Kind extends string>(contract: PublicationContract, expectedName?: Kind): DeliveryContractView<Kind> {
      const original = publicationOriginals.get(contract);
      if (original === undefined) {
        throw new TypeError('ForeignRunHostPublication');
      }
      const view = deliveryView(contract, original);
      if (expectedName !== undefined && view.name !== expectedName) {
        throw new TypeError('RunHostPublicationKindMismatch');
      }
      return view as DeliveryContractView<Kind>;
    },
    beginResultAccessProgress() {
      return handle(accessProgress,
        owner.clientValuesHostBeginResultAccessProgress(),
        'result-access-progress');
    },
    resultAccessProgressAction(progress) {
      return publicationAction('resultAccess',
        owner.clientValuesHostResultAccessProgressAction(progressToken(progress)));
    },
    recordResultAccessRequestAuthorization(progress, value) {
      return mark('clientValuesHostRecordResultAccessRequestAuthorization',
        progress, value);
    },
    recordResultAccessResolution(progress, value) {
      return mark('clientValuesHostRecordResultAccessResolution',
        progress, value);
    },
    recordResultAccessInitialAvailability(progress, value) {
      return mark('clientValuesHostRecordResultAccessInitialAvailability',
        progress, value);
    },
    recordResultAccessReadAdmission(progress, value) {
      return mark('clientValuesHostRecordResultAccessReadAdmission',
        progress, value);
    },
    recordResultAccessGrant(progress, value) {
      return mark('clientValuesHostRecordResultAccessGrant', progress, value);
    },
    resultReadRetentionPolicyCid(manifest, resultName) {
      return deliveryResult('clientValuesHostResultReadRetentionPolicyCid',
        deliveryToken(manifest), resultName);
    },
    resultReadDefinitionCid(manifest, resultName) {
      return deliveryResult('clientValuesHostResultReadDefinitionCid',
        deliveryToken(manifest), resultName);
    },
    resultReadAvailability(manifest, resultName, retention, observedAt) {
      return resultReadAvailability(deliveryContract(manifest), resultName,
        deliveryContract(retention), observedAt);
    },
    resultReadExtendedAvailability(manifest, resultName, retention,
      extension, observedAt) {
      return deliveryResult('clientValuesHostResultReadExtendedAvailability',
        deliveryToken(manifest), resultName, deliveryToken(retention),
        deliveryToken(extension), observedAt);
    },
    resultRetentionClockContractCid(retention) {
      return deliveryResult('clientValuesHostResultRetentionClockContractCid',
        deliveryToken(retention));
    },
    issueResultReadGrant(index, manifest, grant, limits) {
      const bounds = limitsOf(limits);
      const result = issuedDelivery('clientValuesHostIssueResultReadGrant',
        deliveryToken(index), deliveryToken(manifest),
        grant.resultNames, grant.formats, grant.principalId, grant.purpose,
        grant.dataCeilingCid, grant.maxBytes, grant.maxUses,
        grant.expiresAt, grant.authorizationContextCid,
        grant.egressAdmissionCid, ...bounds);
      issuedGrantBounds.set(result, Object.freeze(bounds));
      return result;
    },
    resultReadGrantValidAt(grant, observedAt) {
      return owner.clientValuesHostResultReadGrantValidAt(
        deliveryToken(grant), observedAt);
    },
    resultReadGrantAllowsBytes(grant, count) {
      return owner.clientValuesHostResultReadGrantAllowsBytes(
        deliveryToken(grant), count);
    },
    issueDeliveryAttempt(index, manifest, grant, attempt, limits) {
      const request = Object.freeze({resultName: attempt.resultName,
        format: attempt.format, attemptId: attempt.attemptId,
        requestedAt: attempt.requestedAt});
      const bounds = Object.freeze(limitsOf(limits));
      const result = issuedDelivery('clientValuesHostIssueDeliveryAttempt',
        deliveryToken(index), deliveryToken(manifest), deliveryToken(grant),
        request.resultName, request.format, request.attemptId,
        request.requestedAt, ...bounds);
      const original = Object.freeze({kind: 'issued-delivery-attempt'}) as unknown as IssuedDeliveryAttemptOriginal;
      const facts = Object.freeze({index, manifest, grant, attempt: result,
        request, limits: Object.freeze({maxWireBytes: bounds[0],
          maxNodes: bounds[1], maxDepth: bounds[2]})});
      issuedAttempts.set(result, {index: deliveryContract(index),
        manifest: deliveryContract(manifest), grant: deliveryContract(grant),
        bounds, original});
      originalAttempts.set(original, facts);
      return result;
    },
    captureIssuedDeliveryAttempt(attempt, index, manifest, grant, limits) {
      // Nominal lookups precede any view-field access. A valid raw admission
      // remains compatible, but cannot claim this issuer's captured inputs.
      deliveryContract(attempt);
      const actualIndex = deliveryContract(index);
      const actualManifest = deliveryContract(manifest);
      const actualGrant = deliveryContract(grant);
      const captured = issuedAttempts.get(attempt);
      if (captured === undefined) return undefined;
      if (captured.index !== actualIndex || captured.manifest !== actualManifest ||
          captured.grant !== actualGrant) {
        throw new TypeError('RunHostDeliveryOriginalMismatch');
      }
      const bounds = limitsOf(limits);
      const grantBounds = issuedGrantBounds.get(grant);
      if (grantBounds === undefined || !sameBounds(bounds, grantBounds) ||
          !sameBounds(bounds, captured.bounds)) return undefined;
      return captured.original;
    },
    readIssuedDeliveryAttempt(original) {
      const facts = originalAttempts.get(original);
      if (facts === undefined) throw new TypeError('ForeignRunHostDeliveryOriginal');
      return facts;
    },
    deliveryResultDefinitionCid(manifest, attempt) {
      return deliveryResult('clientValuesHostDeliveryResultDefinitionCid',
        deliveryToken(manifest), deliveryToken(attempt));
    },
    issueResultDeliveryReceipt(index, manifest, grant, attempt,
      delivered, limits) {
      return issuedDelivery('clientValuesHostIssueResultDeliveryReceipt',
        deliveryToken(index), deliveryToken(manifest), deliveryToken(grant),
        deliveryToken(attempt), delivered.byteCount, delivered.sha256,
        ...limitsOf(limits));
    },
    issueDeliveryRecord(attempt, previous, update, limits) {
      return issuedDelivery('clientValuesHostIssueDeliveryRecord',
        deliveryToken(attempt), previous === undefined ? undefined :
          deliveryToken(previous), update.state,
        update.confirmedByteCount, update.exposure,
        update.possibleUnconfirmedMaxBytes, update.deliveredSha256,
        update.receipt === undefined ? undefined :
          deliveryToken(update.receipt), update.failureCid,
        update.observedAt, update.cleanupOwnerCids, ...limitsOf(limits));
    },
    existingDeliveryAttemptAction(record) {
      return publicationAction('existingDelivery',
        owner.clientValuesHostExistingDeliveryAttemptAction(
          record === undefined ? undefined : deliveryToken(record)));
    },
    deliveryFailureTerminalAction(observed) {
      return publicationAction('failureTerminal',
        owner.clientValuesHostDeliveryFailureTerminalAction(observed));
    },
    deliveryRecordRetryAction(next, count) {
      return publicationAction('recordRetry',
        owner.clientValuesHostDeliveryRecordRetryAction(next, count));
    },
    deliveryTransition(previous, next) {
      return owner.clientValuesHostDeliveryRecordTransition(
        previous === undefined ? undefined : deliveryToken(previous),
        deliveryToken(next));
    },
    deliverySuccessValid(attempt, receipt, record) {
      return owner.clientValuesHostDeliverySuccessValid(
        deliveryToken(attempt), deliveryToken(receipt),
        deliveryToken(record));
    },
    trustedClockNotBefore(previous, observedAt) {
      return owner.clientValuesHostTrustedClockNotBefore(previous, observedAt);
    },
    prepareDeliveryGrantUsageClaim(grant, existingWire, attempt, limits) {
      const claim = deliveryResult(
        'clientValuesHostPrepareDeliveryGrantUsageClaim',
        deliveryToken(grant), existingWire, deliveryToken(attempt),
        ...limitsOf(limits));
      return Object.freeze({
        wire: owner.clientValuesHostDeliveryGrantUsageClaimWire(claim),
        newlyClaimed:
          owner.clientValuesHostDeliveryGrantUsageClaimIsNew(claim),
      });
    },
    prepareDurableResultRowFrames(bounds) {
      const frames = deliveryResult(
        'clientValuesHostPrepareDurableResultRowFrames',
        bounds.maxBytes, bounds.maxRows, bounds.maxRowBytes,
        bounds.maxDepth, bounds.maxFrameBytes);
      return handle(durableRowFrames, frames, 'durable-row-frames');
    },
    feedDurableResultRowFrames(frames, chunk) {
      return deliveryResult('clientValuesHostFeedDurableResultRowFrames',
        requireHandle(durableRowFrames, frames), chunk);
    },
    finishDurableResultRowFrames(frames) {
      const values = deliveryResult('clientValuesHostFinishDurableResultRowFrames',
        requireHandle(durableRowFrames, frames));
      return Object.freeze({bytes: values[0], rows: values[1]});
    },
    cancelDurableResultRowFrames(frames) {
      return deliveryCall('clientValuesHostCancelDurableResultRowFrames',
        requireHandle(durableRowFrames, frames));
    },
    prepareResultDeliverySerializer(format, schemaWire, fields, limits) {
      const serializer = deliveryResult(
        'clientValuesHostPrepareResultDeliverySerializer',
        format, schemaWire, fields, ...limitsOf(limits));
      return handle(deliverySerializers, serializer, 'result-serializer');
    },
    beginResultDelivery(serializer) {
      return deliveryResult('clientValuesHostBeginResultDelivery',
        requireHandle(deliverySerializers, serializer));
    },
    nextResultDeliveryRow(serializer, rowWire) {
      return deliveryResult('clientValuesHostNextResultDeliveryRow',
        requireHandle(deliverySerializers, serializer), rowWire);
    },
    finishResultDelivery(serializer) {
      return deliveryResult('clientValuesHostFinishResultDelivery',
        requireHandle(deliverySerializers, serializer));
    },
  });
}

function admittedTaskProgress(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission,
  definition: RunDefinition, authority: string, durableWires: readonly string[]) {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof authority !== 'string' || !Array.isArray(durableWires) ||
      durableWires.some(wire => typeof wire !== 'string')) {
    throw new TypeError('InvalidRunHostTaskProgress');
  }
  checkRunBinding(prepared, admission, definition);
  return checked(owner.clientValuesHostInspectTaskProgress(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), authority, durableWires),
  'RunHostTaskProgressRejected');
}

function taskProgressSnapshot(value: owner.ClientRemoteTaskProgress) {
  const scopes = owner.clientValuesHostTaskProgressScopes(value);
  const next = owner.clientValuesHostTaskProgressNext(value);
  return Object.freeze({
    nextTask: next < 0 ? undefined : next,
    executionComplete: owner.clientValuesHostTaskProgressExecutionComplete(value),
    cleanupComplete: owner.clientValuesHostTaskProgressCleanupComplete(value),
    resultTasks: Object.freeze(owner.clientValuesHostTaskProgressResultTasks(value)),
    tasks: Object.freeze(owner.clientValuesHostTaskProgressFields(value).map((row, index) =>
      Object.freeze({ordinal: Number(row[0]), taskKey: row[1], execution: row[2],
        cleanup: row[3], revision: Number(row[4]), dispatchCid: row[5] || undefined,
        executionScope: Object.freeze(scopes[index])}))),
  }) as ReturnType<typeof inspectTaskProgress>;
}

/** Inspect checked task readiness. A snapshot grants no start or input custody. */
export function inspectTaskProgress(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission, definition: RunDefinition,
  authority: string, durableWires: readonly string[]): Readonly<{
    nextTask: number | undefined; executionComplete: boolean;
    cleanupComplete: boolean; resultTasks: readonly number[];
    tasks: readonly Readonly<{ordinal: number; taskKey: string;
      execution: 'unobserved' | 'accepted' | 'provisioning' | 'running' |
        'settled' | 'failed' | 'cancelled' | 'unknown';
      cleanup: 'unobserved' | 'active' | 'releasing' | 'released' |
        'unknown' | 'force_lost' | 'recovered_after_loss';
      revision: number; dispatchCid: string | undefined;
      executionScope: readonly string[]}>[];
  }> {
  return taskProgressSnapshot(admittedTaskProgress(prepared, compilation,
    admission, definition, authority, durableWires));
}

function validateTaskPhysicalStartClaim(claim: Parameters<typeof prepareTaskPhysicalStart>[8]) {
  const keys = ['taskKey', 'dispatchCid', 'definitionCid', 'reserved',
    'unstarted', 'authorized', 'cancelled', 'failed'];
  if (claim === null || typeof claim !== 'object' || Array.isArray(claim) ||
      Object.keys(claim).sort().join('\0') !== keys.sort().join('\0') ||
      [claim.taskKey, claim.dispatchCid, claim.definitionCid].some(value => typeof value !== 'string') ||
      [claim.reserved, claim.unstarted, claim.authorized, claim.cancelled, claim.failed]
        .some(value => typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunHostTaskStart');
  }
}

/** Prepare a checked task claim. The Host must commit it before any send. */
export function prepareTaskPhysicalStart(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission, definition: RunDefinition,
  authority: string, durableWires: readonly string[], requested: RequestIdentity, retained: RequestIdentity, claim: Readonly<{taskKey: string; dispatchCid: string;
    definitionCid: string; reserved: boolean; unstarted: boolean;
    authorized: boolean; cancelled: boolean; failed: boolean}>): boolean {
  validateTaskPhysicalStartClaim(claim);
  const progress = admittedTaskProgress(prepared, compilation, admission, definition,
    authority, durableWires);
  return checked(owner.clientValuesHostPrepareRemoteTaskPhysicalStart(
    progress, claim.taskKey, claim.dispatchCid, requireHandle(requests, requested),
    requireHandle(requests, retained), claim.definitionCid, claim.reserved,
    claim.unstarted, claim.authorized, claim.cancelled, claim.failed),
  'RunHostTaskStartRejected');
}

function admittedEffectTaskProgress(allowed: AllowedEffectRun, definition: RunDefinition,
  authority: string, durableWires: readonly string[]) {
  const {value} = requireHandle(effectAllowedRuns, allowed);
  if (typeof authority !== 'string' || !Array.isArray(durableWires) ||
      durableWires.some(wire => typeof wire !== 'string')) {
    throw new TypeError('InvalidRunHostTaskProgress');
  }
  return checked(owner.clientValuesHostInspectEffectTaskProgress(value,
    requireHandle(definitions, definition), authority, durableWires),
  'RunHostEffectTaskProgressRejected');
}

/** Computation/output facts only: this is not Effect or Run completion. */
export function inspectEffectTaskProgress(allowed: AllowedEffectRun, definition: RunDefinition, authority: string, durableWires: readonly string[]): Readonly<{
    nextTask: number | undefined; computationComplete: boolean;
    taskCleanupComplete: boolean; resultTasks: readonly number[];
    tasks: ReturnType<typeof inspectTaskProgress>['tasks'];
  }> {
  return effectTaskProgressSnapshot(admittedEffectTaskProgress(allowed, definition, authority, durableWires));
}

function effectTaskProgressSnapshot(value: owner.ClientRemoteEffectTaskProgress) {
  const scopes = owner.clientValuesHostEffectTaskProgressScopes(value);
  const next = owner.clientValuesHostEffectTaskProgressNext(value);
  return Object.freeze({
    nextTask: next < 0 ? undefined : next,
    computationComplete: owner.clientValuesHostEffectTaskProgressComputationComplete(value),
    taskCleanupComplete: owner.clientValuesHostEffectTaskProgressTaskCleanupComplete(value),
    resultTasks: Object.freeze(owner.clientValuesHostEffectTaskProgressResultTasks(value)),
    tasks: Object.freeze(owner.clientValuesHostEffectTaskProgressFields(value).map((row, index) =>
      Object.freeze({ordinal: Number(row[0]), taskKey: row[1], execution: row[2],
        cleanup: row[3], revision: Number(row[4]), dispatchCid: row[5] || undefined,
        executionScope: Object.freeze(scopes[index])}))),
  }) as ReturnType<typeof inspectEffectTaskProgress>;
}

// Read each native Array element once. Caller-owned iteration, some and slice
// methods are not the supplier of the captured durable/claim facts.
function effectProjectionArray<Value>(value: readonly Value[], maximum: number): Value[] {
  if (!Array.isArray(value)) throw new TypeError('InvalidRunHostEffectRunProjection');
  const length = value.length;
  if (!Number.isSafeInteger(length) || length < 0 || length > maximum) {
    throw new TypeError('InvalidRunHostEffectRunProjection');
  }
  const snapshot = [];
  for (let index = 0; index < length; index++) snapshot.push(value[index]);
  return snapshot;
}

/** Unpublished same-Run computation observation. Task cleanup and cancellation
 * are not a whole Effect/producer/Transfer stop, publication or release ACK. */
export function projectEffectSiteRun(allowed: AllowedEffectRun, definition: RunDefinition, authority: string, durableWires: readonly string[],
  observedAt: string, cancellationRequested: boolean, savedClaims: readonly Readonly<{taskKey: string; dispatchCid: string | null;
    dispatchReserved: boolean; physicalStartClaimed: boolean}>[]): Readonly<
    Omit<ReturnType<typeof inspectEffectTaskProgress>, 'tasks'> & {
      stateWire: string; publicationReady: false;
      execution: 'unobserved' | 'running' | 'settled' | 'failed' | 'cancelled' | 'unknown';
      tasks: readonly Readonly<ReturnType<typeof inspectTaskProgress>['tasks'][number] & {
        nextWork: 'none' | 'cleanup' | 'publication' | 'reconcile' | 'cancel' | 'release'}>[];
    }> {
  // The original checked graph bounds both complete claims and the at-most
  // one durable Coordinator record for each task, before reading elements.
  const {prepared, compilation} = requireHandle(effectAllowedRuns, allowed);
  const count = effectExecutionShape(prepared, compilation).taskCount;
  const wires = effectProjectionArray(durableWires, count);
  const claims = effectProjectionArray(savedClaims, count);
  if (typeof observedAt !== 'string' || typeof cancellationRequested !== 'boolean') {
    throw new TypeError('InvalidRunHostEffectRunProjection');
  }
  const keys = [], dispatches = [], reserved = [], physicallyClaimed = [];
  for (let index = 0; index < claims.length; index++) {
    const claim = claims[index];
    if (!claim || typeof claim !== 'object') throw new TypeError('InvalidRunHostEffectRunProjection');
    const key = claim.taskKey, dispatch = claim.dispatchCid;
    const reservation = claim.dispatchReserved, physical = claim.physicalStartClaimed;
    if (typeof key !== 'string' || (dispatch !== null && (typeof dispatch !== 'string' || dispatch.length === 0)) ||
        typeof reservation !== 'boolean' || typeof physical !== 'boolean') {
      throw new TypeError('InvalidRunHostEffectRunProjection');
    }
    keys.push(key); dispatches.push(dispatch === null ? '' : dispatch);
    reserved.push(reservation); physicallyClaimed.push(physical);
  }
  const value = admittedEffectTaskProgress(allowed, definition, authority, wires);
  const projected = checked(owner.clientValuesHostProjectEffectTaskRun(value,
    observedAt, cancellationRequested, keys, dispatches, reserved, physicallyClaimed),
  'RunHostEffectTaskRunProjectionRejected');
  const fields = owner.clientValuesHostEffectTaskRunFields(projected);
  const work = owner.clientValuesHostEffectTaskRunWork(projected);
  if (fields[3] !== '0' || fields[4] !== '0') throw new Error('InvalidRunHostEffectRunProjection');
  const progress = effectTaskProgressSnapshot(value), next = Number(fields[2]);
  return Object.freeze({...progress, stateWire: fields[0], execution: fields[1],
    nextTask: next < 0 ? undefined : next, publicationReady: false,
    tasks: Object.freeze(progress.tasks.map((task, index) =>
      Object.freeze({...task, nextWork: work[index]}))),
  }) as ReturnType<typeof projectEffectSiteRun>;
}

/** Prepare the existing saved task claim; no Effect approval or physical apply. */
export function prepareEffectTaskPhysicalStart(allowed: AllowedEffectRun, definition: RunDefinition, authority: string, durableWires: readonly string[],
  requested: RequestIdentity, retained: RequestIdentity, claim: Readonly<{taskKey: string; dispatchCid: string; definitionCid: string;
    reserved: boolean; unstarted: boolean; authorized: boolean;
    cancelled: boolean; failed: boolean}>): boolean {
  validateTaskPhysicalStartClaim(claim);
  const value = admittedEffectTaskProgress(allowed, definition, authority, durableWires);
  return checked(owner.clientValuesHostPrepareEffectTaskPhysicalStart(value,
    claim.taskKey, claim.dispatchCid, requireHandle(requests, requested),
    requireHandle(requests, retained), claim.definitionCid, claim.reserved,
    claim.unstarted, claim.authorized, claim.cancelled, claim.failed),
  'RunHostEffectTaskStartRejected');
}

/** Project the unpublished whole Run without committing, starting or releasing it. */
export function projectTaskSiteRun(prepared: PreparedProgram, compilation: TaskCompilation, admission: RunAdmission, definition: RunDefinition,
  authority: string, durableWires: readonly string[], observedAt: string, cancellationRequested: boolean = false,
  claimedTaskKeys: readonly string[] = []): Readonly<{
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
  }> {
  if (typeof observedAt !== 'string' || typeof cancellationRequested !== 'boolean' ||
      !Array.isArray(claimedTaskKeys) ||
      claimedTaskKeys.some(key => typeof key !== 'string')) {
    throw new TypeError('InvalidRunHostTaskRunProjection');
  }
  const value = admittedTaskProgress(prepared, compilation, admission,
    definition, authority, durableWires);
  const projected = checked(owner.clientValuesHostProjectRemoteTaskRun(
    value, observedAt, cancellationRequested, claimedTaskKeys),
  'RunHostTaskRunProjectionRejected');
  const fields = owner.clientValuesHostRemoteTaskRunFields(projected);
  const work = owner.clientValuesHostRemoteTaskRunWork(projected);
  const progress = taskProgressSnapshot(value);
  const next = Number(fields[2]);
  return Object.freeze({...progress, stateWire: fields[0], execution: fields[1],
    nextTask: next < 0 ? undefined : next, publicationReady: fields[3] === '1',
    cleanupComplete: fields[4] === '1',
    tasks: Object.freeze(progress.tasks.map((task, index) =>
      Object.freeze({...task, nextWork: work[index]}))),
  }) as ReturnType<typeof projectTaskSiteRun>;
}

/** Project an admitted durable Site record bound to this checked Run. */
export function projectSiteRun(prepared: PreparedProgram, compilation: ValuesCompilation | TaskCompilation, admission: RunAdmission, definition: RunDefinition,
  authority: string, durableWire: string, observedAt: string, cancellationRequested: boolean = false,
  physicalStartClaimed: boolean = false): Readonly<{stateWire: string;
    execution: 'unobserved' | 'running' | 'settled' | 'failed' |
      'cancelled' | 'unknown';
    cleanup: 'complete' | 'pending'; revision: number;
    nextWork: 'none' | 'cleanup' | 'publication' | 'reconcile' | 'cancel' | 'release'}> {
  const task = taskCompilations.has(compilation as TaskCompilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([authority, durableWire, observedAt].some(value =>
      typeof value !== 'string') || typeof cancellationRequested !== 'boolean' ||
      typeof physicalStartClaimed !== 'boolean') {
    throw new TypeError('InvalidSiteObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const fields = checked(task ? owner.clientValuesHostProjectTaskSiteRun(
    requireHandle(preparations, prepared), compiled.value as owner.ClientTaskCompilation, admitted.value,
    requireHandle(definitions, definition), authority, durableWire, observedAt,
    cancellationRequested, physicalStartClaimed)
    : owner.clientValuesHostProjectSiteRun(
      requireHandle(definitions, definition), compiled.value as owner.ClientValuesCompilation,
      authority, durableWire, observedAt, cancellationRequested,
      physicalStartClaimed),
  'RunHostSiteProjectionRejected');
  if (fields === undefined) {
    throw Object.assign(new Error('RunHostSiteProjectionRejected'),
      {code: 'RunHostSiteProjectionRejected'});
  }
  return Object.freeze({stateWire: fields[0], execution: fields[1],
    cleanup: fields[2], revision: Number(fields[3]), nextWork: fields[4]}) as ReturnType<typeof projectSiteRun>;
}

export function prepareRunPhysicalStart(requested: RequestIdentity, retained: RequestIdentity, definition: RunDefinition,
  definitionCid: string, reserved: boolean, unstarted: boolean, authorized: boolean, cancelled: boolean, failed: boolean = false): boolean {
  if (typeof definitionCid !== 'string' ||
      [reserved, unstarted, authorized, cancelled, failed].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunHostStart');
  return checked(owner.clientValuesHostPreparePhysicalStart(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), definitionCid, reserved,
    unstarted, authorized, cancelled, failed), 'RunHostStartRejected');
}

export function prepareRunPreStartFailure(requested: RequestIdentity, retained: RequestIdentity, definition: RunDefinition,
  definitionCid: string, reserved: boolean, unstarted: boolean, admissionDenied: boolean, cancelled: boolean): boolean {
  if (typeof definitionCid !== 'string' ||
      [reserved, unstarted, admissionDenied, cancelled].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunHostStart');
  return checked(owner.clientValuesHostPreparePreStartFailure(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), definitionCid, reserved,
    unstarted, admissionDenied, cancelled), 'RunHostStartRejected');
}

export function prepareRunCancellation(definition: RunDefinition, definitionCid: string,
  authorized: boolean, terminal: boolean, requested: boolean): 'accepted' | 'already_requested' | 'already_terminal' {
  if (typeof definitionCid !== 'string' ||
      [authorized, terminal, requested].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunCancellation');
  return checked(owner.clientValuesHostPrepareCancellation(
    requireHandle(definitions, definition), definitionCid, authorized,
    terminal, requested), 'RunHostCancellationRejected') as ReturnType<typeof prepareRunCancellation>;
}

/** Identity only; this does not request physical stop or return capacity. */
export function prepareRunCancellationIdentity(definition: RunDefinition, scope: Readonly<{namespaceId: string; authorityScopeCid: string;
    cancelId: string; expectedRevision: number}>): RunCancellationIdentity {
  const {namespaceId, authorityScopeCid, cancelId, expectedRevision} = scope ?? {};
  if ([namespaceId, authorityScopeCid, cancelId].some(value => typeof value !== 'string') ||
      !Number.isSafeInteger(expectedRevision) || expectedRevision < 0 ||
      expectedRevision > 2147483647) {
    throw new TypeError('InvalidRunCancellationIdentity');
  }
  return handle(cancellationIdentities, checked(
    owner.clientValuesHostPrepareCancellationIdentity(namespaceId,
      authorityScopeCid, cancelId, requireHandle(definitions, definition),
      expectedRevision), 'RunHostCancellationIdentityRejected'),
  'cancellation-identity');
}

/** Stored identity checksum; never storage provenance or execution authority. */
export function runCancellationIntentCid(identity: RunCancellationIdentity): string {
  return owner.clientValuesHostCancellationIntentCid(
    requireHandle(cancellationIdentities, identity));
}

/** Replay requires the saved immutable outcome, rather than today's Run flags. */
export function prepareRunCancellationOperation(definition: RunDefinition, requested: RunCancellationIdentity, facts: Readonly<{
    retained?: RunCancellationIdentity; currentRevision: number;
    currentAuthorization: boolean; terminalObserved: boolean;
    cancellationRequested: boolean;
  }>): 'accepted' | 'already_requested' | 'already_terminal' | 'replay_original' {
  const {retained, currentRevision, currentAuthorization,
    terminalObserved, cancellationRequested} = facts ?? {};
  if (!Number.isSafeInteger(currentRevision) || currentRevision < 0 ||
      currentRevision > 2147483647 ||
      [currentAuthorization, terminalObserved, cancellationRequested].some(value =>
        typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunCancellationOperation');
  }
  const result = owner.clientValuesHostPrepareCancellationOperation(
    requireHandle(cancellationIdentities, requested), retained === undefined ?
      undefined : requireHandle(cancellationIdentities, retained),
    requireHandle(definitions, definition), currentRevision,
    currentAuthorization, terminalObserved, cancellationRequested);
  if (runtimeIsError(result) && ['ClientCancellationIntentConflict',
    'ClientCancellationOperationMismatch', 'ClientCancellationRevisionConflict',
    'ClientCancellationDenied', 'ClientCancellationRunMismatch'].includes(runtimeField(result, 0) as string)) {
    throw Object.assign(new Error(runtimeField(result, 0) as string), {code: runtimeField(result, 0) as string});
  }
  const action = checked(result, 'RunHostCancellationOperationRejected');
  if (!['accepted', 'already_requested', 'already_terminal', 'replay_original'].includes(action)) {
    throw new Error('InvalidRunHostCancellationOperation');
  }
  return action as ReturnType<typeof prepareRunCancellationOperation>;
}

export function issueRunControlObservation(revision: number, observation: Readonly<{requested: boolean; unstarted: boolean;
    stopped: boolean}>): Readonly<{
    revision: number; cancellation_requested: boolean;
    physical_stop: 'unknown' | 'confirmed'}> {
  const {requested, unstarted, stopped} = observation ?? {};
  if (!Number.isSafeInteger(revision) || revision < 0 || revision > 2147483647 ||
      observation === null || typeof observation !== 'object' ||
      Array.isArray(observation) ||
      [requested, unstarted, stopped].some(value => typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunControlObservation');
  }
  return JSON.parse(checked(owner.clientValuesHostRunControlObservation(
    revision, requested, unstarted, stopped), 'RunHostControlRejected'));
}


// The common identity Owner does not authenticate an epoch or retain its
// validation material. A physical Host must establish those facts separately.
export function prepareSubmissionEpoch(scope: Readonly<{authorityScopeCid: string;
  epochNonce: string; notBefore: number; expiresAt: number}>): SubmissionEpoch {
  const {authorityScopeCid, epochNonce, notBefore, expiresAt} = scope ?? {};
  if (typeof authorityScopeCid !== 'string' || typeof epochNonce !== 'string' ||
      !Number.isSafeInteger(notBefore) || !Number.isSafeInteger(expiresAt)) {
    throw new TypeError('InvalidSubmissionEpoch');
  }
  const value = owner.clientValuesHostSubmissionEpoch(authorityScopeCid,
    epochNonce, notBefore, expiresAt);
  if (value === undefined) throw new Error('SubmissionEpochRejected');
  return handle(submissionEpochs, value, 'submission-epoch');
}

export function submissionEpochFacts(epoch: SubmissionEpoch): Readonly<{wire: string; cid: string}> {
  const value = requireHandle(submissionEpochs, epoch);
  return Object.freeze({wire: owner.clientValuesHostSubmissionEpochWire(value),
    cid: owner.clientValuesHostSubmissionEpochCid(value)});
}

export function submissionEpochValidity(epoch: SubmissionEpoch, now: number): 'admissible' | 'not_yet_valid' | 'expired' {
  if (!Number.isSafeInteger(now)) throw new TypeError('InvalidSubmissionClock');
  const value = owner.clientValuesHostSubmissionEpochValidity(
    requireHandle(submissionEpochs, epoch), now);
  if (value === undefined) throw new Error('SubmissionClockRejected');
  if (!['admissible', 'not_yet_valid', 'expired'].includes(value)) {
    throw new Error('InvalidSubmissionOwnerReply');
  }
  return value as ReturnType<typeof submissionEpochValidity>;
}

export function submissionRequestId(epoch: SubmissionEpoch, nonce: string): string {
  if (typeof nonce !== 'string') throw new TypeError('InvalidSubmissionNonce');
  const value = owner.clientValuesHostSubmissionRequestId(
    requireHandle(submissionEpochs, epoch), nonce);
  if (value === undefined) throw new Error('SubmissionNonceRejected');
  return value;
}

export function prepareSubmittedIntent(wire: string, limits: Readonly<{
  maxWireBytes: number; maxNodes: number; maxDepth: number}>): SubmittedIntent {
  const {maxWireBytes, maxNodes, maxDepth} = limits ?? {};
  if (typeof wire !== 'string' ||
      !Number.isInteger(maxWireBytes) || maxWireBytes < 1 || maxWireBytes > 1048576 ||
      !Number.isInteger(maxNodes) || maxNodes < 1 || maxNodes > 65536 ||
      !Number.isInteger(maxDepth) || maxDepth < 1 || maxDepth > 64) {
    throw new TypeError('InvalidSubmittedIntent');
  }
  const value = owner.clientValuesHostSubmittedIntent(wire, maxWireBytes, maxNodes, maxDepth);
  if (value === undefined) throw new Error('SubmittedIntentRejected');
  return handle(submittedIntents, value, 'submitted-intent');
}

export function submittedIntentFacts(intent: SubmittedIntent): Readonly<{wire: string; cid: string}> {
  const value = requireHandle(submittedIntents, intent);
  return Object.freeze({wire: owner.clientValuesHostSubmittedIntentWire(value),
    cid: owner.clientValuesHostSubmittedIntentCid(value)});
}

export function submittedIntentTransition(before: string, after: string): boolean {
  if (typeof before !== 'string' || typeof after !== 'string') {
    throw new TypeError('InvalidSubmittedIntentPhase');
  }
  return owner.clientValuesHostSubmittedIntentTransition(before, after);
}
