// Fixture process ownership only. Product Hosts retain their normal policies.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile, realpath, stat} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {types as nodeTypes} from 'node:util';
import {Worker, isMainThread, parentPort, workerData} from 'node:worker_threads';
import type {ChildProcess} from 'node:child_process';
import type {Debugger, Session} from 'node:inspector';
import type {MessagePort} from 'node:worker_threads';

type FixtureTransport = 'local' | 'remote' | 'tail';
type DiagnosticEvent = {event: string; code?: string; primaryCode?: string; codeOmitted?: true;
  issueTag?: number; nestedIssueTag?: number};
type HostDiagnostics = Readonly<{bestEffort: true; correlated: false; available: boolean; unavailable: boolean;
  truncated: boolean; records: readonly Readonly<DiagnosticEvent>[]}>;
type FailureData = {edge: string; type: string; code?: string; codeOmitted?: true; codeType?: string};
type FailureEdge = [edge: string, value: unknown, depth: number, accessor?: boolean];
type DiagnosticBoundary = 'original-catch' | 'local-500' | 'local-submission-500' | 'http-500';
type Observation = {available: boolean; sourceSha256?: string; boundary?: DiagnosticBoundary;
  zeroBasedLine?: number; originalCauseTypes?: readonly FailureData[][];
  unavailableReason?: 'original-caller-unavailable'};
type ObserverOptions = {sourceURL?: URL; enabled?: boolean; boundary?: DiagnosticBoundary;
  report?: (observation: Observation) => void};
type BoundaryFrame = {frame: number; caller?: string; condition?: string;
  operationFrame?: number; operationCaller?: string};
type OriginalBoundary = BoundaryFrame & {anchor: string; count: number; index: number};
type ObserverWorkerData = BoundaryFrame & {kind: 'packed-submission-cause'; url: string;
  sha256: string; lineNumber: number};
type ObserverMessage = {kind: 'ready' | 'loaded'} | {kind: 'primary'; types: FailureData[]} |
  {kind: 'unavailable'; reason?: 'original-caller-unavailable'};
type InspectorOutputs = {
  'Debugger.getScriptSource': Debugger.GetScriptSourceReturnType;
  'Debugger.evaluateOnCallFrame': Debugger.EvaluateOnCallFrameReturnType;
  'Debugger.setBreakpointByUrl': Debugger.SetBreakpointByUrlReturnType;
};
type InspectorOutput<Method extends string> = Method extends keyof InspectorOutputs ? InspectorOutputs[Method] : unknown;
type ObserverPorts = {session: Session; parentPort: MessagePort; workerData: ObserverWorkerData};
type TransportWorker = Readonly<{check(): void; release(): void}>;
type WorkerCommand = {name: string; command?: string; args: readonly string[]; cwd?: string; environment?: NodeJS.ProcessEnv};
type WorkerReceipt = {name: string; startedAt: string; endedAt: string | null; pid: number | null;
  status: number | null; signal: NodeJS.Signals | null; error: string | null; terminal: boolean};
type Stream = 'stdout' | 'stderr';
type TransportOptions = {deadline: number; timeoutMs?: number; outputLimit?: number;
  env?: NodeJS.ProcessEnv; forward?: (name: Stream, bytes: Buffer) => unknown};

export const acceptanceTimeoutMs = 900_000;
// A finite enclosing fixture envelope; product Run and cleanup budgets are separate.
const maximumAcceptanceTimeoutMs = 1_800_000;
// Select the enclosing fixture limit before any package or product work.
export function selectAcceptanceTimeout(environment: NodeJS.ProcessEnv = process.env) {
  const timeoutMs = Number(environment.ACTQL_TEST_QUERY_TIMEOUT_MS ?? acceptanceTimeoutMs);
  assert.ok(Number.isSafeInteger(timeoutMs) && timeoutMs > 0 &&
    timeoutMs <= maximumAcceptanceTimeoutMs);
  return timeoutMs;
}

