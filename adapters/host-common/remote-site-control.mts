import {runtimeField} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import {tuplePair} from './runtime-tuple.mjs';
import type {DispatchInput} from '../../packages/coordinator-core/index.js';

type Quantity = number | bigint;
type DispatchDeclaration = Readonly<DispatchInput>;
type DispatchAdmission = DispatchDeclaration & Readonly<{dispatchRequestCid: string}>;
type Budget = Readonly<{retainedBytes: bigint; executionBytes: bigint}>;
type BudgetAdmission = Budget & Readonly<{budgetCid: string}>;
type OutputIntentDeclaration = Readonly<{
  storeAuthorityCid: string;
  publicationAttemptCid: string;
  resultDefinitionCid: string;
  orderingEvidenceCid: string;
  coordinatorAuthority: string;
  transferAttemptId: string;
  transferRoute: string;
  destinationSite: string;
  destinationSiteGeneration: number;
  transferMaxBytes: Quantity;
  transferExpiresAtMilliseconds: Quantity;
  sourceGrantCid: string;
  destinationGrantCid: string;
  routeCapabilityCid: string;
  transferOrigin: string;
}>;
type OutputIntentProjection = Readonly<{
  store_authority_cid: string;
  publication_attempt_cid: string;
  result_definition_cid: string;
  ordering_evidence_cid: string;
  coordinator_authority: string;
  transfer_attempt: string;
  destination_site_key: string;
  destination_site_generation: number;
  transfer_max_bytes: bigint;
  transfer_expires_unix_ms: bigint;
  source_grant_cid: string;
  destination_grant_cid: string;
  route_capability_cid: string;
  transfer_origin: string;
}>;
type PublicationPayload = Readonly<{
  storeAuthorityCid: string;
  publicationAttemptCid: string;
  materialGenerationCid: string;
  resultDefinitionCid: string;
  logicalRelationCid: string;
  resultSchemaCid: string;
  orderingEvidenceCid: string;
  durableCodecCid: string;
  maxBytes: Quantity;
  rowCount: Quantity;
}>;
type DeliveryContext = Readonly<{
  coordinatorAuthority: string;
  siteKey: string;
  siteGeneration: number;
  authorizationCurrent: boolean;
  cancellationRequested: boolean;
}>;
type SiteObservation = Readonly<{
  revision: number;
  state: readonly number[];
  evidence?: unknown;
  subject?: unknown;
  measurement?: unknown;
}>;
type ErrorDetails = Readonly<{code?: unknown; cause?: unknown}>;
type RuntimeRegistration = Readonly<{
  site: unknown;
  runtimeBundleCid: string;
  connectorRegistration: string;
  connectorRevision: string;
  strategyRevision: string;
}>;
type ExecutionRegistration = RuntimeRegistration & Readonly<{operationCapabilityCid: string}>;
type EvidenceRegistration = RuntimeRegistration & Readonly<{evidenceKind: string; issuerCapabilityCid: string}>;
type OutputMeasurement = Readonly<{
  rowCount: number;
  admissionNodes: number;
  admissionTextBytes: number;
  admissionWork: number;
  columnRows: readonly number[];
  columnBytes: readonly number[];
  columnNodes: readonly number[];
  columnMaxValueBytes: readonly number[];
  columnNullRows: readonly number[];
  columnAdmittedDepths: readonly number[];
}>;
type OutputMeasurementAdmission = OutputMeasurement & Readonly<{measurementCid: string}>;
type ManagedOutput = Readonly<{
  materialGeneration: string;
  managedProfileCid: string;
  resultSchemaCid: string;
  logicalViewCid: string;
  representationCodecCid: string;
  physicalManifestCid: string;
  rowCount: number;
  retainedBytes: bigint;
}>;
type OutputSubject = ManagedOutput & Readonly<{
  dispatchRequestCid: string;
  holdingEvidenceCid: string;
  measurementEvidenceCid: string;
  subjectCid: string;
}>;
type ExecutionEvidence = Readonly<{
  connectorRegistration: string;
  connectorRevision: string;
  dispatchRequestCid: string;
  evidenceKind: string;
  evidenceSubjectCid: string;
  holdingEvidenceCid: string;
  issuerCapabilityCid: string;
  materialGeneration: string;
  obligationsCid: string;
  runtimeBundleCid: string;
  siteGeneration: number;
  siteKey: string;
  strategyRevision: string;
  evidenceCid: string;
}>;

