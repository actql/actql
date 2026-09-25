declare const environmentBrand: unique symbol;
declare const preparedBrand: unique symbol;
declare const compilationBrand: unique symbol;
declare const requestBrand: unique symbol;
declare const admissionBrand: unique symbol;
declare const definitionBrand: unique symbol;
declare const publicationBrand: unique symbol;
declare const resultOccurrenceBrand: unique symbol;
declare const runEvidenceBrand: unique symbol;
declare const capturedSnapshotBrand: unique symbol;

export interface CheckEnvironment {
  readonly [environmentBrand]: true;
}

export interface PreparedProgram {
  readonly [preparedBrand]: true;
}

export interface ValuesCompilation {
  readonly [compilationBrand]: true;
}

export interface RequestIdentity {
  readonly [requestBrand]: true;
}

export interface RunAdmission {
  readonly [admissionBrand]: true;
}

export interface RunDefinition {
  readonly [definitionBrand]: true;
}

export interface PublicationContract {
  readonly token: {readonly [publicationBrand]: true};
  readonly cid: string;
  readonly wire: string;
}

export interface DeliveryContractView {
  readonly name: string;
  readonly identityField: string;
  readonly identity: string;
  readonly wire: string;
}

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
  admit(name: string, wire: string,
    limits: PublicationLimits): DeliveryContractView;
  beginResultAccessProgress(): ResultAccessProgress;
  resultAccessProgressAction(progress: ResultAccessProgress): number;
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
  resultReadRetentionPolicyCid(manifest: DeliveryContractView,
    resultName: string): string;
  resultReadDefinitionCid(manifest: DeliveryContractView,
    resultName: string): string;
  resultReadAvailability(manifest: DeliveryContractView,
    resultName: string, retention: DeliveryContractView,
    observedAt: string): string;
  resultReadExtendedAvailability(manifest: DeliveryContractView,
    resultName: string, retention: DeliveryContractView,
    extension: DeliveryContractView, observedAt: string): string;
  resultRetentionClockContractCid(retention: DeliveryContractView): string;
  issueResultReadGrant(index: DeliveryContractView,
    manifest: DeliveryContractView, grant: Readonly<{
      resultNames: readonly string[]; formats: readonly string[];
      principalId: string; purpose: string; dataCeilingCid: string;
      maxBytes: number; maxUses: number; expiresAt: string;
      authorizationContextCid: string; egressAdmissionCid: string;
    }>, limits: PublicationLimits): DeliveryContractView;
  resultReadGrantValidAt(grant: DeliveryContractView,
    observedAt: string): boolean;
  resultReadGrantAllowsBytes(grant: DeliveryContractView,
    count: number): boolean;
  issueDeliveryAttempt(index: DeliveryContractView,
    manifest: DeliveryContractView, grant: DeliveryContractView,
    attempt: Readonly<{resultName: string; format: string;
      attemptId: string; requestedAt: string}>,
    limits: PublicationLimits): DeliveryContractView;
  deliveryResultDefinitionCid(manifest: DeliveryContractView,
    attempt: DeliveryContractView): string;
  issueResultDeliveryReceipt(index: DeliveryContractView,
    manifest: DeliveryContractView, grant: DeliveryContractView,
    attempt: DeliveryContractView,
    delivered: Readonly<{byteCount: number; sha256: string}>,
    limits: PublicationLimits): DeliveryContractView;
  issueDeliveryRecord(attempt: DeliveryContractView,
    previous: DeliveryContractView | undefined,
    update: Readonly<{state: string; confirmedByteCount: number;
      exposure: string; possibleUnconfirmedMaxBytes?: number;
      deliveredSha256?: string; receipt?: DeliveryContractView;
      failureCid?: string; observedAt: string;
      cleanupOwnerCids: readonly string[]}>,
    limits: PublicationLimits): DeliveryContractView;
  existingDeliveryAttemptAction(record?: DeliveryContractView): number;
  deliveryFailureTerminalAction(observed: boolean): number;
  deliveryRecordRetryAction(next: number, count: number): number;
  deliveryTransition(previous: DeliveryContractView | undefined,
    next: DeliveryContractView): boolean;
  deliverySuccessValid(attempt: DeliveryContractView,
    receipt: DeliveryContractView, record: DeliveryContractView): boolean;
  trustedClockNotBefore(previous: string | undefined,
    observedAt: string): boolean;
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
  tenantId: string;
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
export function issueRunDefinition(admission: RunAdmission, scopeId: string,
  runId: string, inputArtifactSetCid: string, createdAt: string,
  validUntil: string): RunDefinition;