export const acceptanceOutputBytes = 8 * 1024 * 1024;
export const transportModes = Object.freeze(['local', 'remote']);
// Fixed production factory categories only; no thrown string or prefix can extend this set.
const originalFailureCodes = Object.freeze([
  'ACTQL_E_DELEGATION_UNAVAILABLE', 'CheckpointSignerUnavailable', 'ClientAuthenticationDenied',
  'ClientCancellationDenied', 'ClientCancellationModelFenceUnavailable', 'ClientCancellationModelFenceUnconfirmed',
  'ClientCancellationRevisionConflict', 'ClientCancellationUnknown', 'ClientConnectionDenied',
  'ClientHostClosing', 'ClientHostFailure',
  'ClientKeyedLookupActivationUnknown', 'ClientKeyedLookupActivationUnresolved',
  'ClientKeyedLookupPageUnknown', 'ClientKeyedLookupPageUnresolved',
  'ClientObservationCommitOutcomeUnknown',
  'ClientObservationConnectionUnusable', 'ClientObservationRollbackFailed', 'ClientOperationUnavailable',
  'ClientParametersInvalid', 'ClientParametersTooLarge', 'ClientPreparedSubmissionUnavailable',
  'ClientProgramAnalysisLimit', 'ClientProgramImplementationLimit', 'ClientProgramInvalidInput',
  'ClientProgramNeedsInputs', 'ClientProgramPreparationFailure', 'ClientProgramRejected',
  'ClientProgramUnsupported', 'ClientRequestCancellationDenied', 'ClientRequestDefinitionMissing',
  'ClientRequestInferEvidenceMismatch', 'ClientRequestInferEvidenceMissing', 'ClientRequestIntentConflict',
  'ClientRequestJournalCapacity', 'ClientRequestJournalClosed', 'ClientRequestJournalCommitOutcomeUnknown',
  'ClientRequestJournalConnectionUnusable', 'ClientRequestJournalCorrupt', 'ClientRequestJournalDatabaseUnavailable',
  'ClientRequestJournalFacilityUnavailable', 'ClientRequestJournalInspectionCleanupPending', 'ClientRequestJournalInspectionUnavailable',
  'ClientRequestJournalRollbackFailed', 'ClientRequestJournalSqlCleanupPending', 'ClientRequestJournalSqlUnavailable',
  'ClientRequestJournalTemporaryUnavailable', 'ClientRequestJournalWalUnavailable', 'ClientRequestLookupDenied',
  'ClientRequestLookupUnknown', 'ClientRequestNotFound', 'ClientRequestOwnerMismatch',
  'ClientRequestPlanEvidenceMismatch', 'ClientRequestPlanEvidenceMissing', 'ClientRequestResultInventoryMismatch',
  'ClientRequestRunAlreadyAssigned', 'ClientRequestSourceInventoryMismatch', 'ClientRequestSubmissionCustodyLost',
  'ClientRequestSubmittedIntentBindingMissing', 'ClientRequestSubmittedIntentMismatch', 'ClientRequestTooLarge',
  'ClientRunCancellationDenied', 'ClientRunCancellationRequested', 'ClientRunFailureObservationDenied',
  'ClientRunPhysicalStartDenied', 'ClientRunReconciliationConflict', 'ClientRunReconciliationDenied',
  'ClientRunStartDenied', 'ClientRunStopObservationChanged', 'ClientRunStopObservationDenied',
  'ClientSourceOperationAlreadyEntered', 'ClientSourceOperationBindingUnavailable', 'ClientSourceOperationCapacity',
  'ClientSourceOperationCorrupt', 'ClientSourceOperationOriginalChanged', 'ClientSourceOperationUnavailable',
  'ClientSourceOperationUnresolved', 'ClientSubmissionEpochClockInvalid', 'ClientSubmissionEpochCustodyLost',
  'ClientSubmissionEpochExpired', 'ClientSubmissionEpochNotYetValid', 'ClientSubmissionEpochScopeMismatch',
  'ClientSubmissionEpochUnauthorized', 'ClientSubmissionEpochUnverifiable', 'ClientSubmissionIdentityMismatch',
  'ClientSubmissionNameCapacity', 'ClientSubmissionNameCustodyLost', 'ClientSubmissionNameReferenceUsed',
  'ClientSubmissionNameUnresolvable', 'ClientSubmissionReferenceRequired', 'ClientSubmissionRestartCapacity',
  'ClientSubmissionRestartConflict', 'ClientSubmissionRestartCorrupt', 'ClientSubmissionRestartCustodyLost',
  'ClientSubmissionRestartOriginalResolvable', 'ClientSubmissionRestartRequiresReconciliation', 'ClientSubmissionUnresolvable',
  'ClientSubmittedIntentCapacity', 'ClientSubmittedIntentConflict', 'ClientSubmittedIntentCorrupt',
  'ClientSubmittedIntentCustodyLost', 'ClientSubmittedIntentNotRetirable', 'ClientSubmittedIntentRetirementConflict',
  'ContinuationDirectoryCleanupPending', 'ContinuationDirectoryEntriesLimit', 'ContinuationDirectoryUnavailable',
  'ContinuationDirectoryWireLimit', 'ContinuationLedgerEntriesLimit', 'ContinuationMetadataUnavailable',
  'DeclaredFileInstallationClosed', 'DeclaredFileInstallationUnavailable', 'EACCES',
  'EBADF', 'EBUSY', 'EEXIST',
  'EIO', 'EISDIR', 'EMFILE',
  'ENOENT', 'ENOMEM', 'ENOSPC',
  'ENOTDIR', 'EPERM', 'ERR_BUFFER_TOO_LARGE',
  'ERR_INVALID_ARG_TYPE', 'ERR_INVALID_STATE', 'ERR_OUT_OF_RANGE',
  'ERR_SQLITE_ERROR', 'EffectCaptureResourceCleanupPending', 'EffectRecoveryOriginalSelectionUnavailable',
  'EffectRecoveryRequestMismatch', 'EffectRecoveryResourcesUnavailable', 'EffectRetirementResourcesUnavailable',
  'ExecutionAuthorizationDenied', 'ForeignClientKeyedLookupOriginal', 'ForeignClientKeyedLookupPage',
  'ForeignClientLocalExecutionOwner', 'ForeignClientRequestJournalCustody',
  'ForeignClientSourceOperation', 'ForeignEffectCaptureResources', 'ForeignInstalledComputePreparation',
  'ForeignInstalledComputeRun', 'ForeignInstalledContentRun', 'ForeignInstalledCredentialOperationSite',
  'ForeignInstalledEffectManagedRun', 'ForeignInstalledHostPreparation', 'ForeignInstalledLocalFileEffectRun',
  'ForeignInstalledManagedRunContracts', 'ForeignInstalledMockEffectRun', 'ForeignInstalledMockModelRun',
  'ForeignInstalledMockPreparation', 'ForeignInstalledMockSourceBinding', 'ForeignInstalledModelPreparation',
  'ForeignInstalledModelRecovery', 'ForeignInstalledModelRecoveryScope', 'ForeignInstalledModelSourceCoordinates',
  'ForeignInstalledProjectOriginal', 'ForeignInstalledProjectProfile', 'ForeignInstalledProjectSourcePreparation',
  'ForeignInstalledSourceConstruction', 'ForeignInstalledSourceInitialization', 'ForeignInstalledSourcePreparation',
  'ForeignInstalledSourceProducer', 'ForeignInstalledSourceReaderDemand', 'ForeignOriginalKeyedRawResponse',
  'ForeignRequestOriginal',
  'ForeignRowSourceCredentialAcquisitionAuthorization', 'ForeignRowSourceCredentialReadChild', 'ForeignRowSourceCredentialResourceChild',
  'ForeignRowSourceMetadataChild', 'ForeignRunStateObservation', 'HostEffectResultPublicationUnavailable',
  'HostEffectRunPreparationUnavailable', 'HostJournalInstallationCleanupPending', 'HostJournalInstallationUnavailable',
  'HostJournalPreparationCleanupPending', 'HostJournalPreparationUnavailable', 'HostResultPublicationCleanupPending',
  'HostResultPublicationPurposeUnavailable', 'HostResultPublicationUnavailable', 'InferTrustedRuntimeScopeUnavailable',
  'InferTrustedRuntimeViewUnavailable', 'InferTrustedStoreClosed', 'InstallationMetadataJournalCleanupUnavailable',
  'InstallationMetadataJournalCleanupUnconfirmed', 'InstalledComputePreparationCleanupPending', 'InstalledComputeRunLimit',
  'InstalledContentCaptureBeforeSend', 'InstalledContentPhysicalCleanupPending', 'InstalledContentRunCleanupPending',
  'InstalledContentRunPreparationUnavailable', 'InstalledContentRunPreparationUnsupported', 'InstalledEffectControlConstructionCleanupPending',
  'InstalledEffectInstallationChanged', 'InstalledEffectOriginalSelectionChanged', 'InstalledEffectPlanSelectionPending',
  'InstalledEffectPlanUnavailable', 'InstalledEffectRequestPreparationUnavailable', 'InstalledEffectRunCleanupPending',
  'InstalledFileLocatorAfterSend', 'InstalledFileLocatorUnavailable', 'InstalledHostAssetCleanupPending',
  'InstalledHostAssetLimit', 'InstalledHostAssetUnavailable', 'InstalledHostJournalCleanupPending',
  'InstalledHostPreparationChanged', 'InstalledHostPreparationCleanupPending', 'InstalledHostPreparationLimit',
  'InstalledHostPublicationOwnershipCleanupPending', 'InstalledInferAuthorityUnavailable', 'InstalledInferDispatchNotConnected',
  'InstalledKeyedEffectDagRequiresRunOwner', 'InstalledKeyedHostOriginalRunUnavailable', 'InstalledKeyedHostPreparation',
  'InstalledKeyedJoinPreparation', 'InstalledKeyedLookupLimits', 'InstalledKeyedReadApprovalMismatch',
  'InstalledKeyedRequestFailed', 'InstalledKeyedRequestIdentityUnavailable', 'InstalledKeyedSourceReadUnavailable',
  'InstalledListingSourceUnavailable', 'InstalledLocalFileEffectResourcesUnavailable', 'InstalledLocalFileEffectRunLimit',
  'InstalledManagedDomainPreparationRequired', 'InstalledManagedSourceUnavailable', 'InstalledMockCatalogueUnavailable',
  'InstalledMockEffectProfileConflict', 'InstalledMockEffectResourcesUnavailable', 'InstalledMockEffectRunLimit',
  'InstalledMockModelCleanupPending', 'InstalledMockModelOperationalAdmissionUnavailable', 'InstalledMockModelOriginalCompositionUnavailable',
  'InstalledMockModelOriginalUnavailable', 'InstalledMockModelRuntimeUnavailable', 'InstalledMockPreparationUnavailable',
  'InstalledMockSourceChanged', 'InstalledMockSourceCleanupPending', 'InstalledMockSourceInputLimit',
  'InstalledMockSourceUnavailable', 'InstalledModelCleanupPending', 'InstalledModelGroupPreparationUnavailable',
  'InstalledModelOperationalAdmissionUnavailable', 'InstalledModelPlanSelectionPending', 'InstalledModelQuantityCapacityUnavailable',
  'InstalledModelRecoveryCapacityUnavailable', 'InstalledModelRecoveryPreparationUnavailable', 'InstalledModelRecoveryRuntimeUnavailable',
  'InstalledModelSourcePreparationUnavailable', 'InstalledProjectProfileUnavailable', 'InstalledProjectSourceCompositionUnavailable',
  'InstalledProjectSourcePreparationUnavailable', 'InstalledProviderSourceLedgerRequired', 'InstalledProviderSourceUnavailable',
  'InstalledRowSiteCurrentCheckNotSynchronous', 'InstalledSecretMaterialCleanupPending', 'InstalledSecretMaterialCleanupUnavailable',
  'InstalledSecretMaterialClosed', 'InstalledSourceCapacityUnavailable', 'InstalledSourceCleanupPending',
  'InstalledSourceClosed', 'InstalledSourceEvidenceFactsUnavailable', 'InstalledSourceInitializationCleanupPending',
  'InstalledSourceInitializationClosed', 'InstalledSourceInitializationMethodUnavailable', 'InstalledSourceInitializationNotSynchronous',
  'InstalledSourceInitializationPending', 'InstalledSourceInitializationRuntimeUnavailable', 'InstalledSourceInitializationUnavailable',
  'InstalledSourcePlanConstructorUnavailable', 'InstalledSourcePlanUnavailable', 'InstalledSourcePreparationChanged',
  'InstalledSourcePreparationCleanupPending', 'InstalledSourcePreparationMismatch', 'InstalledSourceProducerLimit',
  'InstalledSourceProgramMismatch', 'InstalledSourcePropertyOccurrenceLimit', 'InstalledSourcePropertyUseLimit',
  'InstalledSourcePublicationCollision', 'InstalledSourceQueryUseLimit', 'InstalledSourceReadApprovalMismatch',
  'InstalledSourceReadChildOriginalUnavailable', 'InstalledSourceReadChildUseLimit', 'InstalledSourceReadUnavailable',
  'InstalledSourceReaderCleanupPending', 'InstalledSourceReaderCleanupUnavailable', 'InstalledSourceReaderNotCurrent',
  'InstalledSourceRecoveryPreparationUnavailable', 'InstalledSourceRunCleanupPending', 'InstalledWholeSourceRequestPreparationRequired',
  'InvalidAcquisitionOccurrence', 'InvalidCanonicalNumber', 'InvalidCanonicalText',
  'InvalidCanonicalValue', 'InvalidClientCancellationAttempt', 'InvalidClientCancellationLookup',
  'InvalidClientCancellationOperation', 'InvalidClientHostAdmission', 'InvalidClientHostAttemptLookup',
  'InvalidClientHostCancellation', 'InvalidClientHostCancellationLookup', 'InvalidClientHostCheckOutcome',
  'InvalidClientHostCheckpointPage', 'InvalidClientHostCheckpointReview', 'InvalidClientHostLookupResponse',
  'InvalidClientHostOwnerObservations', 'InvalidClientHostPlanView', 'InvalidClientHostPreparation',
  'InvalidClientHostProfile', 'InvalidClientHostRequestCancellation', 'InvalidClientHostResolveReply',
  'InvalidClientHostResourceReply', 'InvalidClientHostResultDescription', 'InvalidClientHostRunPlanView',
  'InvalidClientHostRunState', 'InvalidClientHostRunView', 'InvalidClientHostSubmissionLookup',
  'InvalidClientHostSubmissionOutcome', 'InvalidClientInferRunOriginal', 'InvalidClientProgramPreparationInstallation',
  'InvalidClientRequest', 'InvalidClientRequestAdmission', 'InvalidClientRequestIdentity',
  'InvalidClientRequestJournalConfiguration', 'InvalidClientRequestJournalControl', 'InvalidClientRequestLookup',
  'InvalidClientRunAdmissionEvidence', 'InvalidClientRunCancellation', 'InvalidClientRunDefinition',
  'InvalidClientRunFailureObservation', 'InvalidClientRunLookup', 'InvalidClientRunPhysicalStart',
  'InvalidClientRunPlanOriginal', 'InvalidClientRunReconciliation', 'InvalidClientRunStart',
  'InvalidClientRunStopObservation', 'InvalidClientSourceInventory', 'InvalidClientSourceOperationLimits',
  'InvalidClientSourceOperationOccurrence', 'InvalidClientSubmissionAttempt', 'InvalidClientSubmissionEpochOperation',
  'InvalidClientSubmissionInstallation', 'InvalidClientSubmissionName', 'InvalidClientSubmissionNonce',
  'InvalidClientSubmissionOperation', 'InvalidClientSubmissionRestart', 'InvalidClientSubmittedIntent',
  'InvalidClientSubmittedIntentOutcome', 'InvalidClientSubmittedIntentRetirement', 'InvalidConnectionOptions',
  'InvalidContinuationDirectoryBounds', 'InvalidContinuationDirectoryName', 'InvalidContinuationLedger',
  'InvalidContinuationMetadataBounds', 'InvalidHostRuntimeResult', 'InvalidInstallationMetadataCurrentFence',
  'InvalidInstallationMetadataJournal', 'InvalidInstalledContentCapture', 'InvalidInstalledEffectMappings',
  'InvalidInstalledKeyedTransportLimits', 'InvalidInstalledListingReportCapacity', 'InvalidInstalledRowSite',
  'InvalidInstalledRowSourceLimits', 'InvalidInstalledRowSourceOperations', 'InvalidInstalledSecretMaterial',
  'InvalidInstalledSecretMaterialConstructor', 'InvalidInstalledSourceAccess', 'InvalidInstalledSourceAcquisitionPreparer',
  'InvalidInstalledSourcePageCharge', 'InvalidInstalledSourcePageLimits', 'InvalidInstalledSourcePageWire',
  'InvalidInstalledSourcePreparation', 'InvalidInstalledSourcePublication', 'InvalidInstalledSourceReadChild',
  'InvalidInstalledSourceReadIdentity', 'InvalidInstalledSourceReadPreparation', 'InvalidInstalledSourceReader',
  'InvalidInstalledSourceReaderPageDemand', 'InvalidJournalDirectoryInspectionConfiguration', 'InvalidKeyedRequestObservation',
  'InvalidKeyedResponseObservation', 'InvalidKeyedVerificationObservation', 'InvalidLocalAccountAuthorization',
  'InvalidLocalValuesRowLimit', 'InvalidOpenOptions', 'InvalidOriginalCheckObservation',
  'InvalidRemoteCredentialCurrentFence', 'InvalidRowSourceAuthorizationInstallation', 'InvalidRowSourceCheckEnvironmentBase',
  'InvalidRowSourceCredentialAcquisitionCurrent', 'InvalidRowSourceCredentialAcquisitionJournal', 'InvalidRowSourceCredentialAcquisitionLimits',
  'InvalidRowSourceCredentialAcquisitionProfile', 'InvalidRowSourceCredentialAcquisitionRequest', 'InvalidRowSourceCredentialSite',
  'InvalidRowSourceInstallationMetadata', 'InvalidRowSourceSecretPresentation', 'InvalidSqliteSnapshotInspectionConfiguration',
  'InvalidWaitCondition', 'InvalidWaitRevision', 'KeyedLookupDurationExceeded',
  'LegacyClientRequestJournalFormat', 'LocalAccountAdoptedStateMissing', 'LocalAccountConfigurationRejected',
  'LocalAccountFirstInitializationUnavailable', 'LocalAccountInitializationChanged', 'LocalAccountInitializationConflict',
  'LocalAccountInitializationExposed', 'LocalAccountInitializationInvalid', 'LocalAccountInitializationLimit',
  'LocalAccountProfileUnavailable', 'LocalMockAdoptedStateMissing', 'LocalMockInitializationAlreadyPending',
  'LocalMockInitializationCleanupPending', 'LocalMockInitializationConflict', 'LocalMockInitializationConsentRequired',
  'LocalMockInitializationExposed', 'LocalMockInitializationInvalid', 'LocalMockInstallationChanged',
  'LocalSigningCaptureCleanupPending', 'LocalSigningOriginalConflict', 'ModelCancellationJournalUnavailable',
  'MoonBitHostFailure', 'NodeInitialControlInputUnavailable', 'NodeInitialControlOriginalChanged',
  'NodeLocalPreparationAdmissionUnavailable', 'NodeLocalPreparationCleanupPending', 'NodeManagedComputeIntentUnavailable',
  'NodeManagedRunAdmissionUnavailable', 'NodeManagedRunCompilationUnavailable', 'NodeManagedRunPlanUnavailable',
  'NodeManagedRunRuntimeUnavailable', 'NodeSourceManagedInputUnavailable', 'NodeSourceManagedIntentUnavailable',
  'OriginalKeyedLookupAlreadyActivated', 'OriginalKeyedLookupPublicationUnavailable',
  'PreparationCapacityExceeded', 'PrivateEvidenceFirstInitializationUnavailable', 'RequestedEffectStopUnavailable',
  'ResultAccessDenied', 'ResultReadCleanupPending',
  'RowSourceAuthorizationCleanupPending', 'RowSourceAuthorizationPurposeUnavailable',
  'RowSourceCredentialAcquisitionAuthorizationConsumed', 'RowSourceCredentialAcquisitionCleanupPending', 'RowSourceCredentialAcquisitionLimit',
  'RowSourceCredentialAcquisitionUnavailable', 'RowSourceCredentialJournalCleanupUnconfirmed', 'RowSourceEffectTargetReadApprovalNotAdmitted',
  'RowSourceGrantNotAuthorized', 'RowSourceInstallationMetadataSiteChanged', 'RowSourceMetadataCleanupPending',
  'RowSourceMetadataGrantNotAuthorized', 'RowSourceMetadataGrantUnavailable', 'RowSourceMetadataOccurrenceAlreadyPrepared',
  'RowSourceMetadataOperationLimit', 'RowSourceMetadataOperationNotRegistered', 'RowSourceMetadataSiteAlreadyAttached',
  'RowSourceMetadataTargetChanged', 'RowSourceReadApprovalNotAdmitted', 'RowSourceSiteClosed',
  'RunHostAdmissionRejected', 'RunHostCompilationRejected', 'RunHostContentCaptureRejected',
  'RunHostContentGenerationRecoveryRejected', 'RunHostContentGenerationRejected', 'RunHostContentInferInputRejected',
  'RunHostContentInferObservationRejected', 'RunHostContentInferPlanRejected', 'RunHostContentInputIdentityRejected',
  'RunHostContentInvocationRejected', 'RunHostContentPlanRejected', 'RunHostEffectContentAdmissionRejected',
  'RunHostEffectContentCaptureRejected', 'RunHostInferMaterialsRejected', 'RunHostInspectRejected',
  'RunHostInvocationRejected', 'RunHostOriginalMapRejected', 'RunHostOriginalPlanRejected',
  'RunHostResultPolicyRejected', 'RunHostResultSelectionRejected', 'RunHostSourceFreeAdmissionRejected',
  'RunHostSourceFreeDefinitionRejected', 'RunHostStaticPlanRejected', 'RunHostTaskCompilationRejected',
  'RunHostTaskDefinitionRejected', 'RunHostTaskInvocationRejected', 'RunStateAccessDenied',
  'RunStateObservationChanged', 'SourceManagedInstallationCleanupPending', 'SourceManagedPreparationUnavailable',
  'SourceManagedSynchronousProtocolChanged', 'SqliteInspectionTemporaryUnavailable', 'SqliteJournalInitializationCleanupPending',
  'SqliteSchemaPreparationUnavailable', 'StaleClientProgramErrorProjection', 'SubmissionAttemptRejected',
  'UndeclaredResponseHeader', 'UnknownClientOperation', 'UnknownClientRequestJournalFormat',
  'WaitAborted', 'WaitTimeout',
]);
let currentWorker: TransportWorker | undefined;
export function sourceFixturePaths(mode: FixtureTransport | undefined, profile: string, directory = process.cwd()) {
  assert.ok(mode === undefined || ['local', 'remote', 'tail'].includes(mode));
  const profileSuffix = profile === 'standard' ? '' : `-${profile}`;
  const transportSuffix = mode === 'remote' || mode === 'tail' ? `-${mode}` : '';
  return Object.freeze({
    database: resolve(directory, `records${profileSuffix}${transportSuffix}.duckdb`),
    sourceProfilePath: resolve(directory, `source-profile${profileSuffix}${transportSuffix}.json`),
  });
}