// The compiled Common bindings own opaque values and Result admission.
type CommonSiteBindings = {
  strategyRemoteDispatchPrepare(
    coordinatorAuthority: string, runDefinitionCid: string, taskKey: string, taskAttempt: number,
    dispatchId: string, siteKey: string, siteGeneration: number, runtimeBundleCid: string,
    connectorRegistration: string, connectorRevision: string, strategyRevision: string,
    inputBindingCid: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string,
  ): unknown;
  strategyRemoteDispatchAdmit(
    coordinatorAuthority: string, runDefinitionCid: string, taskKey: string, taskAttempt: number,
    dispatchId: string, claimedRequestCid: string, siteKey: string, siteGeneration: number,
    runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, inputBindingCid: string, obligationsCid: string, budgetCid: string,
    evidenceIssuerCapabilityCid: string, grantCid: string,
  ): unknown;
  strategyRemoteDispatchIdentity(request: unknown): string;
  strategyRemoteBudgetPrepare(retainedBytes: bigint, executionBytes: bigint): unknown;
  strategyRemoteBudgetAdmit(
    retainedBytes: bigint, executionBytes: bigint, claimedBudgetCid: string,
  ): unknown;
  strategyRemoteBudgetIdentity(budget: unknown): string;
  strategyRemoteBudgetJson(budget: unknown): unknown;
  strategyRemoteBudgetCapacity(budget: unknown): readonly [bigint, bigint];
  strategyRemoteDispatchBudgetIdentity(request: unknown): string;
  strategyRemoteRecordMatchesDispatch(record: unknown, request: unknown): boolean;
  strategyRemoteDispatchJson(request: unknown): unknown;
  strategyRemoteInputBindingPrepare(body: string, maxBytes: number): unknown;
  strategyRemoteInputBindingIdentity(binding: unknown): string;
  strategyRemoteInputBindingMatchesDispatch(binding: unknown, request: unknown): boolean;
  strategyRemotePollDispatchJson(request: unknown, binding: unknown): unknown;
  strategyRemoteOutputIntentPrepare(
    request: unknown, storeAuthorityCid: string, publicationAttemptCid: string,
    resultDefinitionCid: string, orderingEvidenceCid: string, coordinatorAuthority: string,
    transferAttempt: string, transferRoute: number, destinationSiteKey: string,
    destinationSiteGeneration: number, transferMaxBytes: bigint, transferExpiresUnixMs: bigint,
    sourceGrantCid: string, destinationGrantCid: string, routeCapabilityCid: string,
    transferOrigin: string,
  ): unknown;
  strategyRemoteOutputIntentIdentity(intent: unknown): string;
  strategyRemotePollOutputRequest(output: unknown): unknown;
  strategyRemotePollOutputIntent(output: unknown): unknown;
  strategyRemoteOutputIntentProjection(intent: unknown): readonly [OutputIntentProjection, string];
  strategyRemotePublicationPayloadPrepare(
    storeAuthorityCid: string, publicationAttemptCid: string, materialGenerationCid: string,
    resultDefinitionCid: string, logicalRelationCid: string, resultSchemaCid: string,
    orderingEvidenceCid: string, durableCodecCid: string, maxBytes: bigint, rowCount: bigint,
  ): unknown;
  strategyRemotePublicationPayloadJson(request: unknown): unknown;
  strategyRemotePublicationPayloadAdmitJson(body: string, claimedRequestCid: string): unknown;
  strategyRemotePollOutputJson(request: unknown, intent: unknown): unknown;
  strategyRemotePollOutputPlanJson(request: unknown, intent: unknown): unknown;
  strategyRemotePollOutputAdmit(body: string): unknown;
  strategyRemotePollOutputPlanAdmit(body: string): unknown;
  strategyRemoteOutputPlanAdmit(
    body: string, output: unknown, subject: unknown, maxChunks: number, maxManifestBytes: number,
    maxReferencedBytes: bigint,
  ): unknown;
  strategyRemoteOutputPlanPrepare(
    output: unknown, subject: unknown, payloadRequest: unknown, transferRequest: unknown,
  ): unknown;
  strategyRemoteOutputPlanJson(plan: unknown): unknown;
  strategyRemoteOutputPlanIdentity(plan: unknown): string;
  strategyRemoteOutputPlanPayloadRequest(plan: unknown): unknown;
  strategyRemoteOutputPlanTransferRequest(plan: unknown): unknown;
  strategyRemoteOutputResultAdmit(
    body: string, output: unknown, payloadRequest: unknown, transferRequest: unknown,
  ): unknown;
  strategyRemoteOutputResultPrepare(
    output: unknown, payloadRequest: unknown, payloadPhysicalDigest: string, transferRecord: unknown,
  ): unknown;
  strategyRemoteOutputResultJson(result: unknown): unknown;
  strategyRemoteOutputResultIdentity(result: unknown): string;
  strategyRemoteCoordinatorOutputReportAckJson(record: unknown, body: string): unknown;
  strategyRemoteOutputReportReplyAdmit(body: string, result: unknown): unknown;
  strategyRemoteOutputResultProjection(result: unknown, transferRequest: unknown): unknown;
  strategyRemoteOutputExpectedIdentity(payloadRequest: unknown, transferRequest: unknown): unknown;
  strategyRemotePollDispatchAdmit(body: string): unknown;
  strategyRemotePollDispatchRequest(dispatch: unknown): unknown;
  strategyRemotePollDispatchBindingBody(dispatch: unknown): string;
  strategyRemotePollQueryJson(request: unknown): unknown;
  strategyRemotePollCancelJson(request: unknown): unknown;
  strategyRemotePollReleaseJson(request: unknown): unknown;
  strategyRemotePollNotSeenJson(request: unknown): unknown;
  strategyRemotePollNotSeenAdmit(body: string, request: unknown): unknown;
  strategyRemoteDispatchReplyJson(record: unknown): unknown;
  strategyRemoteDispatchStatusJson(
    record: unknown, evidence: unknown, subject: unknown, measurement: unknown,
  ): unknown;
  strategyRemoteDispatchAdmitJson(body: string, claimedRequestCid: string): unknown;
  strategyRemoteDispatchResponseAdmitJson(body: string, request: unknown, statusReply: boolean): unknown;
  strategyRemoteDispatchResponseProjection(response: unknown): unknown;
  strategyRemoteDispatchResponseCanRetireCancellationDelivery(response: unknown): boolean;
  strategyRemoteCoordinatorCanRetireCancellationDelivery(record: unknown): boolean;
  strategyRemoteDispatchResponseEvidence(response: unknown): unknown;
  strategyRemoteDispatchResponseSubject(response: unknown): unknown;
  strategyRemoteDispatchResponseMeasurement(response: unknown): unknown;
  strategyRemoteDispatchJournalKey(request: unknown): unknown;
  strategyRemoteDispatchExecutionScope(request: unknown): unknown;
  strategyRemoteManagedRuntimeRegistrationScope(capability: unknown, issuer: unknown): unknown;
  strategyRemoteCoordinatorJournalCreate(authority: string): unknown;
  strategyRemoteCoordinatorIntentPrepare(journal: unknown, request: unknown): unknown;
  strategyRemoteCoordinatorIntentIsNew(admission: unknown): boolean;
  strategyRemoteCoordinatorIntentJson(admission: unknown): unknown;
  strategyRemoteCoordinatorIntentCommit(admission: unknown, durable: boolean): unknown;
  strategyRemoteCoordinatorIntentMatches(record: unknown, request: unknown): boolean;
  strategyRemoteCoordinatorDeliveryEnvelopeJson(request: unknown, body: string): unknown;
  strategyRemoteCoordinatorDeliveryContextCurrent(
    request: unknown, expectedAuthority: string, expectedSite: string, expectedGeneration: number,
    authorizationCurrent: boolean, cancellationRequested: boolean,
  ): unknown;
  strategyRemoteCoordinatorRedeliveryEligible(
    record: unknown, request: unknown, notSeenBody: string, expectedAuthority: string,
    expectedSite: string, expectedGeneration: number, authorizationCurrent: boolean,
    cancellationRequested: boolean,
  ): unknown;
  strategyRemoteCoordinatorIntentRestore(journal: unknown, request: unknown): unknown;
  strategyRemoteCoordinatorPrepareUnknown(record: unknown): unknown;
  strategyRemoteCoordinatorPrepareObservation(
    record: unknown, siteRevision: number, execution: number, evidence: number, cleanup: number,
    materialAvailable: boolean, quarantinedCapacity: boolean, admittedEvidence: unknown,
    admittedSubject: unknown, admittedMeasurement: unknown,
  ): unknown;
  strategyRemoteCoordinatorTransitionProjection(transition: unknown): unknown;
  strategyRemoteCoordinatorTransitionKey(transition: unknown): unknown;
  strategyRemoteCoordinatorTransitionExpectedHistoryJson(transition: unknown): unknown;
  strategyRemoteCoordinatorTransitionHistoryJson(transition: unknown): unknown;
  strategyRemoteCoordinatorTransitionIsReplay(transition: unknown): boolean;
  strategyRemoteCoordinatorObservationIssueCode(failure: unknown): string;
  strategyRemoteCoordinatorRecordHistoryJson(record: unknown): unknown;
  strategyRemoteCoordinatorHistoryRestore(record: unknown, body: string, evidence: unknown): unknown;
  strategyRemoteCoordinatorTransitionCommit(transition: unknown, durable: boolean): unknown;
  strategyRemoteCoordinatorRecordStatus(record: unknown): unknown;
  strategyRemoteCoordinatorRecordRevision(record: unknown): number;
  strategyRemoteCoordinatorRecordRestore(
    record: unknown, revision: number, progress: number, siteRevision: number, execution: number,
    evidence: number, cleanup: number, materialAvailable: boolean, quarantinedCapacity: boolean,
    evidenceCid: string, subjectCid: string, measurementCid: string,
  ): unknown;
  strategyRemoteCoordinatorCompletionEvidenceAvailable(record: unknown): boolean;
  strategyRemoteCoordinatorOutputPrepare(
    journal: unknown, output: unknown, payloadRequest: unknown, transferRequest: unknown,
  ): unknown;
  strategyRemoteCoordinatorOutputIsNew(admission: unknown): boolean;
  strategyRemoteCoordinatorOutputAdmissionKey(admission: unknown): unknown;
  strategyRemoteCoordinatorOutputAdmissionJson(admission: unknown): unknown;
  strategyRemoteCoordinatorOutputCommit(admission: unknown, durable: boolean): unknown;
  strategyRemoteCoordinatorOutputPrepareUnknown(record: unknown): unknown;
  strategyRemoteCoordinatorOutputPrepareSuccess(record: unknown, result: unknown): unknown;
  strategyRemoteCoordinatorOutputTransitionKey(transition: unknown): unknown;
  strategyRemoteCoordinatorOutputTransitionProjection(transition: unknown): unknown;
  strategyRemoteCoordinatorOutputTransitionCommit(transition: unknown, durable: boolean): unknown;
  strategyRemoteCoordinatorOutputRecordKey(record: unknown): unknown;
  strategyRemoteCoordinatorOutputRecordStatus(record: unknown): unknown;
  strategyRemoteCoordinatorOutputRecordRevision(record: unknown): number;
  strategyRemoteCoordinatorOutputRecordResultJson(record: unknown): unknown;
  strategyRemoteCoordinatorOutputRecordResultProjection(record: unknown): unknown;
  strategyRemoteCoordinatorOutputRecordRestore(
    record: unknown, revision: number, progress: number, resultJson: string,
  ): unknown;
  strategyRemoteJournalCreate(site: unknown): unknown;
  strategyRemoteAdmissionPrepare(journal: unknown, request: unknown): unknown;
  strategyRemoteAdmissionIsNew(admission: unknown): boolean;
  strategyRemoteAdmissionJson(admission: unknown): unknown;
  strategyRemoteAdmissionCommit(admission: unknown, durable: boolean): unknown;
  strategyRemoteRegisterExecutionCapability(
    site: unknown, runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, operationCapabilityCid: string,
  ): unknown;
  strategyRemoteExecutionCapabilityScope(capability: unknown): unknown;
  strategyRemotePrepareProvisioning(record: unknown, capability: unknown): unknown;
  strategyRemotePrepareManagedProvisioning(record: unknown, capability: unknown, issuer: unknown): unknown;
  strategyRemotePrepareExecution(record: unknown): unknown;
  strategyRemotePrepareSettled(record: unknown): unknown;
  strategyRemotePrepareFailed(record: unknown): unknown;
  strategyRemotePrepareCancelled(record: unknown): unknown;
  strategyRemotePrepareReconciledFailure(record: unknown): unknown;
  strategyRemotePrepareReconciledCancellation(record: unknown): unknown;
  strategyRemotePrepareRetained(
    record: unknown, materialGeneration: string, holdingEvidenceCid: string,
  ): unknown;
  strategyRemoteRegisterEvidenceIssuer(
    site: unknown, runtimeBundleCid: string, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string, evidenceKind: string, issuerCapabilityCid: string,
  ): unknown;
  strategyRemoteIssueExecutionEvidence(
    issuer: unknown, record: unknown, evidenceSubjectCid: string,
  ): unknown;
  strategyRemoteManagedOutputMeasurementPrepare(
    rowCount: number, admissionNodes: number, admissionTextBytes: number, admissionWork: number,
    columnRows: readonly number[], columnBytes: readonly number[], columnNodes: readonly number[],
    columnMaxValueBytes: readonly number[], columnNullRows: readonly number[],
    columnAdmittedDepths: readonly number[],
  ): unknown;
  strategyRemoteManagedOutputMeasurementIdentity(measurement: unknown): string;
  strategyRemoteManagedOutputMeasurementJson(measurement: unknown): unknown;
  strategyRemoteManagedOutputMeasurementProjection(measurement: unknown): unknown;
  strategyRemoteManagedOutputMeasurementAdmit(
    rowCount: number, admissionNodes: number, admissionTextBytes: number, admissionWork: number,
    columnRows: readonly number[], columnBytes: readonly number[], columnNodes: readonly number[],
    columnMaxValueBytes: readonly number[], columnNullRows: readonly number[],
    columnAdmittedDepths: readonly number[], claimedMeasurementCid: string,
  ): unknown;
  strategyRemoteManagedOutputMeasurementAdmitJson(body: string, claimedMeasurementCid: string): unknown;
  strategyRemoteOutputHoldingEvidenceIdentity(
    request: unknown, materialGeneration: string, retainedBytes: bigint,
  ): unknown;
  strategyRemoteManagedOutputSubjectPrepare(
    dispatchRequestCid: string, materialGeneration: string, holdingEvidenceCid: string,
    managedProfileCid: string, resultSchemaCid: string, logicalViewCid: string,
    representationCodecCid: string, physicalManifestCid: string, measurementEvidenceCid: string,
    rowCount: number, retainedBytes: bigint,
  ): unknown;
  strategyRemoteManagedOutputEvidenceKind(): string;
  strategyRemoteManagedOutputSubjectAdmit(
    dispatchRequestCid: string, materialGeneration: string, holdingEvidenceCid: string,
    managedProfileCid: string, resultSchemaCid: string, logicalViewCid: string,
    representationCodecCid: string, physicalManifestCid: string, measurementEvidenceCid: string,
    rowCount: number, retainedBytes: bigint, claimedSubjectCid: string,
  ): unknown;
  strategyRemoteManagedOutputSubjectAdmitJson(
    body: string, claimedSubjectCid: string, request: unknown,
  ): unknown;
  strategyRemoteManagedOutputSubjectIdentity(subject: unknown): string;
  strategyRemoteManagedOutputSubjectJson(subject: unknown): unknown;
  strategyRemoteManagedOutputSubjectProjection(subject: unknown): unknown;
  strategyRemoteManagedOutputSubjectMatchesMeasurement(subject: unknown, measurement: unknown): boolean;
  strategyRemoteIssueManagedOutputEvidence(issuer: unknown, record: unknown, subject: unknown): unknown;
  strategyRemoteManagedOutputSubjectMatchesEvidence(
    subject: unknown, evidence: unknown, request: unknown,
  ): boolean;
  strategyRemoteExecutionEvidenceAdmit(
    connectorRegistration: string, connectorRevision: string, dispatchRequestCid: string,
    evidenceKind: string, evidenceSubjectCid: string, holdingEvidenceCid: string,
    issuerCapabilityCid: string, materialGeneration: string, obligationsCid: string,
    runtimeBundleCid: string, siteGeneration: number, siteKey: string, strategyRevision: string,
    claimedEvidenceCid: string,
  ): unknown;
  strategyRemoteExecutionEvidenceAdmitJson(
    body: string, claimedEvidenceCid: string, request: unknown,
  ): unknown;
  strategyRemoteExecutionEvidenceIdentity(evidence: unknown): string;
  strategyRemoteExecutionEvidenceMatchesDispatch(evidence: unknown, request: unknown): boolean;
  strategyRemoteExecutionEvidenceJson(evidence: unknown): unknown;
  strategyRemotePrepareEvidence(record: unknown, evidence: unknown): unknown;
  strategyRemotePrepareEvidenceRejection(record: unknown): unknown;
  strategyRemoteRuntimeAdmission(
    runtimeClosed: boolean, recordMatches: boolean, registrationAvailable: boolean,
    budgetAvailable: boolean, activeDispatch: boolean, siteAvailable: boolean,
    capacitySupported: boolean, recordStartable: boolean,
  ): number;
  strategyRemoteRuntimeStartable(record: unknown): boolean;
  strategyRemoteRuntimeCustodyCreate(): unknown;
  strategyRemoteRuntimeRestoreFailedPartialCustody(
    record: unknown, expectedRevision: number, sourceRequestCid: string, sourceWire: string,
    materialGeneration: string, sourceMeasurementCid: string, measurement: unknown, sourceOwner: string,
    sourceGeneration: string, processRequestCid: string, processMaterialGeneration: string,
    processOwner: string, processGeneration: string,
  ): unknown;
  strategyRemoteRuntimeRestoreCompletedCleanupCustody(
    record: unknown, evidence: unknown, subject: unknown, measurement: unknown,
  ): unknown;
  strategyRemoteRuntimeCustodyAcquireOperation(custody: unknown): boolean;
  strategyRemoteRuntimeCustodySettleOperation(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyOperationSettled(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyOperationAcquired(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyAcquireOutput(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyReleaseOutput(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyOutputReleased(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyOutputAcquired(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyAcquireHolding(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyReleaseHolding(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyHoldingReleased(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyHoldingAcquired(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyAcquireBundle(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyReleaseBundle(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyBundleReleased(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyBundleAcquired(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyRecordFailure(
    custody: unknown, cancelled: boolean, stopRequired: boolean, stopConfirmed: boolean,
  ): boolean;
  strategyRemoteRuntimeCustodyConfirmStop(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyStopPending(custody: unknown): boolean;
  strategyRemoteRuntimeCustodyResourcesReclaimed(custody: unknown): boolean;
  strategyRemoteRuntimeSuccessAction(record: unknown, custody: unknown): unknown;
  strategyRemoteRuntimeFailurePlan(record: unknown, cancelled: boolean, stopConfirmed: boolean): unknown;
  strategyRemoteRuntimeOwnedFailurePlan(record: unknown, custody: unknown): unknown;
  strategyRemoteRuntimeCleanupPlan(
    record: unknown, cancelled: boolean, stopConfirmed: boolean, resourcesReclaimed: boolean,
  ): unknown;
  strategyRemoteRuntimeOwnedCleanupPlan(record: unknown, custody: unknown): unknown;
  strategyRemoteRuntimeReclaimUnknownPlan(record: unknown): unknown;
  strategyRemoteRuntimeStepAction(step: unknown): number;
  strategyRemoteRuntimeStepTransition(step: unknown): unknown;
  strategyRemotePrepareUnknown(record: unknown): unknown;
  strategyRemotePrepareRelease(record: unknown): unknown;
  strategyRemotePrepareReleased(record: unknown): unknown;
  strategyRemotePrepareLossRecovery(record: unknown): unknown;
  strategyRemotePrepareForceLoss(journal: unknown, record: unknown, authorized: boolean): unknown;
  strategyRemoteForceLossProjection(transition: unknown): unknown;
  strategyRemoteForceLossKey(transition: unknown): unknown;
  strategyRemoteForceLossCommit(transition: unknown, durable: boolean): unknown;
  strategyRemotePrepareRestart(journal: unknown, replacement: unknown): unknown;
  strategyRemoteRestartCount(restart: unknown): number;
  strategyRemoteRestartAt(restart: unknown, index: number): unknown;
  strategyRemoteRestartMetadata(restart: unknown): unknown;
  strategyRemoteRestartCommit(restart: unknown, durable: boolean): unknown;
  strategyRemoteTransitionProjection(transition: unknown): unknown;
  strategyRemoteTransitionKey(transition: unknown): unknown;
  strategyRemoteTransitionCommit(transition: unknown, durable: boolean): unknown;
  strategyRemoteRecordStatus(record: unknown): unknown;
  strategyRemoteRecordRevision(record: unknown): number;
  strategyRemoteRecordRestore(
    record: unknown, revision: number, execution: number, evidence: number, cleanup: number,
    materialAvailable: boolean, quarantinedCapacity: boolean, materialGeneration: string,
    holdingEvidenceCid: string, executionEvidenceCid: string,
  ): unknown;
  strategyRemoteDurableRecordAdmitJson(body: string): unknown;
  strategyRemoteDurableRecordRestore(journal: unknown, durable: unknown): unknown;
  strategyRemoteRecordDurableJson(record: unknown): unknown;
  strategyRemoteAdmissionDurableJson(admission: unknown): unknown;
  strategyRemoteTransitionDurableJson(transition: unknown): unknown;
  strategyRemoteTransitionExpectedRevision(transition: unknown): number;
  strategyRemoteDurableRecordJson(record: unknown): string;
  strategyRemoteDurableRecordRevision(record: unknown): number;
  strategyRemoteDurableRecordKey(record: unknown): unknown;
  strategyRemoteDurableRecordIdentity(record: unknown): string;
  strategyRemoteHistoricalRestore(journal: unknown, request: unknown): unknown;
};

type Tail<Values extends readonly unknown[]> = Values extends readonly [unknown, ...infer Rest] ? Rest : never;
type SubjectControl = Readonly<{
  identity: CommonSiteBindings['strategyRemoteDispatchIdentity'];
  managedOutputMeasurementIdentity: CommonSiteBindings['strategyRemoteManagedOutputMeasurementIdentity'];
}>;

const remoteSiteControls = new WeakMap<object, ReturnType<typeof createRemoteSiteControl>>();

export function remoteSiteControl(moon: CommonSiteBindings) {
  let control = remoteSiteControls.get(moon);
  if (control !== undefined) return control;
  control = createRemoteSiteControl(moon);
  remoteSiteControls.set(moon, control);
  return control;
}

function createRemoteSiteControl(moon: CommonSiteBindings) {
  let control: SubjectControl | undefined;
  const fields = (request: DispatchDeclaration): Parameters<CommonSiteBindings['strategyRemoteDispatchPrepare']> => [
    request.coordinatorAuthority,
    request.runDefinitionCid,
    request.taskKey,
    request.taskAttempt,
    request.dispatchId,
    request.siteKey,
    request.siteGeneration,
    request.runtimeBundleCid,
    request.connectorRegistration,
    request.connectorRevision,
    request.strategyRevision,
    request.inputBindingCid,
    request.obligationsCid,
    request.budgetCid,
    request.evidenceIssuerCapabilityCid,
    request.grantCid,
  ];
  const int64 = (value: Quantity, label: string) => {
    if (typeof value === 'bigint' && value >= 0n) return value;
    if (Number.isSafeInteger(value) && value >= 0) return BigInt(value);
    throw new TypeError(`Invalid remote output ${label}`);
  };
  const site = Object.freeze({
    prepare(request: DispatchDeclaration) {
      if (request === null || typeof request !== 'object') {
        throw new TypeError('Invalid remote dispatch request');
      }
      return checked(moon.strategyRemoteDispatchPrepare(...fields(request)));
    },
    admit(request: DispatchAdmission) {
      if (request === null || typeof request !== 'object') {
        throw new TypeError('Invalid remote dispatch request');
      }
      const values: Array<Parameters<CommonSiteBindings['strategyRemoteDispatchPrepare']>[number]> = fields(request);
      values.splice(5, 0, request.dispatchRequestCid);
      return checked(moon.strategyRemoteDispatchAdmit(...values as Parameters<CommonSiteBindings['strategyRemoteDispatchAdmit']>));
    },
    identity: moon.strategyRemoteDispatchIdentity,
    prepareBudget: (configuration: Budget) => checked(
      moon.strategyRemoteBudgetPrepare(
        configuration.retainedBytes,
        configuration.executionBytes,
      ),
    ),
    admitBudget: (configuration: BudgetAdmission) => checked(
      moon.strategyRemoteBudgetAdmit(
        configuration.retainedBytes,
        configuration.executionBytes,
        configuration.budgetCid,
      ),
    ),
    budgetIdentity: moon.strategyRemoteBudgetIdentity,
    budgetJson: (value: unknown) => checked(moon.strategyRemoteBudgetJson(value)) as string,
    budgetCapacity: (value: unknown) => tuplePair(
      moon.strategyRemoteBudgetCapacity(value),
    ) as ReturnType<CommonSiteBindings['strategyRemoteBudgetCapacity']> | undefined,
    dispatchBudgetIdentity: moon.strategyRemoteDispatchBudgetIdentity,
    recordMatchesDispatch: moon.strategyRemoteRecordMatchesDispatch,
    requestJson: (value: unknown) => checked(moon.strategyRemoteDispatchJson(value)) as string,
    prepareInputBinding: (body: string, maxBytes: number = 1_048_576) => checked(
      moon.strategyRemoteInputBindingPrepare(body, maxBytes),
    ),
    inputBindingIdentity: moon.strategyRemoteInputBindingIdentity,
    inputBindingMatchesDispatch:
      moon.strategyRemoteInputBindingMatchesDispatch,
    pollJson: (value: unknown, binding: unknown) => checked(
      moon.strategyRemotePollDispatchJson(value, binding),
    ) as string,
    prepareOutputIntent(request: unknown, configuration: OutputIntentDeclaration) {
      if (configuration === null || typeof configuration !== 'object' ||
          !Number.isSafeInteger(configuration.destinationSiteGeneration) ||
          configuration.destinationSiteGeneration < 0) {
        throw new TypeError('Invalid remote output intent');
      }
      const route = configuration.transferRoute === 'direct' ? 0
        : configuration.transferRoute === 'store' ? 1 : -1;
      return checked(moon.strategyRemoteOutputIntentPrepare(
        request,
        configuration.storeAuthorityCid,
        configuration.publicationAttemptCid,
        configuration.resultDefinitionCid,
        configuration.orderingEvidenceCid,
        configuration.coordinatorAuthority,
        configuration.transferAttemptId,
        route,
        configuration.destinationSite,
        configuration.destinationSiteGeneration,
        int64(configuration.transferMaxBytes, 'capacity'),
        int64(configuration.transferExpiresAtMilliseconds, 'expiry'),
        configuration.sourceGrantCid,
        configuration.destinationGrantCid,
        configuration.routeCapabilityCid,
        configuration.transferOrigin,
      ));
    },
    outputIntentIdentity: moon.strategyRemoteOutputIntentIdentity,
    pollOutputRequest: moon.strategyRemotePollOutputRequest,
    pollOutputIntent: moon.strategyRemotePollOutputIntent,
    outputIntentProjection(intent: unknown) {
      const projected = moon.strategyRemoteOutputIntentProjection(intent);
      const value = runtimeField(projected, 0) as OutputIntentProjection;
      return Object.freeze({storeAuthorityCid: value.store_authority_cid,
        publicationAttemptCid: value.publication_attempt_cid,
        resultDefinitionCid: value.result_definition_cid,
        orderingEvidenceCid: value.ordering_evidence_cid,
        coordinatorAuthority: value.coordinator_authority,
        transferAttemptId: value.transfer_attempt,
        transferRoute: runtimeField(projected, 1) as string,
        destinationSite: value.destination_site_key,
        destinationSiteGeneration: value.destination_site_generation,
        transferMaxBytes: value.transfer_max_bytes,
        transferExpiresAtMilliseconds: value.transfer_expires_unix_ms,
        sourceGrantCid: value.source_grant_cid,
        destinationGrantCid: value.destination_grant_cid,
        routeCapabilityCid: value.route_capability_cid,
        transferOrigin: value.transfer_origin});
    },
    preparePublicationPayload(configuration: PublicationPayload) {
      if (configuration === null || typeof configuration !== 'object') {
        throw new TypeError('Invalid remote publication payload');
      }
      return checked(moon.strategyRemotePublicationPayloadPrepare(
        configuration.storeAuthorityCid,
        configuration.publicationAttemptCid,
        configuration.materialGenerationCid,
        configuration.resultDefinitionCid,
        configuration.logicalRelationCid,
        configuration.resultSchemaCid,
        configuration.orderingEvidenceCid,
        configuration.durableCodecCid,
        int64(configuration.maxBytes, 'publication capacity'),
        int64(configuration.rowCount, 'row count'),
      ));
    },
    publicationPayloadJson: (value: unknown) => checked(
      moon.strategyRemotePublicationPayloadJson(value),
    ) as string,
    admitPublicationPayloadJson: (body: string, claimedRequestCid: string) => checked(
      moon.strategyRemotePublicationPayloadAdmitJson(
        body,
        claimedRequestCid,
      ),
    ),
    pollOutputJson: (request: unknown, intent: unknown) => checked(
      moon.strategyRemotePollOutputJson(request, intent),
    ) as string,
    pollOutputPlanJson: (request: unknown, intent: unknown) => checked(
      moon.strategyRemotePollOutputPlanJson(request, intent),
    ) as string,
    admitPollOutput: (body: string) => checked(
      moon.strategyRemotePollOutputAdmit(body),
    ),
    admitPollOutputPlan: (body: string) => checked(
      moon.strategyRemotePollOutputPlanAdmit(body),
    ),
    admitOutputPlan: (
      body: string,
      output: unknown,
      subject: unknown,
      maxChunks: number,
      maxManifestBytes: number,
      maxReferencedBytes: Quantity,
    ) => checked(moon.strategyRemoteOutputPlanAdmit(
      body,
      output,
      subject,
      maxChunks,
      maxManifestBytes,
      int64(maxReferencedBytes, 'remote output plan capacity'),
    )),
    prepareOutputPlan: (
      output: unknown,
      subject: unknown,
      payloadRequest: unknown,
      transferRequest: unknown,
    ) => checked(moon.strategyRemoteOutputPlanPrepare(
      output,
      subject,
      payloadRequest,
      transferRequest,
    )),
    outputPlanJson: (plan: unknown) => checked(
      moon.strategyRemoteOutputPlanJson(plan),
    ) as string,
    outputPlanIdentity: moon.strategyRemoteOutputPlanIdentity,
    outputPlanPayloadRequest: moon.strategyRemoteOutputPlanPayloadRequest,
    outputPlanTransferRequest: moon.strategyRemoteOutputPlanTransferRequest,
    admitOutputResult: (body: string, output: unknown, payloadRequest: unknown, transferRequest: unknown) => checked(moon.strategyRemoteOutputResultAdmit(
      body,
      output,
      payloadRequest,
      transferRequest,
    )),
    prepareOutputResult: (
      output: unknown,
      payloadRequest: unknown,
      payloadDigest: string,
      transferRecord: unknown,
    ) => checked(moon.strategyRemoteOutputResultPrepare(
      output,
      payloadRequest,
      payloadDigest,
      transferRecord,
    )),
    outputResultJson: (result: unknown) => checked(
      moon.strategyRemoteOutputResultJson(result),
    ) as string,
    outputResultIdentity: moon.strategyRemoteOutputResultIdentity,
    coordinatorOutputReportAckJson: (record: unknown, body: string) => checked(
      moon.strategyRemoteCoordinatorOutputReportAckJson(record, body)) as string,
    admitOutputReportReply: (body: string, result: unknown) => checked(
      moon.strategyRemoteOutputReportReplyAdmit(body, result)) as boolean,
    outputResultProjection: (result: unknown, transferRequest: unknown) => checked(
      moon.strategyRemoteOutputResultProjection(result, transferRequest),
    ),
    outputExpectedIdentity: (payloadRequest: unknown, transferRequest: unknown) => moon.strategyRemoteOutputExpectedIdentity(
        payloadRequest,
        transferRequest,
      ),
    admitPollDispatch: (body: string) => checked(
      moon.strategyRemotePollDispatchAdmit(body),
    ),
    pollDispatchRequest: moon.strategyRemotePollDispatchRequest,
    pollDispatchBindingBody: moon.strategyRemotePollDispatchBindingBody,
    pollQueryJson: (value: unknown) => checked(moon.strategyRemotePollQueryJson(value)) as string,
    pollCancelJson: (value: unknown) => checked(moon.strategyRemotePollCancelJson(value)) as string,
    pollReleaseJson: (value: unknown) => checked(
      moon.strategyRemotePollReleaseJson(value),
    ) as string,
    pollNotSeenJson: (value: unknown) => checked(
      moon.strategyRemotePollNotSeenJson(value),
    ) as string,
    admitPollNotSeen: (body: string, request: unknown) => checked(
      moon.strategyRemotePollNotSeenAdmit(body, request),
    ) as boolean,
    replyJson: (value: unknown) => checked(moon.strategyRemoteDispatchReplyJson(value)) as string,
    statusJson: (record: unknown, evidence: unknown, subject: unknown, measurement: unknown) => checked(
      moon.strategyRemoteDispatchStatusJson(
        record,
        evidence,
        subject,
        measurement,
      ),
    ) as string,
    admitJson: (body: string, claimedRequestCid: string) => checked(
      moon.strategyRemoteDispatchAdmitJson(body, claimedRequestCid),
    ),
    admitResponseJson: (body: string, request: unknown, statusReply: boolean) => checked(
      moon.strategyRemoteDispatchResponseAdmitJson(
        body,
        request,
        statusReply,
      ),
    ),
    responseProjection: moon.strategyRemoteDispatchResponseProjection,
    responseCanRetireCancellationDelivery:
      moon.strategyRemoteDispatchResponseCanRetireCancellationDelivery,
    coordinatorCanRetireCancellationDelivery:
      moon.strategyRemoteCoordinatorCanRetireCancellationDelivery,
    responseEvidence: moon.strategyRemoteDispatchResponseEvidence,
    responseSubject: moon.strategyRemoteDispatchResponseSubject,
    responseMeasurement: moon.strategyRemoteDispatchResponseMeasurement,
    journalKey: moon.strategyRemoteDispatchJournalKey,
    executionScope: moon.strategyRemoteDispatchExecutionScope,
    managedRuntimeRegistrationScope: (capability: unknown, issuer: unknown) => checked(
      moon.strategyRemoteManagedRuntimeRegistrationScope(capability, issuer),
    ),
    createCoordinatorJournal: (authority: string) => checked(
      moon.strategyRemoteCoordinatorJournalCreate(authority),
    ),
    prepareCoordinatorIntent: (journal: unknown, request: unknown) => checked(
      moon.strategyRemoteCoordinatorIntentPrepare(journal, request),
    ),
    coordinatorIntentIsNew: moon.strategyRemoteCoordinatorIntentIsNew,
    coordinatorIntentJson: (value: unknown) => checked(
      moon.strategyRemoteCoordinatorIntentJson(value),
    ) as string,
    commitCoordinatorIntent: (value: unknown, durable: boolean) => checked(
      moon.strategyRemoteCoordinatorIntentCommit(value, durable),
    ),
    coordinatorIntentMatches:
      moon.strategyRemoteCoordinatorIntentMatches,
    coordinatorDeliveryEnvelopeJson: (request: unknown, body: string) => checked(
      moon.strategyRemoteCoordinatorDeliveryEnvelopeJson(request, body),
    ) as string,
    coordinatorDeliveryContextCurrent: (request: unknown, context: DeliveryContext) => checked(
      moon.strategyRemoteCoordinatorDeliveryContextCurrent(request,
        context.coordinatorAuthority, context.siteKey, context.siteGeneration,
        context.authorizationCurrent, context.cancellationRequested),
    ) as boolean,
    coordinatorRedeliveryEligible: (
      record: unknown,
      request: unknown,
      notSeenBody: string,
      context: DeliveryContext,
    ) => checked(
      moon.strategyRemoteCoordinatorRedeliveryEligible(record, request,
        notSeenBody, context.coordinatorAuthority, context.siteKey,
        context.siteGeneration, context.authorizationCurrent,
        context.cancellationRequested),
    ) as boolean,
    restoreCoordinatorIntent: (journal: unknown, request: unknown) => checked(
      moon.strategyRemoteCoordinatorIntentRestore(journal, request),
    ),
    prepareCoordinatorUnknown: (record: unknown) => checked(
      moon.strategyRemoteCoordinatorPrepareUnknown(record),
    ),
    prepareCoordinatorObservation(record: unknown, observation: SiteObservation) {
      if (observation === null || typeof observation !== 'object' ||
          !Number.isSafeInteger(observation.revision) ||
          !Array.isArray(observation.state) ||
          observation.state.length !== 5) {
        throw new TypeError('Invalid remote Site observation');
      }
      const [execution, evidence, cleanup, available, quarantined] =
        observation.state;
      return checked(
        moon.strategyRemoteCoordinatorPrepareObservation(
          record,
          observation.revision,
          execution,
          evidence,
          cleanup,
          available === 1,
          quarantined === 1,
          observation.evidence,
          observation.subject,
          observation.measurement,
        ),
      );
    },
    coordinatorTransitionProjection:
      moon.strategyRemoteCoordinatorTransitionProjection,
    coordinatorTransitionKey: moon.strategyRemoteCoordinatorTransitionKey,
    coordinatorTransitionExpectedHistoryJson: (transition: unknown) => checked(
      moon.strategyRemoteCoordinatorTransitionExpectedHistoryJson(transition)) as string,
    coordinatorTransitionHistoryJson: (transition: unknown) => checked(
      moon.strategyRemoteCoordinatorTransitionHistoryJson(transition)) as string,
    coordinatorTransitionIsReplay: moon.strategyRemoteCoordinatorTransitionIsReplay,
    coordinatorObservationIssueCode: (error: unknown) => (error as ErrorDetails | null | undefined)?.code === 'MoonBitHostFailure'
      ? moon.strategyRemoteCoordinatorObservationIssueCode((error as ErrorDetails).cause) : '',
    coordinatorRecordHistoryJson: (record: unknown) => checked(
      moon.strategyRemoteCoordinatorRecordHistoryJson(record)) as string,
    restoreCoordinatorHistoryJson: (record: unknown, body: string, evidence: unknown) => checked(
      moon.strategyRemoteCoordinatorHistoryRestore(record, body, evidence)) as undefined,
    commitCoordinatorTransition: (transition: unknown, durable: boolean) => checked(
      moon.strategyRemoteCoordinatorTransitionCommit(transition, durable),
    ) as undefined,
    coordinatorRecordStatus: moon.strategyRemoteCoordinatorRecordStatus,
    coordinatorRecordRevision: moon.strategyRemoteCoordinatorRecordRevision,
    restoreCoordinatorRecord: (record: unknown, state: unknown) => {
      if (!Array.isArray(state) || state.length !== 11) {
        throw new TypeError('Invalid remote Coordinator state');
      }
      return checked(
        moon.strategyRemoteCoordinatorRecordRestore(record, ...state as Tail<Parameters<CommonSiteBindings['strategyRemoteCoordinatorRecordRestore']>>),
      );
    },
    coordinatorCompletionEvidenceAvailable:
      moon.strategyRemoteCoordinatorCompletionEvidenceAvailable,
    prepareCoordinatorOutput: (
      journal: unknown,
      output: unknown,
      payloadRequest: unknown,
      transferRequest: unknown,
    ) => checked(moon.strategyRemoteCoordinatorOutputPrepare(
      journal,
      output,
      payloadRequest,
      transferRequest,
    )),
    coordinatorOutputIsNew:
      moon.strategyRemoteCoordinatorOutputIsNew,
    coordinatorOutputAdmissionKey:
      moon.strategyRemoteCoordinatorOutputAdmissionKey,
    coordinatorOutputAdmissionJson: (admission: unknown) => checked(
      moon.strategyRemoteCoordinatorOutputAdmissionJson(admission),
    ) as string,
    commitCoordinatorOutput: (admission: unknown, durable: boolean) => checked(
      moon.strategyRemoteCoordinatorOutputCommit(admission, durable),
    ),
    prepareCoordinatorOutputUnknown: (record: unknown) => checked(
      moon.strategyRemoteCoordinatorOutputPrepareUnknown(record),
    ),
    prepareCoordinatorOutputSuccess: (record: unknown, result: unknown) => checked(
      moon.strategyRemoteCoordinatorOutputPrepareSuccess(record, result),
    ),
    coordinatorOutputTransitionKey:
      moon.strategyRemoteCoordinatorOutputTransitionKey,
    coordinatorOutputTransitionProjection:
      moon.strategyRemoteCoordinatorOutputTransitionProjection,
    commitCoordinatorOutputTransition: (transition: unknown, durable: boolean) => checked(
      moon.strategyRemoteCoordinatorOutputTransitionCommit(
        transition,
        durable,
      ),
    ) as undefined,
    coordinatorOutputRecordKey:
      moon.strategyRemoteCoordinatorOutputRecordKey,
    coordinatorOutputRecordStatus:
      moon.strategyRemoteCoordinatorOutputRecordStatus,
    coordinatorOutputRecordRevision:
      moon.strategyRemoteCoordinatorOutputRecordRevision,
    coordinatorOutputRecordResultJson: (record: unknown) => checked(
      moon.strategyRemoteCoordinatorOutputRecordResultJson(record),
    ) as string,
    coordinatorOutputRecordResultProjection: (record: unknown) => checked(
      moon.strategyRemoteCoordinatorOutputRecordResultProjection(record),
    ),
    restoreCoordinatorOutputRecord: (
      record: unknown,
      revision: number,
      progress: number,
      resultJson: string,
    ) => checked(moon.strategyRemoteCoordinatorOutputRecordRestore(
      record,
      revision,
      progress,
      resultJson,
    )) as undefined,
    createJournal: (value: unknown) => checked(moon.strategyRemoteJournalCreate(value)),
    prepareAdmission: (journal: unknown, request: unknown) => checked(
      moon.strategyRemoteAdmissionPrepare(journal, request),
    ),
    admissionIsNew: moon.strategyRemoteAdmissionIsNew,
    admissionJson: (value: unknown) => checked(
      moon.strategyRemoteAdmissionJson(value),
    ) as string,
    commitAdmission: (value: unknown, durable: boolean) => checked(
      moon.strategyRemoteAdmissionCommit(value, durable),
    ),
    registerExecutionCapability: (configuration: ExecutionRegistration) => checked(
      moon.strategyRemoteRegisterExecutionCapability(
        configuration.site,
        configuration.runtimeBundleCid,
        configuration.connectorRegistration,
        configuration.connectorRevision,
        configuration.strategyRevision,
        configuration.operationCapabilityCid,
      ),
    ),
    executionCapabilityScope: moon.strategyRemoteExecutionCapabilityScope,
    prepareProvisioning: (value: unknown, capability: unknown) => checked(
      moon.strategyRemotePrepareProvisioning(value, capability),
    ),
    prepareManagedProvisioning: (value: unknown, capability: unknown, issuer: unknown) => checked(
      moon.strategyRemotePrepareManagedProvisioning(value, capability, issuer),
    ),
    prepareExecution: (value: unknown) => checked(
      moon.strategyRemotePrepareExecution(value),
    ),
    prepareSettled: (value: unknown) => checked(
      moon.strategyRemotePrepareSettled(value),
    ),
    prepareFailed: (value: unknown) => checked(
      moon.strategyRemotePrepareFailed(value),
    ),
    prepareCancelled: (value: unknown) => checked(
      moon.strategyRemotePrepareCancelled(value),
    ),
    prepareReconciledFailure: (value: unknown) => checked(
      moon.strategyRemotePrepareReconciledFailure(value),
    ),
    prepareReconciledCancellation: (value: unknown) => checked(
      moon.strategyRemotePrepareReconciledCancellation(value),
    ),
    prepareRetained: (value: unknown, material: string, holding: string) => checked(
      moon.strategyRemotePrepareRetained(value, material, holding),
    ),
    registerEvidenceIssuer: (configuration: EvidenceRegistration) => checked(
      moon.strategyRemoteRegisterEvidenceIssuer(
        configuration.site,
        configuration.runtimeBundleCid,
        configuration.connectorRegistration,
        configuration.connectorRevision,
        configuration.strategyRevision,
        configuration.evidenceKind,
        configuration.issuerCapabilityCid,
      ),
    ),
    issueExecutionEvidence: (issuer: unknown, record: unknown, evidenceSubjectCid: string) => checked(
      moon.strategyRemoteIssueExecutionEvidence(
        issuer,
        record,
        evidenceSubjectCid,
      ),
    ),
    prepareManagedOutputMeasurement: (measurement: OutputMeasurement) => checked(
      moon.strategyRemoteManagedOutputMeasurementPrepare(
        measurement.rowCount,
        measurement.admissionNodes,
        measurement.admissionTextBytes,
        measurement.admissionWork,
        measurement.columnRows,
        measurement.columnBytes,
        measurement.columnNodes,
        measurement.columnMaxValueBytes,
        measurement.columnNullRows,
        measurement.columnAdmittedDepths,
      ),
    ),
    managedOutputMeasurementIdentity:
      moon.strategyRemoteManagedOutputMeasurementIdentity,
    managedOutputMeasurementJson: (value: unknown) => checked(
      moon.strategyRemoteManagedOutputMeasurementJson(value),
    ) as string,
    managedOutputMeasurementProjection:
      moon.strategyRemoteManagedOutputMeasurementProjection,
    admitManagedOutputMeasurement: (measurement: OutputMeasurementAdmission) => checked(
      moon.strategyRemoteManagedOutputMeasurementAdmit(
        measurement.rowCount,
        measurement.admissionNodes,
        measurement.admissionTextBytes,
        measurement.admissionWork,
        measurement.columnRows,
        measurement.columnBytes,
        measurement.columnNodes,
        measurement.columnMaxValueBytes,
        measurement.columnNullRows,
        measurement.columnAdmittedDepths,
        measurement.measurementCid,
      ),
    ),
    admitManagedOutputMeasurementJson: (body: string, claimedMeasurementCid: string) => checked(
      moon.strategyRemoteManagedOutputMeasurementAdmitJson(
        body,
        claimedMeasurementCid,
      ),
    ),
    outputHoldingEvidenceIdentity: (dispatch: unknown, materialGeneration: string, retainedBytes: bigint) => checked(
      moon.strategyRemoteOutputHoldingEvidenceIdentity(
        dispatch,
        materialGeneration,
        retainedBytes,
      ),
    ) as string,
    prepareManagedOutputSubject: (
      dispatch: unknown,
      output: ManagedOutput,
      measurement: unknown,
      holdingEvidenceCid: string,
    ) => checked(
      moon.strategyRemoteManagedOutputSubjectPrepare(
        control!.identity(dispatch),
        output.materialGeneration,
        holdingEvidenceCid,
        output.managedProfileCid,
        output.resultSchemaCid,
        output.logicalViewCid,
        output.representationCodecCid,
        output.physicalManifestCid,
        control!.managedOutputMeasurementIdentity(measurement),
        output.rowCount,
        output.retainedBytes,
      ),
    ),
    managedOutputEvidenceKind:
      moon.strategyRemoteManagedOutputEvidenceKind(),
    admitManagedOutputSubject: (subject: OutputSubject) => checked(
      moon.strategyRemoteManagedOutputSubjectAdmit(
        subject.dispatchRequestCid,
        subject.materialGeneration,
        subject.holdingEvidenceCid,
        subject.managedProfileCid,
        subject.resultSchemaCid,
        subject.logicalViewCid,
        subject.representationCodecCid,
        subject.physicalManifestCid,
        subject.measurementEvidenceCid,
        subject.rowCount,
        subject.retainedBytes,
        subject.subjectCid,
      ),
    ),
    admitManagedOutputSubjectJson: (body: string, claimedSubjectCid: string, dispatch: unknown) => checked(
      moon.strategyRemoteManagedOutputSubjectAdmitJson(
        body,
        claimedSubjectCid,
        dispatch,
      ),
    ),
    managedOutputSubjectIdentity:
      moon.strategyRemoteManagedOutputSubjectIdentity,
    managedOutputSubjectJson: (value: unknown) => checked(
      moon.strategyRemoteManagedOutputSubjectJson(value),
    ) as string,
    managedOutputSubjectProjection:
      moon.strategyRemoteManagedOutputSubjectProjection,
    managedOutputSubjectMatchesMeasurement:
      moon.strategyRemoteManagedOutputSubjectMatchesMeasurement,
    issueManagedOutputEvidence: (issuer: unknown, record: unknown, subject: unknown) => checked(
      moon.strategyRemoteIssueManagedOutputEvidence(
        issuer,
        record,
        subject,
      ),
    ),
    managedOutputSubjectMatchesEvidence:
      moon.strategyRemoteManagedOutputSubjectMatchesEvidence,
    admitExecutionEvidence: (evidence: ExecutionEvidence) => checked(
      moon.strategyRemoteExecutionEvidenceAdmit(
        evidence.connectorRegistration,
        evidence.connectorRevision,
        evidence.dispatchRequestCid,
        evidence.evidenceKind,
        evidence.evidenceSubjectCid,
        evidence.holdingEvidenceCid,
        evidence.issuerCapabilityCid,
        evidence.materialGeneration,
        evidence.obligationsCid,
        evidence.runtimeBundleCid,
        evidence.siteGeneration,
        evidence.siteKey,
        evidence.strategyRevision,
        evidence.evidenceCid,
      ),
    ),
    admitExecutionEvidenceJson: (body: string, claimedEvidenceCid: string, dispatch: unknown) => checked(
      moon.strategyRemoteExecutionEvidenceAdmitJson(
        body,
        claimedEvidenceCid,
        dispatch,
      ),
    ),
    evidenceIdentity: moon.strategyRemoteExecutionEvidenceIdentity,
    evidenceMatchesDispatch:
      moon.strategyRemoteExecutionEvidenceMatchesDispatch,
    evidenceJson: (value: unknown) => checked(
      moon.strategyRemoteExecutionEvidenceJson(value),
    ) as string,
    prepareEvidence: (value: unknown, evidence: unknown) => checked(
      moon.strategyRemotePrepareEvidence(value, evidence),
    ),
    prepareEvidenceRejection: (value: unknown) => checked(
      moon.strategyRemotePrepareEvidenceRejection(value),
    ),
    runtimeAdmission: moon.strategyRemoteRuntimeAdmission,
    runtimeStartable: moon.strategyRemoteRuntimeStartable,
    createRuntimeCustody: moon.strategyRemoteRuntimeCustodyCreate,
    restoreFailedPartialRuntimeCustody(
      record: unknown,
      expectedRevision: number,
      sourceRequestCid: string,
      sourceWire: string,
      materialGeneration: string,
      sourceMeasurementCid: string,
      measurement: unknown,
      sourceOwner: string,
      sourceGeneration: string,
      processRequestCid: string,
      processMaterialGeneration: string,
      processOwner: string,
      processGeneration: string,
    ) {
      return checked(moon.strategyRemoteRuntimeRestoreFailedPartialCustody(record,
        expectedRevision, sourceRequestCid, sourceWire, materialGeneration,
        sourceMeasurementCid, measurement, sourceOwner, sourceGeneration,
        processRequestCid, processMaterialGeneration, processOwner, processGeneration));
    },
    restoreCompletedCleanupRuntimeCustody(
      record: unknown,
      evidence: unknown,
      subject: unknown,
      measurement: unknown,
    ) {
      return checked(moon.strategyRemoteRuntimeRestoreCompletedCleanupCustody(
        record, evidence, subject, measurement));
    },
    runtimeCustodyAcquireOperation:
      moon.strategyRemoteRuntimeCustodyAcquireOperation,
    runtimeCustodySettleOperation:
      moon.strategyRemoteRuntimeCustodySettleOperation,
    runtimeCustodyOperationSettled:
      moon.strategyRemoteRuntimeCustodyOperationSettled,
    runtimeCustodyOperationAcquired:
      moon.strategyRemoteRuntimeCustodyOperationAcquired,
    runtimeCustodyAcquireOutput:
      moon.strategyRemoteRuntimeCustodyAcquireOutput,
    runtimeCustodyReleaseOutput:
      moon.strategyRemoteRuntimeCustodyReleaseOutput,
    runtimeCustodyOutputReleased:
      moon.strategyRemoteRuntimeCustodyOutputReleased,
    runtimeCustodyOutputAcquired:
      moon.strategyRemoteRuntimeCustodyOutputAcquired,
    runtimeCustodyAcquireHolding:
      moon.strategyRemoteRuntimeCustodyAcquireHolding,
    runtimeCustodyReleaseHolding:
      moon.strategyRemoteRuntimeCustodyReleaseHolding,
    runtimeCustodyHoldingReleased:
      moon.strategyRemoteRuntimeCustodyHoldingReleased,
    runtimeCustodyHoldingAcquired:
      moon.strategyRemoteRuntimeCustodyHoldingAcquired,
    runtimeCustodyAcquireBundle:
      moon.strategyRemoteRuntimeCustodyAcquireBundle,
    runtimeCustodyReleaseBundle:
      moon.strategyRemoteRuntimeCustodyReleaseBundle,
    runtimeCustodyBundleReleased:
      moon.strategyRemoteRuntimeCustodyBundleReleased,
    runtimeCustodyBundleAcquired:
      moon.strategyRemoteRuntimeCustodyBundleAcquired,
    runtimeCustodyRecordFailure:
      moon.strategyRemoteRuntimeCustodyRecordFailure,
    runtimeCustodyConfirmStop:
      moon.strategyRemoteRuntimeCustodyConfirmStop,
    runtimeCustodyStopPending:
      moon.strategyRemoteRuntimeCustodyStopPending,
    runtimeCustodyResourcesReclaimed:
      moon.strategyRemoteRuntimeCustodyResourcesReclaimed,
    runtimeSuccessAction: (record: unknown, custody: unknown) => checked(
      moon.strategyRemoteRuntimeSuccessAction(record, custody),
    ) as number,
    prepareRuntimeFailure: (value: unknown, cancelled: boolean, stopConfirmed: boolean) => checked(
      moon.strategyRemoteRuntimeFailurePlan(
        value,
        cancelled,
        stopConfirmed,
      ),
    ),
    prepareOwnedRuntimeFailure: (value: unknown, custody: unknown) => checked(
      moon.strategyRemoteRuntimeOwnedFailurePlan(value, custody),
    ),
    prepareRuntimeCleanup: (
      value: unknown,
      cancelled: boolean,
      stopConfirmed: boolean,
      resourcesReclaimed: boolean,
    ) => checked(
      moon.strategyRemoteRuntimeCleanupPlan(
        value,
        cancelled,
        stopConfirmed,
        resourcesReclaimed,
      ),
    ),
    prepareOwnedRuntimeCleanup: (value: unknown, custody: unknown) => checked(
      moon.strategyRemoteRuntimeOwnedCleanupPlan(value, custody),
    ),
    prepareRuntimeReclaimUnknown: (value: unknown) => checked(
      moon.strategyRemoteRuntimeReclaimUnknownPlan(value),
    ),
    runtimeStepAction: moon.strategyRemoteRuntimeStepAction,
    runtimeStepTransition: (value: unknown) => checked(
      moon.strategyRemoteRuntimeStepTransition(value),
    ),
    prepareUnknown: (value: unknown) => checked(
      moon.strategyRemotePrepareUnknown(value),
    ),
    prepareRelease: (value: unknown) => checked(
      moon.strategyRemotePrepareRelease(value),
    ),
    prepareReleased: (value: unknown) => checked(
      moon.strategyRemotePrepareReleased(value),
    ),
    prepareLossRecovery: (value: unknown) => checked(
      moon.strategyRemotePrepareLossRecovery(value),
    ),
    prepareForceLoss: (journal: unknown, value: unknown, authorized: boolean) => checked(
      moon.strategyRemotePrepareForceLoss(journal, value, authorized),
    ),
    forceLossProjection: moon.strategyRemoteForceLossProjection,
    forceLossKey: moon.strategyRemoteForceLossKey,
    commitForceLoss: (value: unknown, durable: boolean) => checked(
      moon.strategyRemoteForceLossCommit(value, durable),
    ) as undefined,
    prepareRestart: (journal: unknown, replacement: unknown) => checked(
      moon.strategyRemotePrepareRestart(journal, replacement),
    ),
    restartCount: moon.strategyRemoteRestartCount,
    restartAt: (restart: unknown, index: number) => checked(
      moon.strategyRemoteRestartAt(restart, index),
    ),
    restartMetadata: moon.strategyRemoteRestartMetadata,
    commitRestart: (restart: unknown, durable: boolean) => checked(
      moon.strategyRemoteRestartCommit(restart, durable),
    ) as number,
    transitionProjection: moon.strategyRemoteTransitionProjection,
    transitionKey: moon.strategyRemoteTransitionKey,
    commitTransition: (value: unknown, durable: boolean) => checked(
      moon.strategyRemoteTransitionCommit(value, durable),
    ) as undefined,
    status: moon.strategyRemoteRecordStatus,
    revision: moon.strategyRemoteRecordRevision,
    restore(record: unknown, state: unknown) {
      if (!Array.isArray(state) || state.length !== 9) {
        throw new TypeError('Invalid remote dispatch state');
      }
      return checked(moon.strategyRemoteRecordRestore(record, ...state as Tail<Parameters<CommonSiteBindings['strategyRemoteRecordRestore']>>));
    },
    admitDurableRecordJson: (body: string) => checked(moon.strategyRemoteDurableRecordAdmitJson(body)),
    restoreDurableRecord: (journal: unknown, durable: unknown) => checked(
      moon.strategyRemoteDurableRecordRestore(journal, durable)),
    recordDurableJson: (record: unknown) => checked(moon.strategyRemoteRecordDurableJson(record)) as string,
    admissionDurableJson: (admission: unknown) => checked(moon.strategyRemoteAdmissionDurableJson(admission)) as string,
    transitionDurableJson: (transition: unknown) => checked(moon.strategyRemoteTransitionDurableJson(transition)) as string,
    transitionExpectedRevision: moon.strategyRemoteTransitionExpectedRevision,
    durableRecordJson: moon.strategyRemoteDurableRecordJson,
    durableRecordRevision: moon.strategyRemoteDurableRecordRevision,
    durableRecordKey: moon.strategyRemoteDurableRecordKey,
    durableRecordIdentity: moon.strategyRemoteDurableRecordIdentity,
    restoreHistorical: (journal: unknown, request: unknown) => checked(
      moon.strategyRemoteHistoricalRestore(journal, request),
    ),
  });
  control = site;
  return site;
}