/** Bind zero captured Run-start inputs to the checked source-free Program. */
export function issueSourceFreeRunDefinition(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission, scopeId: string,
  runId: string, createdAt: string, validUntil: string): RunDefinition;
export function privateRunDefinition(definition: RunDefinition): Readonly<{
  wire: string;
  cid: string;
}>;
/** Project the owner's unpublished Run state from retained physical facts. */
export function issueUnpublishedRunStateWire(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission,
  definition: RunDefinition, observedAt: string,
  dispatchReserved: boolean,
  preDispatchFailureConfirmed: boolean): string;
/** Project a committed Run with current physical availability observations. */
export function issueSucceededRunStateWire(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission,
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
/** Canonical contract admission is not publication or read authorization. */
export function admitPublicationContract(name: string, wire: string,
  limits: PublicationLimits): PublicationContract;
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
  previous: PublicationContract | undefined, next: PublicationContract,
  uncommittedConfirmed: boolean): void;
/** Immutable request for the full checked Named Result inventory. */
export function issuePublicationRequest(runDefinition: PublicationContract,
  definitions: readonly PublicationContract[], facts: Readonly<{
    tenantId: string;
    authorityScopeCid: string;
    publicationPolicyCid: string;
    publicationTargetCid: string;
    requestedAt: string;
  }>, limits: PublicationLimits): PublicationContract;
/** One attempt identity, separate from Store effects and outcome. */
export function issuePublicationAttempt(request: PublicationContract,
  runDefinition: PublicationContract, facts: Readonly<{
    attemptId: string;
    fenceCid: string;
    externalIdempotencyKey?: string;
    startedAt: string;
  }>, limits: PublicationLimits): PublicationContract;
/** Candidate entry; the Store must atomically validate and install it. */
export function issuePublicIndexEntry(runDefinition: PublicationContract,
  invocation: PublicationContract, manifest: PublicationContract,
  receipt: PublicationContract, capturedRun: PublicationContract,
  durableBindings: readonly PublicationContract[],
  request: PublicationContract, attempt: PublicationContract,
  committedAt: string, limits: PublicationLimits): PublicationContract;
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
}>, request: PublicationContract, attempt: PublicationContract,
  indexEntry: PublicationContract, limits: PublicationLimits): void;
/** Sequence and predecessor come from the shared publication owner. */
export function issuePublicationRecord(attempt: PublicationContract,
  previous: PublicationContract | undefined, facts: Readonly<{
    state: string;
    observedAt: string;
    publicIndexEntry?: PublicationContract;
    failureCid?: string;
    cleanupOwnerCids: readonly string[];
    uncommittedConfirmed: boolean;
  }>, limits: PublicationLimits): PublicationContract;
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
/** Source-free capture has no source-state advances to invent. */
export function issueSourceFreeCapturedRun(
  runDefinition: PublicationContract, invocation: PublicationContract,
  definitions: readonly PublicationContract[],
  artifacts: readonly PublicationContract[],
  manifest: PublicationContract, receipt: PublicationContract,
  snapshots: readonly CapturedResultSnapshot[], authoring: RunEvidence,
  models: readonly RunEvidence[], limits: PublicationLimits):
  PublicationContract;