export function requireCompleteInventory(expected: readonly string[], completed: readonly string[]) {
  assert.ok(Array.isArray(expected) && Array.isArray(completed));
  assert.ok(expected.every(value => typeof value === 'string'));
  assert.equal(new Set(expected).size, expected.length, 'duplicate authored case');
  assert.equal(new Set(completed).size, completed.length, 'duplicate completed case');
  assert.deepEqual(completed, expected, 'missing, extra or reordered case');
}

// Recent optional Host diagnostics, not a correlated primary or a no-failure
// claim. Keep only copied public codes/numeric tags, never the original detail.
export function createPackedHostFailureDiagnostics(report: (value: HostDiagnostics) => void = value => {
  process.stderr.write(`Packed Host failure diagnostics: ${JSON.stringify(value)}\n`);
}) {
  const records: Readonly<DiagnosticEvent>[] = [];
  let unavailable = false, truncated = false;
  const own = (value: unknown, key: string): unknown => {
    if (value === null || !['object', 'function'].includes(typeof value)) return undefined;
    if (nodeTypes.isProxy(value)) { unavailable = true; return undefined; }
    const field = Object.getOwnPropertyDescriptor(value as object, key);
    if (field !== undefined && !Object.hasOwn(field, 'value')) unavailable = true;
    return field !== undefined && Object.hasOwn(field, 'value') ? field.value : undefined;
  };
  const numericTag = (value: unknown): number | undefined => {
    let owner = value;
    // MoonBit puts the closed variant tag on its prototype, not necessarily
    // the instance. Inspect DATA only, with at most two prototype hops.
    for (let hops = 0; hops <= 2; hops++) {
      if (owner === null || !['object', 'function'].includes(typeof owner)) return undefined;
      if (nodeTypes.isProxy(owner)) { unavailable = true; return undefined; }
      const field = Object.getOwnPropertyDescriptor(owner as object, '$tag');
      if (field !== undefined) {
        if (Object.hasOwn(field, 'value') && Number.isSafeInteger(field.value) &&
            field.value >= 0 && field.value <= 2147483647) return field.value;
        unavailable = true; return undefined;
      }
      if (hops < 2) owner = Object.getPrototypeOf(owner);
    }
    return undefined;
  };
  const capture = (event: string, detail: unknown) => {
    if (!['dispatch_failed', 'effect_start_failed', 'model_resume_failed', 'model_recovery_failed'].includes(event)) return;
    try {
      const record: DiagnosticEvent = {event};
      for (const key of ['code', 'primaryCode'] as const) {
        const code = own(detail, key);
        if (originalFailureCodes.includes(code as string)) record[key] = code as string;
        else if (code !== undefined) record.codeOmitted = true;
      }
      const cause = event === 'effect_start_failed' ? own(detail, 'cause') : undefined;
      const tags = [own(detail, 'issueTag') ?? numericTag(cause),
        own(detail, 'nestedIssueTag') ?? numericTag(own(cause, '_0'))];
      for (const [index, key] of (['issueTag', 'nestedIssueTag'] as const).entries()) {
        if (Number.isSafeInteger(tags[index]) && (tags[index] as number) >= 0 && (tags[index] as number) <= 2147483647) {
          record[key] = tags[index] as number;
        }
      }
      if (records.length === 8) { records.shift(); truncated = true; }
      records.push(Object.freeze(record));
    } catch { unavailable = true; }
  };
  return Object.freeze({
    authorization(original: unknown) {
      try {
        if (original !== undefined && (original === null || typeof original !== 'object' || nodeTypes.isProxy(original))) {
          unavailable = true; return original;
        }
        let observer: ((...args: unknown[]) => unknown) | undefined;
        for (let owner = original; owner != null; owner = Object.getPrototypeOf(owner)) {
          if (nodeTypes.isProxy(owner)) { unavailable = true; return original; }
          const field = Object.getOwnPropertyDescriptor(owner, 'observe');
          if (field === undefined) continue;
          if (!Object.hasOwn(field, 'value') || field.value !== undefined && typeof field.value !== 'function') {
            unavailable = true; return original;
          }
          observer = field.value; break;
        }
        const fields: PropertyDescriptorMap = Object.getOwnPropertyDescriptors(original ?? {});
        fields.observe = {...(fields.observe ?? {enumerable: true, configurable: true, writable: true}), value: function (this: unknown, ...args: [string, unknown, ...unknown[]]) {
          capture(args[0], args[1]);
          return observer === undefined ? undefined : Reflect.apply(observer, this, args);
        }};
        return Object.create(original === undefined ? Object.prototype : Object.getPrototypeOf(original), fields);
      } catch { unavailable = true; return original; }
    },
    report() {
      const value = Object.freeze({bestEffort: true, correlated: false,
        available: records.length > 0 && !unavailable, unavailable: unavailable || records.length === 0, truncated,
        records: Object.freeze([...records])});
      try { report(value); } catch { /* Diagnostics cannot replace the original failure. */ }
      return value;
    },
  });
}

// Pure diagnostic DATA only. Never format a reflection failure or read an
// accessor, message, stack, unrelated field or arbitrary enumerable inventory.
export function collectPackedFailureData(error: unknown) {
  try {
    const out: FailureData[] = [], queue: FailureEdge[] = [['original', error, 0]], seen = new Set<object>();
    while (queue.length && out.length < 32) {
      const [edge, value, depth, accessor] = queue.shift()!;
      if (accessor) {out.push({edge, type: 'Accessor'}); continue;}
      if (value === null) {out.push({edge, type: 'Null'}); continue;}
      const primitiveTypes = {undefined: 'Undefined', string: 'String', number: 'Number',
        boolean: 'Boolean', bigint: 'BigInt', symbol: 'Symbol', function: 'Function'};
      if (typeof value !== 'object') {out.push({edge, type: primitiveTypes[typeof value as keyof typeof primitiveTypes]}); continue;}
      if (seen.has(value)) continue;
      seen.add(value);
      const proto = Object.getPrototypeOf(value);
      const ctor = proto && Object.getOwnPropertyDescriptor(proto, 'constructor')?.value;
      const name = typeof ctor === 'function' ? Object.getOwnPropertyDescriptor(ctor, 'name')?.value : '';
      const type = ['Object', 'Array', 'Error', 'TypeError', 'RangeError', 'SyntaxError', 'ClientError', 'DOMException'].includes(name)
        ? name : typeof name === 'string' && /^_M[A-Za-z0-9_]{1,157}$/u.test(name) ? 'MoonBit' : 'Other';
      const row: FailureData = {edge, type}, code = Object.getOwnPropertyDescriptor(value, 'code');
      if (code) {
        if (Object.hasOwn(code, 'value') && originalFailureCodes.includes(code.value)) row.code = code.value;
        else {
          row.codeOmitted = true;
          row.codeType = !Object.hasOwn(code, 'value') ? 'Accessor' : code.value === undefined ? 'Undefined'
            : typeof code.value === 'string' ? 'String' : typeof code.value === 'number' ? 'Number' : 'Other';
        }
      }
      out.push(row);
      if (depth < 16) for (const key of ['cause', 'primaryFailure', '_0', '_1', '_2']) {
        const field = Object.getOwnPropertyDescriptor(value, key);
        if (field) queue.push([key, Object.hasOwn(field, 'value') ? field.value : undefined,
          depth + 1, !Object.hasOwn(field, 'value')]);
      }
    }
    return {available: true, originalCauseTypes: [out]};
  } catch {
    // Discard partial observations; the thrown object itself stays private.
    return {available: false, originalCauseTypes: []};
  }
}

// This is a test-only observer of the already installed original ingress. It
// captures only its selected original boundary; no runtime bytes are changed.
// Missing diagnostic evidence never replaces the original acceptance result.
export async function observePackedSubmissionCause({sourceURL, enabled = false, boundary = 'original-catch', report = value => {
  process.stderr.write(`Packed submission original cause: ${JSON.stringify(value)}\n`);
}}: ObserverOptions) {
  assert.equal(typeof enabled, 'boolean');
  // Inspector is an explicit diagnostic capability, never an ordinary product
  // acceptance prerequisite. Do not even read the target when unselected.
  if (!enabled) return Object.freeze({close: async () => {}});
  const observations: FailureData[][] = [];
  let worker: Worker | undefined, exited: Promise<number> | undefined, closing: Promise<void> | undefined,
    stopping: Promise<boolean> | undefined, ready: Promise<void> | undefined,
    unavailableReason: Observation['unavailableReason'], loaded = false, observationFailed = false;
  const emit = (value: Observation) => {try {report(value);} catch { /* Preserve the original test outcome. */ }};
  const stopObserver = () => stopping ??= (async () => {
    let stopped = false;
    try {
      worker!.postMessage({kind: 'close'});
      await Promise.race([exited, new Promise((_, reject) => {
        const timer = setTimeout(() => reject(new Error('DiagnosticCleanupUnavailable')), 3000);
        exited!.then(() => clearTimeout(timer));
      })]);
      stopped = true;
    } catch { /* Terminate only this observer, never the original Host. */ }
    if (!stopped) await worker!.terminate().catch(() => {});
    return stopped;
  })();
  const unavailable = () => Object.freeze({close: async () => {
    if (!closing) closing = Promise.resolve().then(() => emit({available: false}));
    await closing;
  }});
  try {
    assert.equal(sourceURL!.protocol, 'file:');
    assert.equal(sourceURL!.search + sourceURL!.hash, '');
    const path = await realpath(fileURLToPath(sourceURL!)), metadata = await stat(path);
    assert.ok(metadata.isFile() && metadata.size > 0 && metadata.size <= 128 * 1024);
    const bytes = await readFile(path), source = bytes.toString('utf8');
    assert.equal(bytes.length, metadata.size);
    const boundaries: Record<DiagnosticBoundary, OriginalBoundary> = {
      'original-catch': {anchor: 'throw publicFailure(error);', count: 2, index: 1, frame: 0},
      'local-500': {anchor: 'const error = new ClientError(code, {status});', count: 1, index: 0,
        frame: 1, caller: 'publicFailure', condition: 'status === 500'},
      'local-submission-500': {anchor: 'const error = new ClientError(code, {status});', count: 1, index: 0,
        frame: 1, caller: 'publicFailure', condition: 'status === 500',
        operationFrame: 2, operationCaller: 'perform'},
      'http-500': {anchor: "response.writeHead(status, {'content-type': 'application/json'});",
        count: 1, index: 0, frame: 0, condition: 'status === 500'},
    };
    assert.ok(Object.hasOwn(boundaries, boundary), 'Unknown diagnostic boundary');
    const selected = boundaries[boundary];
    const catches = source.split('\n').flatMap((line, index) =>
      line.trim() === selected.anchor ? [index] : []);
    assert.equal(catches.length, selected.count, 'Exact original ingress boundary required');
    const lineNumber = catches[selected.index];
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    worker = new Worker(new URL(import.meta.url), {execArgv: [], workerData: {
      kind: 'packed-submission-cause', url: pathToFileURL(path).href,
      sha256, lineNumber, frame: selected.frame, caller: selected.caller, condition: selected.condition,
      operationFrame: selected.operationFrame, operationCaller: selected.operationCaller}});
    exited = new Promise<number>(resolve => worker!.once('exit', resolve));
    ready = new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('DiagnosticStartupUnavailable')), 3000);
      worker!.on('error', error => {observationFailed = true; reject(error);});
      worker!.on('message', (value: ObserverMessage) => {
        if (value.kind === 'loaded') loaded = true;
        if (value.kind === 'primary') observations.push(value.types);
        if (value.kind === 'ready') {clearTimeout(timer); resolve();}
        if (value.kind === 'unavailable') {
          if (value.reason === 'original-caller-unavailable') unavailableReason = value.reason;
          observationFailed = true; clearTimeout(timer); reject(new Error('DiagnosticUnavailable'));
        }
      });
      exited!.then(() => {clearTimeout(timer); reject(new Error('DiagnosticExited'));});
    });
    await ready;
    return Object.freeze({close() {
      closing ??= (async () => {
        const stopped = await stopObserver();
        emit({available: loaded && stopped && !observationFailed, sourceSha256: sha256,
          boundary, zeroBasedLine: lineNumber, originalCauseTypes: observations,
          ...(unavailableReason === undefined ? {} : {unavailableReason})});
      })();
      return closing;
    }});
  } catch {
    if (worker !== undefined) await stopObserver();
    return unavailable();
  }
}

export async function runSubmissionCauseObserver({session, parentPort, workerData}: ObserverPorts) {
  session.connectToMainThread();
  const post = <Method extends string>(method: Method, params: object = {}) => new Promise<InspectorOutput<Method>>((resolve, reject) =>
    session.post(method, params, (error, value) => error ? reject(error) : resolve(value as InspectorOutput<Method>)));
  // Inspector callbacks alone do not keep a Worker alive during startup.
  const alive = setInterval(() => {}, 1000);
  const originals = new Set<string>();
  const pending = new Set<Promise<unknown>>();
  const sourceFlights = new Set<Promise<void>>();
  const flight = <Value,>(action: () => Value | PromiseLike<Value>) => {
    const task = Promise.resolve().then(action);
    pending.add(task);
    task.then(() => pending.delete(task), () => pending.delete(task));
    return task;
  };
  const drain = async () => {
    while (pending.size > 0) await Promise.allSettled([...pending]);
  };
  let breakpoint: string | undefined, closing: Promise<void> | undefined, captured = false, retiring = false, sourceRejected = false;
  // Emit only fixed categories and explicitly listed codes. Even a plausible
  // private code prefix or forged compiled constructor name is not evidence.
  // Keep reflection failures inside this expression. Sending their Error to
  // Inspector's exception formatter can execute private message/stack getters.
  const expression = `(()=>{const originalFailureCodes=${JSON.stringify(originalFailureCodes)};
const value=(${Function.prototype.toString.call(collectPackedFailureData)})(error);
return value.available?value.originalCauseTypes[0]:null;})()`;
  session.on('Debugger.scriptParsed', ({params}) => {
    if (retiring || params.url !== workerData.url) return;
    const validating = flight(async () => {
      try {
        const {scriptSource} = await post('Debugger.getScriptSource', {scriptId: params.scriptId});
        assert.equal(createHash('sha256').update(scriptSource).digest('hex'), workerData.sha256);
        originals.add(params.scriptId);
        parentPort.postMessage({kind: 'loaded'});
      } catch {sourceRejected = true; parentPort.postMessage({kind: 'unavailable'});}
    });
    sourceFlights.add(validating);
    validating.then(() => sourceFlights.delete(validating), () => sourceFlights.delete(validating));
  });
  session.on('Debugger.paused', ({params}) => {
    void flight(async () => {
      let retireBreakpoint = false;
      try {
        if (retiring) return;
        assert.ok(!captured && originals.has(params.callFrames[0].location.scriptId));
        const frame = params.callFrames[workerData.frame];
        if (!frame || !originals.has(frame.location.scriptId) ||
            workerData.caller !== undefined && frame.functionName !== workerData.caller) {
          retireBreakpoint = true;
          parentPort.postMessage({kind: 'unavailable', reason: 'original-caller-unavailable'});
          return;
        }
        if (workerData.operationFrame !== undefined) {
          const operationFrame = params.callFrames[workerData.operationFrame];
          if (!operationFrame || !originals.has(operationFrame.location.scriptId) ||
              operationFrame.functionName !== workerData.operationCaller) {
            retireBreakpoint = true;
            parentPort.postMessage({kind: 'unavailable', reason: 'original-caller-unavailable'});
            return;
          }
          // Read only the original lexical operation's closed boolean category.
          // Do not reclassify the error or inspect request data. Earlier Result
          // or status failures must not consume the submission's diagnostic slot.
          const selected = await post('Debugger.evaluateOnCallFrame', {
            callFrameId: operationFrame.callFrameId,
            expression: "operation === 'submit' || operation === 'submit-intent' || operation === 'submit-named-intent' || operation === 'restart-intent'",
            returnByValue: true, silent: true});
          assert.equal(selected.exceptionDetails, undefined);
          assert.equal(selected.result.type, 'boolean');
          if (!selected.result.value) return;
        }
        captured = true;
        retireBreakpoint = true;
        const {result, exceptionDetails} = await post('Debugger.evaluateOnCallFrame', {
          callFrameId: frame.callFrameId, expression,
          returnByValue: true, silent: true});
        assert.equal(exceptionDetails, undefined);
        assert(Array.isArray(result.value), 'Original failure inspection unavailable');
        parentPort.postMessage({kind: 'primary', types: result.value});
      } catch {retireBreakpoint = true; parentPort.postMessage({kind: 'unavailable'});}
      finally {
        if (retireBreakpoint) await post('Debugger.removeBreakpoint', {breakpointId: breakpoint}).catch(() => {});
        await post('Debugger.resume').catch(() => parentPort.postMessage({kind: 'unavailable'}));
      }
    });
  });
  parentPort.on('message', (value: {kind: string}) => {
    if (value.kind !== 'close') return;
    closing ??= (async () => {
      retiring = true;
      try {
        // The main thread can request close before the resume callback arrives.
        // Keep this same Session until all its original command flights settle,
        // including notifications delivered while disabling the debugger.
        await drain();
        await post('Debugger.disable');
      } catch {parentPort.postMessage({kind: 'unavailable'});}
      finally {
        await drain();
        try {session.disconnect();}
        finally {
          // Keep the existing Worker alive through callbacks queued by
          // disconnect before releasing its final handles. This turn is not
          // retirement: the parent still awaits this original Worker's exit.
          await new Promise<void>(resolve => setImmediate(resolve));
          clearInterval(alive);
          parentPort.close();
        }
      }
    })();
  });
  await flight(async () => {
    try {
      await post('Debugger.enable');
      // Enabling enumerates already loaded scripts. Finish those original
      // validation flights before arming their boundary or announcing ready;
      // a known mismatch must not enter while its Session is being retired.
      // A later import has no flight yet and keeps the pending URL breakpoint.
      while (sourceFlights.size > 0) await Promise.allSettled([...sourceFlights]);
      if (retiring || sourceRejected) return;
      ({breakpointId: breakpoint} = await post('Debugger.setBreakpointByUrl', {
        url: workerData.url, lineNumber: workerData.lineNumber, columnNumber: 0,
        ...(workerData.condition === undefined ? {} : {condition: workerData.condition})}));
      if (!retiring) parentPort.postMessage({kind: 'ready'});
    } catch {parentPort.postMessage({kind: 'unavailable'});}
  });
}

if (!isMainThread && workerData?.kind === 'packed-submission-cause') {
  const {Session} = await import('node:inspector');
  await runSubmissionCauseObserver({session: new Session(), parentPort, workerData} as ObserverPorts);
}

// Parent death must not leave a live fixture Host behind. Cancellation otherwise
// stops before the next case; the original case finally blocks retain cleanup.
export function ownTransportWorker() {
  assert.equal(typeof process.send, 'function', 'worker requires an owned IPC parent');
  assert.equal(process.connected, true, 'worker parent must still be connected');
  assert.equal(currentWorker, undefined, 'one fixture cleanup authority per worker');
  let cancelled = false;
  const cancel = (message: {type?: string} | null | undefined) => {
    if (message?.type === 'cancel-packed-query') cancelled = true;
  };
  const disconnected = () => process.exit(1);
  process.on('message', cancel);
  process.on('disconnect', disconnected);
  currentWorker = Object.freeze({
    check() { if (cancelled) throw new Error('PackedQuerySiblingCancelled'); },
    release() {
      process.removeListener('message', cancel);
      process.removeListener('disconnect', disconnected);
      if (process.connected) process.disconnect();
    },
  });
  return currentWorker;
}
export function transportWorker() {
  assert.ok(currentWorker, 'transport entry must install parent-death ownership before product imports');
  return currentWorker;
}

// Both transports and the serial tail use this one absolute deadline and one
// output allowance. No child creates a fresh acceptance budget or process group.
export function createTransportOwner({deadline, env = process.env, timeoutMs = acceptanceTimeoutMs,
  outputLimit = acceptanceOutputBytes, forward = (name, bytes) => process[name].write(bytes)}: TransportOptions) {
  assert.ok(Number.isSafeInteger(deadline) && deadline > Date.now());
  assert.ok(Number.isSafeInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= maximumAcceptanceTimeoutMs);
  assert.ok(deadline - Date.now() <= timeoutMs);
  assert.ok(Number.isSafeInteger(outputLimit) && outputLimit > 0 &&
    outputLimit <= acceptanceOutputBytes);
  let outputBytes = 0, primary: unknown, closed = false;
  const live = new Set<{child: ChildProcess; receipt: WorkerReceipt}>(), receipts: WorkerReceipt[] = [];
  let escalation: NodeJS.Timeout | undefined;
  const fail = (error: unknown) => {
    primary ??= error;
    for (const owned of live) {
      if (owned.child.connected) {
        try { owned.child.send({type: 'cancel-packed-query'}, () => {}); }
        catch { /* The same owned handle is still joined and has a bounded kill. */ }
      }
    }
    escalation ??= setTimeout(() => {
      for (const owned of live) owned.child.kill('SIGKILL');
    }, Math.max(0, Math.min(5000, deadline - Date.now())));
  };
  const expired = setTimeout(() => {
    primary ??= new Error('PackedQueryAcceptanceDeadline');
    for (const owned of live) owned.child.kill('SIGKILL');
  }, Math.max(0, deadline - Date.now()));
  const interrupted = (signal: string) => fail(new Error(`PackedQueryInterrupted:${signal}`));
  const sigint = () => interrupted('SIGINT'), sigterm = () => interrupted('SIGTERM');
  process.on('SIGINT', sigint);
  process.on('SIGTERM', sigterm);
  async function run(commands: readonly WorkerCommand[]) {
    assert.ok(!closed && !primary);
    assert.ok(Array.isArray(commands) && commands.length >= 1 && commands.length <= 2);
    assert.equal(live.size, 0, 'one transport batch at a time');
    if (Date.now() >= deadline) throw new Error('PackedQueryAcceptanceDeadline');
    const flights = commands.map(({name, command = process.execPath, args, cwd,
      environment = {}}) => new Promise<void>(resolve => {
      if (primary) { resolve(); return; }
      let child: ChildProcess;
      const receipt: WorkerReceipt = {name, startedAt: new Date().toISOString(), endedAt: null,
        pid: null, status: null, signal: null, error: null, terminal: false};
      receipts.push(receipt);
      try {
        child = spawn(command, args, {cwd, env: {...env, ...environment},
          detached: false, stdio: ['ignore', 'pipe', 'pipe', 'ipc']});
      } catch (error) {
        receipt.error = (error as NodeJS.ErrnoException).code ?? (error as Error).message;
        receipt.terminal = true;
        receipt.endedAt = new Date().toISOString();
        fail(error); resolve(); return;
      }
      const owned = {child, receipt};
      receipt.pid = child.pid ?? null;
      live.add(owned);
      for (const name of ['stdout', 'stderr'] as const) child[name]!.on('data', (bytes: Buffer) => {
        outputBytes += bytes.length;
        if (outputBytes > outputLimit) {
          fail(new Error('PackedQueryAggregateOutputLimit')); return;
        }
        try { forward(name, bytes); } catch (error) { fail(error); }
      });
      child.once('error', error => {
        receipt.error = (error as NodeJS.ErrnoException).code ?? (error as Error).message;
        fail(error);
      });
      child.once('exit', (code, signal) => {
        if (code !== 0 || signal !== null) fail(new Error(`PackedQueryWorkerFailed:${name}`));
      });
      child.once('close', (status, signal) => {
        Object.assign(receipt, {status, signal, endedAt: new Date().toISOString(), terminal: true});
        live.delete(owned);
        resolve();
      });
    }));
    await Promise.all(flights);
    if (primary) throw primary;
    assert.ok(receipts.every(receipt => receipt.terminal));
  }
  return Object.freeze({run,
    check() {
      if (primary) throw primary;
      if (Date.now() >= deadline) throw new Error('PackedQueryAcceptanceDeadline');
    },
    report: () => ({deadline, timeoutMs, workerOutputBytes: outputBytes, outputLimit,
      primaryError: (primary as Error | null | undefined)?.message ?? null, liveChildren: live.size,
      children: receipts.map(receipt => ({...receipt}))}),
    close() {
      assert.equal(live.size, 0, 'all owned workers must settle before release');
      closed = true;
      clearTimeout(expired); clearTimeout(escalation);
      process.removeListener('SIGINT', sigint); process.removeListener('SIGTERM', sigterm);
    },
  });
}
