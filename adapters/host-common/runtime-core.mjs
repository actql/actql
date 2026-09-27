import {checked} from './runtime-result.mjs';
import {publicationAction} from './publication-action.mjs';
import {
  validOutputLimits,
  validResultOutputLimits,
} from './result-output-limits.mjs';

const usageKeys = ['planningWork', 'attempts', 'holdings', 'transferredBytes',
  'reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes'];
const tuplePair = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [value._0, value._1]
    : undefined;
const siteControls = new WeakMap();
const remoteSiteControls = new WeakMap();
const remoteTransferControls = new WeakMap();
const remoteStandardSourceControls = new WeakMap();
const remoteCredentialControls = new WeakMap();
const effectApplicationControls = new WeakMap();
const remoteBundleControls = new WeakMap();
const publicationControls = new WeakMap();

function effectApplicationControl(moon) {
  let control = effectApplicationControls.get(moon);
  if (control !== undefined) return control;
  control = Object.freeze({
    logicalRequestScope: (...args) =>
      checked(moon.strategyEffectLogicalRequestScope(...args)),
    logicalRequestScopeCid: moon.strategyEffectLogicalRequestScopeCid,
    dispatchKey: (...args) =>
      checked(moon.strategyEffectDispatchKey(...args)),
    dispatchKeyCid: moon.strategyEffectDispatchKeyCid,
    recoveredPreviewKeys: (...args) => checked(
      moon.strategyEffectRecoveredPreviewKeys(...args)),
    batchRowsShareMember: moon.strategyEffectBatchRowsShareMember,
    logicalItemLocator: (...args) =>
      checked(moon.strategyEffectLogicalItemLocator(...args)),
    logicalItemLocatorCid: moon.strategyEffectLogicalItemLocatorCid,
    applyKey: (...args) =>
      checked(moon.strategyEffectApplyKey(...args)),
    applyKeyCid: moon.strategyEffectApplyKeyCid,
    recoveryAction: moon.strategyEffectRowRecoveryAction,
    recoveryActionFromEntry: moon.strategyEffectRowRecoveryActionFromEntry,
    setFrontier: (...args) => checked(moon.strategyEffectSetFrontier(...args)),
    setFrontierFromLedger: (...args) => checked(
      moon.strategyEffectSetFrontierFromLedger(...args)),
    setFrontierOutcome: moon.strategyEffectSetFrontierOutcome,
    setFrontierReadyCount: moon.strategyEffectSetFrontierReadyCount,
    setFrontierReadyMember: moon.strategyEffectSetFrontierReadyMember,
    setFrontierReadyRow: moon.strategyEffectSetFrontierReadyRow,
    checkSetFootprintConflicts: (...args) => checked(
      moon.strategyEffectSetFootprintConflictsCheck(...args),
    ),
    checkPreviewFootprintConflicts: (...args) => checked(
      moon.strategyEffectPreviewFootprintConflictsCheck(...args),
    ),
    derivePreviewIdentities: (...args) => checked(
      moon.strategyEffectPreviewIdentities(...args),
    ),
    derivePreviewRowIdentities: (...args) => checked(
      moon.strategyEffectPreviewRowIdentities(...args),
    ),
    admitPreviewApplyIdentity: (...args) => checked(
      moon.strategyEffectPreviewApplyIdentityAdmit(...args),
    ),
    admitPreviewIdentity: (...args) => checked(
      moon.strategyEffectPreviewApplyIdentity(...args),
    ),
    checkPreviewTargetGuards: (...args) => checked(
      moon.strategyEffectPreviewTargetGuardsCheck(...args),
    ),
    admitCollectionBatch: (...args) => checked(
      moon.strategyEffectCollectionBatchAdmit(...args),
    ),
    admitMemberRow: (...args) => checked(
      moon.strategyEffectMemberRowAdmit(...args),
    ),
    previewMemberKind: moon.strategyEffectPreviewMemberKind,
    previewOrderedRowCid: moon.strategyEffectPreviewOrderedRowCid,
    recoveryBindings: (...args) => checked(
      moon.strategyEffectRecoveryBindings(...args)),
    recoveryBindingLocatorCid:
      moon.strategyEffectRecoveryBindingLocatorCid,
    recoverClaimsFromHeads: (...args) => checked(
      moon.strategyEffectRecoverClaimsFromHeads(...args)),
    recoveredClaimScope: moon.strategyEffectRecoveredClaimScope,
    recoveredClaimLocator: moon.strategyEffectRecoveredClaimLocator,
    recoveredClaimKey: moon.strategyEffectRecoveredClaimKey,
    recoveredClaimBasis: moon.strategyEffectRecoveredClaimBasis,
    recoveredClaimIntentFingerprintCid:
      moon.strategyEffectRecoveredClaimIntentFingerprintCid,
    recoveredClaimCanonicalRequestCid:
      moon.strategyEffectRecoveredClaimCanonicalRequestCid,
    issueRowOutcomeReceipt: (...args) => {
      const value = checked(moon.strategyIssueEffectRowOutcomeReceipt(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
        terminalState: moon.strategyEffectRowOutcomeReceiptTerminalState(value),
      });
    },
    admitSavedResponseEvidence: (...args) => checked(
      moon.strategyAdmitEffectSavedResponseEvidence(...args)),
    issueRowOutcomeReceiptFromResponse: (...args) => {
      const value = checked(
        moon.strategyIssueEffectRowOutcomeReceiptFromResponse(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
        terminalState: moon.strategyEffectRowOutcomeReceiptTerminalState(value),
      });
    },
    admitRowOutcomeReceipt: (...args) => {
      const value = checked(moon.strategyAdmitEffectRowOutcomeReceipt(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
        terminalState: moon.strategyEffectRowOutcomeReceiptTerminalState(value),
      });
    },
    admitRowOutcomeReceiptFromResponse: (...args) => {
      const value = checked(
        moon.strategyAdmitEffectRowOutcomeReceiptFromResponse(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
        terminalState: moon.strategyEffectRowOutcomeReceiptTerminalState(value),
      });
    },
    issueRowReceiptTerminalEntry: (...args) => checked(
      moon.strategyIssueEffectRowReceiptTerminalEntry(...args),
    ),
    issueRowReceiptTerminalEntryFromResponse: (...args) => checked(
      moon.strategyIssueEffectRowReceiptTerminalEntryFromResponse(...args),
    ),
    checkMemberReceiptRowPartitionEvidence: (...args) => checked(
      moon.strategyCheckEffectMemberReceiptRowPartitionEvidence(...args),
    ),
    issueMemberReceiptFromRowPartition: (...args) => {
      const value = checked(
        moon.strategyIssueEffectMemberReceiptFromRowPartition(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
      });
    },
    issueSetReceiptFromMembers: (...args) => {
      const value = checked(
        moon.strategyIssueEffectSetApplyReceiptFromMembers(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
      });
    },
    admitLedgerEntry: (...args) => checked(
      moon.strategyEffectAdmitLedgerEntry(...args),
    ),
    ledgerEntryFollows: moon.strategyEffectLedgerEntryFollows,
    ledgerEntryCid: moon.strategyEffectLedgerEntryCid,
    ledgerEntryStateCode: moon.strategyEffectLedgerEntryStateCode,
    ledgerEntryLocatorCid: moon.strategyEffectLedgerEntryLocatorCid,
    ledgerEntryScopeCid: moon.strategyEffectLedgerEntryScopeCid,
    ledgerEntryWire: moon.strategyEffectLedgerEntryWire,
    ledgerEntryAdmitsDispatch: moon.strategyEffectLedgerEntryAdmitsDispatch,
    ledgerEntryMatchesBasis: moon.strategyEffectLedgerEntryMatchesBasis,
    ledgerBasis: (...args) => checked(moon.strategyEffectLedgerBasis(...args)),
    issuePreparedLedgerEntry: (...args) => checked(
      moon.strategyEffectIssuePreparedLedgerEntry(...args),
    ),
    issueNextLedgerEntry: (...args) => checked(
      moon.strategyEffectIssueNextLedgerEntry(...args),
    ),
  });
  effectApplicationControls.set(moon, control);
  return control;
}

function siteControl(moon) {
  let control = siteControls.get(moon);
  if (control !== undefined) return control;
  control = Object.freeze({
    create: configuration => moon.strategySiteCreate(
      configuration.key,
      configuration.generation,
      configuration.runtimeRevision,
      configuration.maxConcurrentOperations,
      configuration.maxConcurrentTransfers,
      configuration.maxRetainedBytes,
      configuration.maxExecutionBytes,
    ),
    available: moon.strategySiteAvailable,
    revoked: moon.strategySiteRevoked,
    capacitySupports: moon.strategySiteCapacitySupports,
    bindingCurrent: moon.strategySiteBindingCurrent,
    startOperation: moon.strategySiteStartOperation,
    operationAvailable: moon.strategySiteOperationAvailable,
    settleOperation: moon.strategySiteSettleOperation,
    retainOperationHolding: moon.strategySiteRetainOperationHolding,
    startTransfer: moon.strategySiteStartTransfer,
    transferAvailable: moon.strategySiteTransferAvailable,
    settleTransferSource: moon.strategySiteSettleTransferSource,
    settleTransferDestination: moon.strategySiteSettleTransferDestination,
    retainTransferHolding: moon.strategySiteRetainTransferHolding,
    retainHolding: moon.strategySiteRetainHolding,
    releaseHolding: moon.strategySiteReleaseHolding,
    retainCleanup: moon.strategySiteRetainCleanup,
    releaseCleanup: moon.strategySiteReleaseCleanup,
    beginTeardown: moon.strategySiteBeginTeardown,
    revoke: moon.strategySiteRevoke,
    status: moon.strategySiteStatus,
    selectCandidate: (durations, keys) =>
      moon.strategySiteSelectCandidate(
        durations.map(value => value ?? undefined), keys),
    planCandidate: value => tuplePair(
      moon.strategySitePlanCandidate(
        value.durationMilliseconds ?? undefined,
        value.startupMilliseconds,
        value.capacitySupported,
        value.acceptsSiteTransfer,
        value.transferProviderAvailable,
        value.transferMilliseconds,
        value.transferRequired,
        value.sharedTransfer,
        value.sourceRevoked,
        value.estimateAvailable,
        value.transferBytes,
        value.retainedBytes,
        value.executionBytes,
      ),
    ),
    managedCandidateFallback: moon.strategySiteManagedCandidateFallback,
    beginFailedOperation: moon.strategySiteBeginFailedOperationProgress,
    recordFailedOperationStop: moon.strategySiteRecordFailedOperationStop,
    recordFailedOperationSettlement:
      moon.strategySiteRecordFailedOperationSettlement,
    failedOperationAction: moon.strategySiteFailedOperationAction,
    beginRetainedClose: moon.strategySiteBeginRetainedCloseProgress,
    beginRetainedHolding: moon.strategySiteBeginRetainedHoldingProgress,
    recordRetainedCloseStarted:
      moon.strategySiteRecordRetainedCloseStarted,
    recordRetainedCloseSucceeded:
      moon.strategySiteRecordRetainedCloseSucceeded,
    recordRetainedCloseFailed:
      moon.strategySiteRecordRetainedCloseFailed,
    recordRetainedCleanupAuthority:
      moon.strategySiteRecordRetainedCleanupAuthority,
    recordRetainedCleanupStopped:
      moon.strategySiteRecordRetainedCleanupStopped,
    recordRetainedHoldingReleased:
      moon.strategySiteRecordRetainedHoldingReleased,
    retainedCloseAction: moon.strategySiteRetainedCloseAction,
    retainedHoldingAction: moon.strategySiteRetainedHoldingAction,
    beginHostCleanup: moon.strategyHostBeginCleanupProgress,
    recordHostCleanupRetry: moon.strategyHostRecordCleanupRetry,
    recordHostCleanupClosesAwaited:
      moon.strategyHostRecordCleanupClosesAwaited,
    hostCleanupAction: moon.strategyHostCleanupAction,
    hostCleanupPending: moon.strategyHostCleanupPending,
    hostTaskRunOutcome: moon.strategyHostTaskRunOutcome,
    beginHostTaskSuccess: moon.strategyHostBeginTaskSuccessProgress,
    recordHostTaskSiteCompletion:
      moon.strategyHostRecordTaskSiteCompletion,
    recordHostTaskCommonCompletion:
      moon.strategyHostRecordTaskCommonCompletion,
    recordHostTaskOutputRetained:
      moon.strategyHostRecordTaskOutputRetained,
    recordHostTaskSiteOperationSettled:
      moon.strategyHostRecordTaskSiteOperationSettled,
    recordHostTaskManagedBinding:
      moon.strategyHostRecordTaskManagedBinding,
    hostTaskSiteOperationSettled:
      moon.strategyHostTaskSiteOperationSettled,
    hostTaskSuccessAction: moon.strategyHostTaskSuccessAction,
  });
  siteControls.set(moon, control);
  return control;
}

function remoteSiteControl(moon) {
  let control = remoteSiteControls.get(moon);
  if (control !== undefined) return control;
  const fields = request => [
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
  const int64 = (value, label) => {
    if (typeof value === 'bigint' && value >= 0n) return value;
    if (Number.isSafeInteger(value) && value >= 0) return BigInt(value);
    throw new TypeError(`Invalid remote output ${label}`);
  };
  control = Object.freeze({
    prepare(request) {
      if (request === null || typeof request !== 'object') {
        throw new TypeError('Invalid remote dispatch request');
      }
      return checked(moon.strategyRemoteDispatchPrepare(...fields(request)));
    },
    admit(request) {
      if (request === null || typeof request !== 'object') {
        throw new TypeError('Invalid remote dispatch request');
      }
      const values = fields(request);
      values.splice(5, 0, request.dispatchRequestCid);
      return checked(moon.strategyRemoteDispatchAdmit(...values));
    },
    identity: moon.strategyRemoteDispatchIdentity,
    prepareBudget: configuration => checked(
      moon.strategyRemoteBudgetPrepare(
        configuration.retainedBytes,
        configuration.executionBytes,
      ),
    ),
    admitBudget: configuration => checked(
      moon.strategyRemoteBudgetAdmit(
        configuration.retainedBytes,
        configuration.executionBytes,
        configuration.budgetCid,
      ),
    ),
    budgetIdentity: moon.strategyRemoteBudgetIdentity,
    budgetJson: value => checked(moon.strategyRemoteBudgetJson(value)),
    budgetCapacity: value => tuplePair(
      moon.strategyRemoteBudgetCapacity(value),
    ),
    dispatchBudgetIdentity: moon.strategyRemoteDispatchBudgetIdentity,
    recordMatchesDispatch: moon.strategyRemoteRecordMatchesDispatch,
    requestJson: value => checked(moon.strategyRemoteDispatchJson(value)),
    prepareInputBinding: (body, maxBytes = 1_048_576) => checked(
      moon.strategyRemoteInputBindingPrepare(body, maxBytes),
    ),
    inputBindingIdentity: moon.strategyRemoteInputBindingIdentity,
    inputBindingMatchesDispatch:
      moon.strategyRemoteInputBindingMatchesDispatch,
    pollJson: (value, binding) => checked(
      moon.strategyRemotePollDispatchJson(value, binding),
    ),
    prepareOutputIntent(request, configuration) {
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
    preparePublicationPayload(configuration) {
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
    publicationPayloadJson: value => checked(
      moon.strategyRemotePublicationPayloadJson(value),
    ),
    admitPublicationPayloadJson: (body, claimedRequestCid) => checked(
      moon.strategyRemotePublicationPayloadAdmitJson(
        body,
        claimedRequestCid,
      ),
    ),
    pollOutputJson: (request, intent) => checked(
      moon.strategyRemotePollOutputJson(request, intent),
    ),
    pollOutputPlanJson: (request, intent) => checked(
      moon.strategyRemotePollOutputPlanJson(request, intent),
    ),
    admitPollOutput: body => checked(
      moon.strategyRemotePollOutputAdmit(body),
    ),
    admitPollOutputPlan: body => checked(
      moon.strategyRemotePollOutputPlanAdmit(body),
    ),
    admitOutputPlan: (
      body,
      output,
      subject,
      maxChunks,
      maxManifestBytes,
      maxReferencedBytes,
    ) => checked(moon.strategyRemoteOutputPlanAdmit(
      body,
      output,
      subject,
      maxChunks,
      maxManifestBytes,
      int64(maxReferencedBytes, 'remote output plan capacity'),
    )),
    prepareOutputPlan: (
      output,
      subject,
      payloadRequest,
      transferRequest,
    ) => checked(moon.strategyRemoteOutputPlanPrepare(
      output,
      subject,
      payloadRequest,
      transferRequest,
    )),
    outputPlanJson: plan => checked(
      moon.strategyRemoteOutputPlanJson(plan),
    ),
    outputPlanIdentity: moon.strategyRemoteOutputPlanIdentity,
    outputPlanPayloadRequest: moon.strategyRemoteOutputPlanPayloadRequest,
    outputPlanTransferRequest: moon.strategyRemoteOutputPlanTransferRequest,
    admitOutputResult: (
      body,
      output,
      payloadRequest,
      transferRequest,
    ) => checked(moon.strategyRemoteOutputResultAdmit(
      body,
      output,
      payloadRequest,
      transferRequest,
    )),
    prepareOutputResult: (
      output,
      payloadRequest,
      payloadDigest,
      transferRecord,
    ) => checked(moon.strategyRemoteOutputResultPrepare(
      output,
      payloadRequest,
      payloadDigest,
      transferRecord,
    )),
    outputResultJson: result => checked(
      moon.strategyRemoteOutputResultJson(result),
    ),
    outputResultIdentity: moon.strategyRemoteOutputResultIdentity,
    outputResultProjection: (result, transferRequest) => checked(
      moon.strategyRemoteOutputResultProjection(result, transferRequest),
    ),
    outputExpectedIdentity: (payloadRequest, transferRequest) =>
      moon.strategyRemoteOutputExpectedIdentity(
        payloadRequest,
        transferRequest,
      ),
    admitPollDispatch: body => checked(
      moon.strategyRemotePollDispatchAdmit(body),
    ),
    pollDispatchRequest: moon.strategyRemotePollDispatchRequest,
    pollDispatchBindingBody: moon.strategyRemotePollDispatchBindingBody,
    pollQueryJson: value => checked(moon.strategyRemotePollQueryJson(value)),
    pollReleaseJson: value => checked(
      moon.strategyRemotePollReleaseJson(value),
    ),
    pollNotSeenJson: value => checked(
      moon.strategyRemotePollNotSeenJson(value),
    ),
    admitPollNotSeen: (body, request) => checked(
      moon.strategyRemotePollNotSeenAdmit(body, request),
    ),
    replyJson: value => checked(moon.strategyRemoteDispatchReplyJson(value)),
    statusJson: (record, evidence, subject, measurement) => checked(
      moon.strategyRemoteDispatchStatusJson(
        record,
        evidence,
        subject,
        measurement,
      ),
    ),
    admitJson: (body, claimedRequestCid) => checked(
      moon.strategyRemoteDispatchAdmitJson(body, claimedRequestCid),
    ),
    admitResponseJson: (body, request, statusReply) => checked(
      moon.strategyRemoteDispatchResponseAdmitJson(
        body,
        request,
        statusReply,
      ),
    ),
    responseProjection: moon.strategyRemoteDispatchResponseProjection,
    responseEvidence: moon.strategyRemoteDispatchResponseEvidence,
    responseSubject: moon.strategyRemoteDispatchResponseSubject,
    responseMeasurement: moon.strategyRemoteDispatchResponseMeasurement,
    journalKey: moon.strategyRemoteDispatchJournalKey,
    executionScope: moon.strategyRemoteDispatchExecutionScope,
    managedRuntimeRegistrationScope: (capability, issuer) => checked(
      moon.strategyRemoteManagedRuntimeRegistrationScope(capability, issuer),
    ),
    createCoordinatorJournal: authority => checked(
      moon.strategyRemoteCoordinatorJournalCreate(authority),
    ),
    prepareCoordinatorIntent: (journal, request) => checked(
      moon.strategyRemoteCoordinatorIntentPrepare(journal, request),
    ),
    coordinatorIntentIsNew: moon.strategyRemoteCoordinatorIntentIsNew,
    coordinatorIntentJson: value => checked(
      moon.strategyRemoteCoordinatorIntentJson(value),
    ),
    commitCoordinatorIntent: (value, durable) => checked(
      moon.strategyRemoteCoordinatorIntentCommit(value, durable),
    ),
    coordinatorIntentMatches:
      moon.strategyRemoteCoordinatorIntentMatches,
    restoreCoordinatorIntent: (journal, request) => checked(
      moon.strategyRemoteCoordinatorIntentRestore(journal, request),
    ),
    prepareCoordinatorUnknown: record => checked(
      moon.strategyRemoteCoordinatorPrepareUnknown(record),
    ),
    prepareCoordinatorObservation(record, observation) {
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
    commitCoordinatorTransition: (transition, durable) => checked(
      moon.strategyRemoteCoordinatorTransitionCommit(transition, durable),
    ),
    coordinatorRecordStatus: moon.strategyRemoteCoordinatorRecordStatus,
    coordinatorRecordRevision: moon.strategyRemoteCoordinatorRecordRevision,
    restoreCoordinatorRecord: (record, state) => {
      if (!Array.isArray(state) || state.length !== 11) {
        throw new TypeError('Invalid remote Coordinator state');
      }
      return checked(
        moon.strategyRemoteCoordinatorRecordRestore(record, ...state),
      );
    },
    coordinatorCompletionEvidenceAvailable:
      moon.strategyRemoteCoordinatorCompletionEvidenceAvailable,
    prepareCoordinatorOutput: (
      journal,
      output,
      payloadRequest,
      transferRequest,
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
    coordinatorOutputAdmissionJson: admission => checked(
      moon.strategyRemoteCoordinatorOutputAdmissionJson(admission),
    ),
    commitCoordinatorOutput: (admission, durable) => checked(
      moon.strategyRemoteCoordinatorOutputCommit(admission, durable),
    ),
    prepareCoordinatorOutputUnknown: record => checked(
      moon.strategyRemoteCoordinatorOutputPrepareUnknown(record),
    ),
    prepareCoordinatorOutputSuccess: (record, result) => checked(
      moon.strategyRemoteCoordinatorOutputPrepareSuccess(record, result),
    ),
    coordinatorOutputTransitionKey:
      moon.strategyRemoteCoordinatorOutputTransitionKey,
    coordinatorOutputTransitionProjection:
      moon.strategyRemoteCoordinatorOutputTransitionProjection,
    commitCoordinatorOutputTransition: (transition, durable) => checked(
      moon.strategyRemoteCoordinatorOutputTransitionCommit(
        transition,
        durable,
      ),
    ),
    coordinatorOutputRecordKey:
      moon.strategyRemoteCoordinatorOutputRecordKey,
    coordinatorOutputRecordStatus:
      moon.strategyRemoteCoordinatorOutputRecordStatus,
    coordinatorOutputRecordRevision:
      moon.strategyRemoteCoordinatorOutputRecordRevision,
    coordinatorOutputRecordResultJson: record => checked(
      moon.strategyRemoteCoordinatorOutputRecordResultJson(record),
    ),
    coordinatorOutputRecordResultProjection: record => checked(
      moon.strategyRemoteCoordinatorOutputRecordResultProjection(record),
    ),
    restoreCoordinatorOutputRecord: (
      record,
      revision,
      progress,
      resultJson,
    ) => checked(moon.strategyRemoteCoordinatorOutputRecordRestore(
      record,
      revision,
      progress,
      resultJson,
    )),
    createJournal: value => checked(moon.strategyRemoteJournalCreate(value)),
    prepareAdmission: (journal, request) => checked(
      moon.strategyRemoteAdmissionPrepare(journal, request),
    ),
    admissionIsNew: moon.strategyRemoteAdmissionIsNew,
    admissionJson: value => checked(
      moon.strategyRemoteAdmissionJson(value),
    ),
    commitAdmission: (value, durable) => checked(
      moon.strategyRemoteAdmissionCommit(value, durable),
    ),
    registerExecutionCapability: configuration => checked(
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
    prepareProvisioning: (value, capability) => checked(
      moon.strategyRemotePrepareProvisioning(value, capability),
    ),
    prepareManagedProvisioning: (value, capability, issuer) => checked(
      moon.strategyRemotePrepareManagedProvisioning(value, capability, issuer),
    ),
    prepareExecution: value => checked(
      moon.strategyRemotePrepareExecution(value),
    ),
    prepareSettled: value => checked(
      moon.strategyRemotePrepareSettled(value),
    ),
    prepareFailed: value => checked(
      moon.strategyRemotePrepareFailed(value),
    ),
    prepareCancelled: value => checked(
      moon.strategyRemotePrepareCancelled(value),
    ),
    prepareReconciledFailure: value => checked(
      moon.strategyRemotePrepareReconciledFailure(value),
    ),
    prepareReconciledCancellation: value => checked(
      moon.strategyRemotePrepareReconciledCancellation(value),
    ),
    prepareRetained: (value, material, holding) => checked(
      moon.strategyRemotePrepareRetained(value, material, holding),
    ),
    registerEvidenceIssuer: configuration => checked(
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
    issueExecutionEvidence: (issuer, record, evidenceSubjectCid) => checked(
      moon.strategyRemoteIssueExecutionEvidence(
        issuer,
        record,
        evidenceSubjectCid,
      ),
    ),
    prepareManagedOutputMeasurement: measurement => checked(
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
    managedOutputMeasurementJson: value => checked(
      moon.strategyRemoteManagedOutputMeasurementJson(value),
    ),
    managedOutputMeasurementProjection:
      moon.strategyRemoteManagedOutputMeasurementProjection,
    admitManagedOutputMeasurement: measurement => checked(
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
    admitManagedOutputMeasurementJson: (
      body,
      claimedMeasurementCid,
    ) => checked(
      moon.strategyRemoteManagedOutputMeasurementAdmitJson(
        body,
        claimedMeasurementCid,
      ),
    ),
    outputHoldingEvidenceIdentity: (
      dispatch,
      materialGeneration,
      retainedBytes,
    ) => checked(
      moon.strategyRemoteOutputHoldingEvidenceIdentity(
        dispatch,
        materialGeneration,
        retainedBytes,
      ),
    ),
    prepareManagedOutputSubject: (
      dispatch,
      output,
      measurement,
      holdingEvidenceCid,
    ) => checked(
      moon.strategyRemoteManagedOutputSubjectPrepare(
        control.identity(dispatch),
        output.materialGeneration,
        holdingEvidenceCid,
        output.managedProfileCid,
        output.resultSchemaCid,
        output.logicalViewCid,
        output.representationCodecCid,
        output.physicalManifestCid,
        control.managedOutputMeasurementIdentity(measurement),
        output.rowCount,
        output.retainedBytes,
      ),
    ),
    managedOutputEvidenceKind:
      moon.strategyRemoteManagedOutputEvidenceKind(),
    admitManagedOutputSubject: subject => checked(
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
    admitManagedOutputSubjectJson: (
      body,
      claimedSubjectCid,
      dispatch,
    ) => checked(
      moon.strategyRemoteManagedOutputSubjectAdmitJson(
        body,
        claimedSubjectCid,
        dispatch,
      ),
    ),
    managedOutputSubjectIdentity:
      moon.strategyRemoteManagedOutputSubjectIdentity,
    managedOutputSubjectJson: value => checked(
      moon.strategyRemoteManagedOutputSubjectJson(value),
    ),
    managedOutputSubjectProjection:
      moon.strategyRemoteManagedOutputSubjectProjection,
    managedOutputSubjectMatchesMeasurement:
      moon.strategyRemoteManagedOutputSubjectMatchesMeasurement,
    issueManagedOutputEvidence: (issuer, record, subject) => checked(
      moon.strategyRemoteIssueManagedOutputEvidence(
        issuer,
        record,
        subject,
      ),
    ),
    managedOutputSubjectMatchesEvidence:
      moon.strategyRemoteManagedOutputSubjectMatchesEvidence,
    admitExecutionEvidence: evidence => checked(
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
    admitExecutionEvidenceJson: (
      body,
      claimedEvidenceCid,
      dispatch,
    ) => checked(
      moon.strategyRemoteExecutionEvidenceAdmitJson(
        body,
        claimedEvidenceCid,
        dispatch,
      ),
    ),
    evidenceIdentity: moon.strategyRemoteExecutionEvidenceIdentity,
    evidenceMatchesDispatch:
      moon.strategyRemoteExecutionEvidenceMatchesDispatch,
    evidenceJson: value => checked(
      moon.strategyRemoteExecutionEvidenceJson(value),
    ),
    prepareEvidence: (value, evidence) => checked(
      moon.strategyRemotePrepareEvidence(value, evidence),
    ),
    prepareEvidenceRejection: value => checked(
      moon.strategyRemotePrepareEvidenceRejection(value),
    ),
    runtimeAdmission: moon.strategyRemoteRuntimeAdmission,
    runtimeStartable: moon.strategyRemoteRuntimeStartable,
    createRuntimeCustody: moon.strategyRemoteRuntimeCustodyCreate,
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
    runtimeSuccessAction: (record, custody) => checked(
      moon.strategyRemoteRuntimeSuccessAction(record, custody),
    ),
    prepareRuntimeFailure: (value, cancelled, stopConfirmed) => checked(
      moon.strategyRemoteRuntimeFailurePlan(
        value,
        cancelled,
        stopConfirmed,
      ),
    ),
    prepareOwnedRuntimeFailure: (value, custody) => checked(
      moon.strategyRemoteRuntimeOwnedFailurePlan(value, custody),
    ),
    prepareRuntimeCleanup: (
      value,
      cancelled,
      stopConfirmed,
      resourcesReclaimed,
    ) => checked(
      moon.strategyRemoteRuntimeCleanupPlan(
        value,
        cancelled,
        stopConfirmed,
        resourcesReclaimed,
      ),
    ),
    prepareOwnedRuntimeCleanup: (value, custody) => checked(
      moon.strategyRemoteRuntimeOwnedCleanupPlan(value, custody),
    ),
    prepareRuntimeReclaimUnknown: value => checked(
      moon.strategyRemoteRuntimeReclaimUnknownPlan(value),
    ),
    runtimeStepAction: moon.strategyRemoteRuntimeStepAction,
    runtimeStepTransition: value => checked(
      moon.strategyRemoteRuntimeStepTransition(value),
    ),
    prepareUnknown: value => checked(
      moon.strategyRemotePrepareUnknown(value),
    ),
    prepareRelease: value => checked(
      moon.strategyRemotePrepareRelease(value),
    ),
    prepareReleased: value => checked(
      moon.strategyRemotePrepareReleased(value),
    ),
    prepareLossRecovery: value => checked(
      moon.strategyRemotePrepareLossRecovery(value),
    ),
    prepareForceLoss: (journal, value, authorized) => checked(
      moon.strategyRemotePrepareForceLoss(journal, value, authorized),
    ),
    forceLossProjection: moon.strategyRemoteForceLossProjection,
    forceLossKey: moon.strategyRemoteForceLossKey,
    commitForceLoss: (value, durable) => checked(
      moon.strategyRemoteForceLossCommit(value, durable),
    ),
    prepareRestart: (journal, replacement) => checked(
      moon.strategyRemotePrepareRestart(journal, replacement),
    ),
    restartCount: moon.strategyRemoteRestartCount,
    restartAt: (restart, index) => checked(
      moon.strategyRemoteRestartAt(restart, index),
    ),
    restartMetadata: moon.strategyRemoteRestartMetadata,
    commitRestart: (restart, durable) => checked(
      moon.strategyRemoteRestartCommit(restart, durable),
    ),
    transitionProjection: moon.strategyRemoteTransitionProjection,
    transitionKey: moon.strategyRemoteTransitionKey,
    commitTransition: (value, durable) => checked(
      moon.strategyRemoteTransitionCommit(value, durable),
    ),
    status: moon.strategyRemoteRecordStatus,
    revision: moon.strategyRemoteRecordRevision,
    restore(record, state) {
      if (!Array.isArray(state) || state.length !== 9) {
        throw new TypeError('Invalid remote dispatch state');
      }
      return checked(moon.strategyRemoteRecordRestore(record, ...state));
    },
    restoreHistorical: (journal, request) => checked(
      moon.strategyRemoteHistoricalRestore(journal, request),
    ),
  });
  remoteSiteControls.set(moon, control);
  return control;
}

function remoteTransferControl(moon) {
  let control = remoteTransferControls.get(moon);
  if (control !== undefined) return control;
  const int64 = (value, label) => {
    if (typeof value === 'bigint' && value >= 0n) return value;
    if (Number.isSafeInteger(value) && value >= 0) return BigInt(value);
    throw new TypeError(`Invalid Remote Transfer ${label}`);
  };
  const requestFields = request => {
    if (request === null || typeof request !== 'object' ||
        request.physicalManifest === null ||
        typeof request.physicalManifest !== 'object' ||
        !Array.isArray(request.physicalManifest.chunks) ||
        request.limits === null || typeof request.limits !== 'object' ||
        !Number.isSafeInteger(request.limits.maxChunks) ||
        request.limits.maxChunks < 0 ||
        !Number.isSafeInteger(request.limits.maxManifestBytes) ||
        request.limits.maxManifestBytes < 0 ||
        !Number.isSafeInteger(request.sourceSiteGeneration) ||
        request.sourceSiteGeneration < 0 ||
        !Number.isSafeInteger(request.destinationSiteGeneration) ||
        request.destinationSiteGeneration < 0 ||
        !Number.isSafeInteger(request.physicalManifest.rowCount) ||
        request.physicalManifest.rowCount < 0 ||
        request.physicalManifest.chunks.length > request.limits.maxChunks) {
      throw new TypeError('Invalid Remote Transfer request');
    }
    const physical = request.physicalManifest;
    const chunks = physical.chunks;
    if (chunks.some(chunk => chunk === null || typeof chunk !== 'object' ||
      !Number.isSafeInteger(chunk.rowCount) || chunk.rowCount < 0)) {
      throw new TypeError('Invalid Remote Transfer chunks');
    }
    return [
      request.coordinatorAuthority,
      request.transferAttemptId,
      request.route === 'direct' ? 0 : request.route === 'store' ? 1 : -1,
      request.sourceSite,
      request.sourceSiteGeneration,
      request.destinationSite,
      request.destinationSiteGeneration,
      request.sourceMaterialGeneration,
      physical.version,
      physical.schemaContractCid,
      physical.viewContractCid,
      physical.codecContractCid,
      physical.rowCount,
      chunks.map(chunk => chunk.cid),
      chunks.map(chunk => int64(chunk.byteLength, 'chunk length')),
      chunks.map(chunk => chunk.rowCount),
      request.limits.maxChunks,
      request.limits.maxManifestBytes,
      int64(request.limits.maxReferencedBytes, 'referenced-byte limit'),
      int64(request.capacityBytes, 'capacity'),
      int64(request.expiresAtMilliseconds, 'expiry'),
      request.sourceGrantCid,
      request.destinationGrantCid,
      request.routeCapabilityCid,
    ];
  };
  control = Object.freeze({
    prepare: request => checked(
      moon.strategyRemoteTransferPrepare(...requestFields(request)),
    ),
    identity: moon.strategyRemoteTransferIdentity,
    requestJson: value => checked(moon.strategyRemoteTransferJson(value)),
    manifestJson: value => checked(
      moon.strategyRemoteTransferManifestJson(value),
    ),
    admitJson: (
      body,
      manifestBody,
      claimedRequestCid,
      claimedManifestCid,
      limits,
    ) => {
      if (limits === null || typeof limits !== 'object' ||
          !Number.isSafeInteger(limits.maxChunks) || limits.maxChunks < 0 ||
          !Number.isSafeInteger(limits.maxManifestBytes) ||
          limits.maxManifestBytes < 0) {
        throw new TypeError('Invalid Remote Transfer wire limits');
      }
      return checked(moon.strategyRemoteTransferAdmitJson(
        body,
        manifestBody,
        claimedRequestCid,
        claimedManifestCid,
        limits.maxChunks,
        limits.maxManifestBytes,
        int64(limits.maxReferencedBytes, 'referenced-byte limit'),
      ));
    },
    admissionEnvelopeJson: value => checked(
      moon.strategyRemoteTransferAdmissionEnvelopeJson(value),
    ),
    admitAdmissionEnvelopeJson: (
      body,
      claimedRequestCid,
      claimedManifestCid,
      limits,
    ) => {
      if (limits === null || typeof limits !== 'object' ||
          !Number.isSafeInteger(limits.maxChunks) || limits.maxChunks < 0 ||
          !Number.isSafeInteger(limits.maxManifestBytes) ||
          limits.maxManifestBytes < 0) {
        throw new TypeError('Invalid Remote Transfer wire limits');
      }
      return checked(moon.strategyRemoteTransferAdmissionEnvelopeAdmitJson(
        body,
        claimedRequestCid,
        claimedManifestCid,
        limits.maxChunks,
        limits.maxManifestBytes,
        int64(limits.maxReferencedBytes, 'referenced-byte limit'),
      ));
    },
    replyJson: value => checked(
      moon.strategyRemoteTransferReplyJson(value),
    ),
    admitReplyJson: (body, request) => checked(
      moon.strategyRemoteTransferReplyAdmitJson(body, request),
    ),
    storeUploadReplyJson: (request, kind, nextChunk, sealed) => checked(
      moon.strategyRemoteTransferStoreUploadReplyJson(
        request,
        kind === 'admission' ? 0 : kind === 'chunk' ? 1 :
          kind === 'commit' ? 2 : -1,
        nextChunk,
        sealed,
      ),
    ),
    admitStoreUploadReplyJson: (body, request, kind) => checked(
      moon.strategyRemoteTransferStoreUploadReplyAdmitJson(
        body,
        request,
        kind === 'admission' ? 0 : kind === 'chunk' ? 1 :
          kind === 'commit' ? 2 : -1,
      ),
    ),
    storeUploadReplyProjection:
      moon.strategyRemoteTransferStoreUploadReplyProjection,
    storeUseReplyJson: (request, useId, kind, complete) => checked(
      moon.strategyRemoteTransferStoreUseReplyJson(
        request,
        useId,
        kind === 'admission' ? 0 : kind === 'completion' ? 1 : -1,
        complete,
      ),
    ),
    admitStoreUseReplyJson: (body, request, useId, kind) => checked(
      moon.strategyRemoteTransferStoreUseReplyAdmitJson(
        body,
        request,
        useId,
        kind === 'admission' ? 0 : kind === 'completion' ? 1 : -1,
      ),
    ),
    storeUseReplyProjection:
      moon.strategyRemoteTransferStoreUseReplyProjection,
    storeUseCancellationReplyJson: (request, useId) => checked(
      moon.strategyRemoteTransferStoreUseCancellationReplyJson(
        request,
        useId,
      ),
    ),
    admitStoreUseCancellationReplyJson: (body, request, useId) => checked(
      moon.strategyRemoteTransferStoreUseCancellationReplyAdmitJson(
        body,
        request,
        useId,
      ),
    ),
    storeUseCancellationReplyProjection:
      moon.strategyRemoteTransferStoreUseCancellationReplyProjection,
    prepareDestinationReceipt: (request, materialGeneration) => checked(
      moon.strategyRemoteTransferDestinationReceiptPrepare(
        request,
        materialGeneration,
      ),
    ),
    destinationReceiptJson: receipt => checked(
      moon.strategyRemoteTransferDestinationReceiptJson(receipt),
    ),
    destinationReceiptIdentity:
      moon.strategyRemoteTransferDestinationReceiptIdentity,
    admitDestinationReceiptJson: (body, request, claimedReceiptCid) =>
      checked(moon.strategyRemoteTransferDestinationReceiptAdmitJson(
        body,
        request,
        claimedReceiptCid,
      )),
    destinationReceiptProjection:
      moon.strategyRemoteTransferDestinationReceiptProjection,
    storeUse: Object.freeze({
      prepare: (request, useId) => checked(
        moon.strategyRemoteTransferStoreUsePrepare(request, useId),
      ),
      identity: moon.strategyRemoteTransferStoreUseIdentity,
      projection: moon.strategyRemoteTransferStoreUseProjection,
      open: moon.strategyRemoteTransferStoreUseOpen,
      prepareStart: record => checked(
        moon.strategyRemoteTransferStoreUseStartPrepare(record),
      ),
      prepareProgress: (record, confirmedChunks, confirmedBytes) => checked(
        moon.strategyRemoteTransferStoreUseProgressPrepare(
          record,
          confirmedChunks,
          int64(confirmedBytes, 'confirmed Store use bytes'),
        ),
      ),
      prepareComplete: (record, receipt) => checked(
        moon.strategyRemoteTransferStoreUseCompletePrepare(record, receipt),
      ),
      prepareFailure: (record, readerStopped) => checked(
        moon.strategyRemoteTransferStoreUseFailurePrepare(
          record,
          readerStopped,
        ),
      ),
      prepareUnknown: record => checked(
        moon.strategyRemoteTransferStoreUseUnknownPrepare(record),
      ),
      prepareCleanup: record => checked(
        moon.strategyRemoteTransferStoreUseCleanupPrepare(record),
      ),
      transitionProjection: transition => tuplePair(
        moon.strategyRemoteTransferStoreUseTransitionProjection(transition),
      ),
      transitionKey:
        moon.strategyRemoteTransferStoreUseTransitionJournalKey,
      commitTransition: (transition, durable) => checked(
        moon.strategyRemoteTransferStoreUseTransitionCommit(
          transition,
          durable,
        ),
      ),
      recordProjection: moon.strategyRemoteTransferStoreUseRecordProjection,
      restore: (storeUse, state) => {
        if (!Array.isArray(state) || state.length !== 7 ||
            state.some(value => typeof value !== 'string') ||
            !/^(0|[1-9][0-9]*)$/.test(state[0]) ||
            !/^[0-4]$/.test(state[1]) || !/^[0-2]$/.test(state[2]) ||
            !/^(0|[1-9][0-9]*)$/.test(state[3]) ||
            !/^(0|[1-9][0-9]*)$/.test(state[4]) ||
            !/^[01]$/.test(state[5])) {
          throw new TypeError('Invalid Remote Transfer Store use state');
        }
        const revision = Number(state[0]);
        const confirmedChunks = Number(state[3]);
        if (!Number.isSafeInteger(revision) ||
            !Number.isSafeInteger(confirmedChunks)) {
          throw new TypeError('Invalid Remote Transfer Store use revision');
        }
        return checked(moon.strategyRemoteTransferStoreUseRecordRestore(
          storeUse,
          revision,
          Number(state[1]),
          Number(state[2]),
          confirmedChunks,
          BigInt(state[4]),
          state[5] === '1',
          state[6],
        ));
      },
    }),
    requestProjection: moon.strategyRemoteTransferProjection,
    journalKey: moon.strategyRemoteTransferJournalKey,
    chunks: request => {
      const cids = moon.strategyRemoteTransferChunkCids(request);
      const byteLengths = moon.strategyRemoteTransferChunkByteLengths(request);
      const rowCounts = moon.strategyRemoteTransferChunkRowCounts(request);
      if (cids.length !== byteLengths.length ||
          cids.length !== rowCounts.length) {
        throw new Error('Remote Transfer projection mismatch');
      }
      return Object.freeze(cids.map((cid, index) => Object.freeze({
        cid,
        byteLength: byteLengths[index],
        rowCount: rowCounts[index],
      })));
    },
    activeAt: (request, trustedNowMilliseconds) =>
      moon.strategyRemoteTransferActiveAt(
        request,
        int64(trustedNowMilliseconds, 'trusted clock'),
      ),
    open: moon.strategyRemoteTransferOpen,
    prepareStart: value => checked(
      moon.strategyRemoteTransferStartPrepare(value),
    ),
    prepareSourceSettled: (value, integrityVerified, objectSealed) => checked(
      moon.strategyRemoteTransferSourceSettledPrepare(
        value,
        integrityVerified,
        objectSealed,
      ),
    ),
    prepareDestinationCommit: value => checked(
      moon.strategyRemoteTransferDestinationCommitPrepare(value),
    ),
    prepareFailure: (value, cancelled, sourceAccessStopped) => checked(
      moon.strategyRemoteTransferFailurePrepare(
        value,
        cancelled,
        sourceAccessStopped,
      ),
    ),
    prepareUnknown: value => checked(
      moon.strategyRemoteTransferUnknownPrepare(value),
    ),
    prepareCleanup: (
      value,
      sourceAccessStopped,
      destinationTemporaryReclaimed,
      objectUseReleased,
    ) => checked(moon.strategyRemoteTransferCleanupPrepare(
      value,
      sourceAccessStopped,
      destinationTemporaryReclaimed,
      objectUseReleased,
    )),
    transitionProjection: value => tuplePair(
      moon.strategyRemoteTransferTransitionProjection(value),
    ),
    transitionKey: moon.strategyRemoteTransferTransitionJournalKey,
    commitTransition: (value, durable) => checked(
      moon.strategyRemoteTransferTransitionCommit(value, durable),
    ),
    recordProjection: moon.strategyRemoteTransferRecordProjection,
    recordRequestIdentity:
      moon.strategyRemoteTransferRecordRequestIdentity,
    recordIsDestinationCommitted:
      moon.strategyRemoteTransferRecordIsDestinationCommitted,
    directCleanupConfirmed:
      moon.strategyRemoteTransferDirectCleanupConfirmed,
    directTransferProgress:
      moon.strategyRemoteTransferDirectProgress,
    directCancelDecision:
      moon.strategyRemoteTransferDirectCancelDecision,
    revision: moon.strategyRemoteTransferRecordRevision,
    restore: (request, state) => {
      if (!Array.isArray(state) || state.length !== 9 ||
          state.some(value => !Number.isSafeInteger(value))) {
        throw new TypeError('Invalid Remote Transfer state');
      }
      return checked(moon.strategyRemoteTransferRecordRestore(request, state));
    },
  });
  remoteTransferControls.set(moon, control);
  return control;
}

function remoteStandardSourceControl(moon) {
  let control = remoteStandardSourceControls.get(moon);
  if (control !== undefined) return control;
  control = Object.freeze({
    register(configuration) {
      if (configuration === null || typeof configuration !== 'object') {
        throw new TypeError('Invalid remote standard source configuration');
      }
      const binding = configuration.bindingLimits;
      const source = configuration.sourceLimits;
      const values = source?.values;
      const wire = source?.wire;
      return moon.strategyRemoteStandardSourceFactoryRegister(
        configuration.schemaContractCid,
        configuration.viewContractCid,
        configuration.codecContractCid,
        configuration.sequence,
        configuration.program,
        binding?.maxBindingBytes,
        binding?.maxChunks,
        binding?.maxManifestBytes,
        binding?.maxReferencedBytes,
        source?.maxRows,
        source?.maxWireBytes,
        source?.maxReadBytes,
        source?.maxEntries,
        source?.maxNameBytes,
        values?.maxNodes,
        values?.maxTextBytes,
        values?.maxDepth,
        values?.maxWork,
        wire?.maxBytes,
        wire?.maxNodes,
        wire?.maxDepth,
        wire?.maxTextBytes,
      );
    },
    requestCid: moon.strategyRemoteStandardSourceFactoryRequestCid,
    start: (factory, dispatch, binding, claim, available, release) =>
      moon.strategyRemoteStandardSourceSessionStart(
        factory,
        dispatch,
        binding,
        claim.request,
        claim.destinationReceipt,
        available,
        release,
      ),
    authorize: (session, claim) =>
      moon.strategyRemoteStandardSourceSessionAuthorizes(
        session,
        claim.request,
        claim.destinationReceipt,
      ),
    feed: moon.strategyRemoteStandardSourceSessionFeed,
    finish: moon.strategyRemoteStandardSourceSessionFinish,
    cancel: moon.strategyRemoteStandardSourceSessionCancel,
    captured: moon.strategyRemoteStandardSourceCaptured,
    release: moon.strategyRemoteStandardSourceRelease,
    failureCode: moon.strategyRemoteStandardInputFailureCode,
    failureCleanupPending:
      moon.strategyRemoteStandardInputFailureCleanupPending,
    retryFailureCleanup:
      moon.strategyRemoteStandardInputFailureCleanupRetry,
  });
  remoteStandardSourceControls.set(moon, control);
  return control;
}

function remoteCredentialControl(moon) {
  let control = remoteCredentialControls.get(moon);
  if (control !== undefined) return control;
  const grantFields = grant => {
    if (grant === null || typeof grant !== 'object') {
      throw new TypeError('Invalid Remote Credential grant');
    }
    return [
      grant.issuerAuthority,
      grant.principal,
      grant.tenant,
      grant.environment,
      grant.siteKey,
      grant.siteGeneration,
      grant.runtimeBundleCid,
      grant.connectorRegistration,
      grant.connectorRevision,
      grant.resourceOrigin,
      grant.operation,
      grant.runInvocationCid,
      grant.taskAttempt,
      grant.dispatchRequestCid,
      BigInt(grant.expiresUnixMilliseconds),
      grant.maxUses,
    ];
  };
  control = Object.freeze({
    prepare: grant => checked(
      moon.strategyRemoteCredentialGrantPrepare(...grantFields(grant)),
    ),
    identity: moon.strategyRemoteCredentialGrantIdentity,
    json: grant => checked(moon.strategyRemoteCredentialGrantJson(grant)),
    admitJson: (body, claimedGrantCid) => checked(
      moon.strategyRemoteCredentialGrantAdmitJson(body, claimedGrantCid),
    ),
    projection: moon.strategyRemoteCredentialGrantProjection,
    signaturePreimage: grant => checked(
      moon.strategyRemoteCredentialSignaturePreimage(grant),
    ),
    prepareSignatureEnvelope: (grant, keyId, signature) => checked(
      moon.strategyRemoteCredentialSignatureEnvelopePrepare(
        grant,
        keyId,
        signature,
      ),
    ),
    admitSignatureEnvelope: envelope => checked(
      moon.strategyRemoteCredentialSignatureEnvelopeAdmit(
        envelope.version,
        envelope.keyId,
        envelope.grantCid,
        envelope.body,
        envelope.signature,
      ),
    ),
    signatureEnvelopeProjection:
      moon.strategyRemoteCredentialSignatureEnvelopeProjection,
    signatureEnvelopeGrant:
      moon.strategyRemoteCredentialSignatureEnvelopeGrant,
    prepareUse(grant, request) {
      if (request === null || typeof request !== 'object') {
        throw new TypeError('Invalid Remote Credential use');
      }
      const scope = grantFields(request.scope);
      return checked(moon.strategyRemoteCredentialUsePrepare(
        grant,
        request.useId,
        BigInt(request.trustedNowMilliseconds),
        request.usedCount,
        request.revoked,
        ...scope.slice(1, 15),
      ));
    },
    useIdentity: moon.strategyRemoteCredentialUseIdentity,
    useJson: value => checked(moon.strategyRemoteCredentialUseJson(value)),
    authorizeUse(value, request) {
      if (request === null || typeof request !== 'object') {
        throw new TypeError('Invalid Remote Credential authorization');
      }
      const scope = grantFields(request.scope);
      checked(moon.strategyRemoteCredentialUseAuthorize(
        value,
        BigInt(request.trustedNowMilliseconds),
        request.revoked,
        ...scope.slice(1, 15),
      ));
    },
    useProjection: moon.strategyRemoteCredentialUseProjection,
  });
  remoteCredentialControls.set(moon, control);
  return control;
}

function remoteBundleControl(moon) {
  let control = remoteBundleControls.get(moon);
  if (control !== undefined) return control;
  control = Object.freeze({
    prepare: manifest => Array.isArray(manifest.components) ? checked(
      moon.strategyRemoteBundleManifestPrepareComponents(
        manifest.issuerAuthority,
        manifest.bundleName,
        manifest.revision,
        manifest.targetTriple,
        manifest.components.map(component =>
          moon.strategyRemoteBundleComponentPrepare(
            component.role,
            component.cid,
            BigInt(component.bytes),
          )),
        manifest.connectorRegistration,
        manifest.connectorRevision,
        manifest.strategyRevision,
      ),
    ) : checked(moon.strategyRemoteBundleManifestPrepare(
      manifest.issuerAuthority,
      manifest.bundleName,
      manifest.revision,
      manifest.targetTriple,
      manifest.componentCid,
      BigInt(manifest.componentBytes),
      manifest.connectorRegistration,
      manifest.connectorRevision,
      manifest.strategyRevision,
    )),
    identity: moon.strategyRemoteBundleManifestIdentity,
    json: manifest => checked(moon.strategyRemoteBundleManifestJson(manifest)),
    admitJson: (body, claimedCid) => checked(
      moon.strategyRemoteBundleManifestAdmitJson(body, claimedCid),
    ),
    projection: moon.strategyRemoteBundleManifestProjection,
    componentsProjection:
      moon.strategyRemoteBundleManifestComponentsProjection,
    signaturePreimage: manifest => checked(
      moon.strategyRemoteBundleSignaturePreimage(manifest),
    ),
    prepareSignatureEnvelope: (manifest, keyId, signature) => checked(
      moon.strategyRemoteBundleSignatureEnvelopePrepare(
        manifest,
        keyId,
        signature,
      ),
    ),
    admitSignatureEnvelope: envelope => checked(
      moon.strategyRemoteBundleSignatureEnvelopeAdmit(
        envelope.version,
        envelope.keyId,
        envelope.runtimeBundleCid,
        envelope.body,
        envelope.signature,
      ),
    ),
    signatureEnvelopeProjection:
      moon.strategyRemoteBundleSignatureEnvelopeProjection,
    signatureEnvelopeManifest:
      moon.strategyRemoteBundleSignatureEnvelopeManifest,
    open: moon.strategyRemoteBundleOpen,
    prepareActivation: (current, target) => checked(
      moon.strategyRemoteBundleActivationPrepare(current, target),
    ),
    activationTransitionCount:
      moon.strategyRemoteBundleActivationTransitionCount,
    activationTransitionAt: (activation, index) => checked(
      moon.strategyRemoteBundleActivationTransitionAt(activation, index),
    ),
    commitActivation: (activation, durable) => checked(
      moon.strategyRemoteBundleActivationCommit(activation, durable),
    ),
    prepareActivate: record => checked(
      moon.strategyRemoteBundleActivatePrepare(record),
    ),
    prepareDrain: record => checked(
      moon.strategyRemoteBundleDrainPrepare(record),
    ),
    prepareActiveDrain: (activeBundleCid, record) => checked(
      moon.strategyRemoteActiveBundleDrainPrepare(activeBundleCid, record),
    ),
    prepareRetain: (record, maxOwners) => checked(
      moon.strategyRemoteBundleRetainPrepare(record, maxOwners),
    ),
    prepareActiveRetain: (activeBundleCid, record, maxOwners) => checked(
      moon.strategyRemoteActiveBundleRetainPrepare(
        activeBundleCid,
        record,
        maxOwners,
      ),
    ),
    prepareRelease: record => checked(
      moon.strategyRemoteBundleReleasePrepare(record),
    ),
    prepareReclaim: record => checked(
      moon.strategyRemoteBundleReclaimPrepare(record),
    ),
    prepareInactiveReclaim: (activeBundleCid, record) => checked(
      moon.strategyRemoteInactiveBundleReclaimPrepare(
        activeBundleCid,
        record,
      ),
    ),
    transitionProjection: transition => tuplePair(
      moon.strategyRemoteBundleTransitionProjection(transition),
    ),
    transitionKey: moon.strategyRemoteBundleTransitionKey,
    commitTransition: (transition, durable) => checked(
      moon.strategyRemoteBundleTransitionCommit(transition, durable),
    ),
    recordProjection: moon.strategyRemoteBundleRecordProjection,
    restore: (manifest, state) => {
      if (!Array.isArray(state) || state.length !== 3 ||
          state.some(value => typeof value !== 'string') ||
          state.some(value => !/^(0|[1-9][0-9]*)$/.test(value))) {
        throw new TypeError('Invalid Remote Bundle state');
      }
      const values = state.map(Number);
      if (values.some(value => !Number.isSafeInteger(value))) {
        throw new TypeError('Invalid Remote Bundle state');
      }
      return checked(moon.strategyRemoteBundleRecordRestore(
        manifest,
        values[0],
        values[1],
        values[2],
      ));
    },
  });
  remoteBundleControls.set(moon, control);
  return control;
}

function publicationControl(moon) {
  let control = publicationControls.get(moon);
  if (control !== undefined) return control;
  const tokens = new WeakMap();
  const evidenceTokens = new WeakMap();
  const admissionTokens = new WeakMap();
  const snapshotTokens = new WeakMap();
  const effectSourceTokens = new WeakMap();
  const localEffectSourceTokens = new WeakMap();
  const localEffectArtifactTokens = new WeakMap();
  const localEffectIdentityTokens = new WeakMap();
  const localEffectManifestTokens = new WeakMap();
  const sourceAdvanceTokens = new WeakMap();
  const computationPreviewTokens = new WeakMap();
  const computationPreviewWires = new WeakMap();
  const inspect = contract => {
    const value = Object.freeze({
      name: moon.strategyPublicationContractName(contract),
      identityField: moon.strategyPublicationContractIdentityField(contract),
      identity: moon.strategyPublicationContractIdentity(contract),
      wire: moon.strategyPublicationContractJson(contract),
    });
    tokens.set(value, contract);
    return value;
  };
  const token = value => {
    const result = tokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign publication contract');
    }
    return result;
  };
  const inspectEvidence = evidence => {
    const value = Object.freeze({
      name: moon.strategyRunEvidenceName(evidence),
      identity: moon.strategyRunEvidenceIdentity(evidence),
      wire: moon.strategyRunEvidenceJson(evidence),
    });
    evidenceTokens.set(value, evidence);
    return value;
  };
  const evidenceToken = value => {
    const result = evidenceTokens.get(value);
    if (result === undefined) throw new TypeError('Foreign Run evidence');
    return result;
  };
  const inspectAdmission = admission => {
    const value = Object.freeze({kind: 'run-publication-admission'});
    admissionTokens.set(value, admission);
    return value;
  };
  const admissionToken = value => {
    const result = admissionTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign Run publication admission');
    }
    return result;
  };
  const inspectSnapshot = snapshot => {
    const value = Object.freeze({kind: 'captured-result-snapshot'});
    snapshotTokens.set(value, snapshot);
    return value;
  };
  const snapshotToken = value => {
    const result = snapshotTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign captured Result snapshot');
    }
    return result;
  };
  const inspectEffectSource = source => {
    const value = Object.freeze({kind: 'captured-effect-source-artifact'});
    effectSourceTokens.set(value, source);
    return value;
  };
  const effectSourceToken = value => {
    const result = effectSourceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign captured Effect source artifact');
    }
    return result;
  };
  const localEffectSourceToken = value => {
    const result = localEffectSourceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign local Effect source evidence');
    }
    return result;
  };
  const inspectSourceAdvance = advance => {
    const value = Object.freeze({kind: 'pending-source-state-advance'});
    sourceAdvanceTokens.set(value, advance);
    return value;
  };
  const sourceAdvanceToken = value => {
    const result = sourceAdvanceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign pending source-state advance');
    }
    return result;
  };
  const issuanceLimits = (limits, label) => {
    if (limits === null || typeof limits !== 'object' ||
        !Number.isSafeInteger(limits.maxWireBytes) ||
        !Number.isSafeInteger(limits.maxNodes) ||
        !Number.isSafeInteger(limits.maxDepth) ||
        limits.maxWireBytes < 0 || limits.maxNodes < 0 ||
        limits.maxDepth < 0) {
      throw new TypeError(`Invalid ${label} issuance limits`);
    }
    return limits;
  };
  control = Object.freeze({
    seal(name, bodyWire, limits) {
      return inspect(checked(moon.strategyPublicationSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admit(name, completeWire, limits) {
      return inspect(checked(moon.strategyPublicationAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    sealRunEvidence(name, bodyWire, limits) {
      issuanceLimits(limits, 'Run evidence');
      return inspectEvidence(checked(moon.strategyRunEvidenceSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitRunEvidence(name, completeWire, limits) {
      issuanceLimits(limits, 'Run evidence');
      return inspectEvidence(checked(moon.strategyRunEvidenceAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueRunInvocation(template, observation, limits) {
      issuanceLimits(limits, 'Run Invocation');
      return inspect(checked(moon.strategyIssueRunInvocation(
        evidenceToken(template),
        evidenceToken(observation),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitRunPublication(template, prepared, authorization, compiledPlan) {
      return inspectAdmission(checked(moon.strategyRunPublicationAdmit(
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      )));
    },
    admitCheckedClientRunPublication(
      checkedProgram, template, prepared, authorization, compiledPlan,
    ) {
      if (typeof moon.clientProgramAdmitPublication !== 'function') {
        throw new TypeError('Client Program admission is unavailable');
      }
      const admission = moon.clientProgramAdmitPublication(
        checkedProgram,
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      );
      if (admission === undefined) {
        throw new TypeError('Publication evidence differs from checked Program');
      }
      return inspectAdmission(admission);
    },
    checkClientRunDefinitionBinding(checkedProgram, admission, definition) {
      if (typeof moon.clientProgramCheckRunBinding !== 'function' ||
          !moon.clientProgramCheckRunBinding(checkedProgram,
            admissionToken(admission), token(definition))) {
        throw new TypeError('Run Definition differs from checked Program');
      }
    },
    admitCheckedClientEffectRunPublication(
      checkedEffect, template, prepared, authorization, compiledPlan,
    ) {
      if (typeof moon.clientProgramAdmitEffectPublication !== 'function') {
        throw new TypeError('Client Effect admission is unavailable');
      }
      const admission = moon.clientProgramAdmitEffectPublication(
        checkedEffect,
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      );
      if (admission === undefined) {
        throw new TypeError('Publication evidence differs from checked Effect');
      }
      return inspectAdmission(admission);
    },
    bindCheckedClientEffectRun(checkedEffect, admission, runDefinition) {
      if (typeof moon.clientProgramBindEffectRun !== 'function') {
        throw new TypeError('Client Effect Run binding is unavailable');
      }
      const bound = moon.clientProgramBindEffectRun(
        checkedEffect, admissionToken(admission), token(runDefinition));
      if (bound === undefined) {
        throw new TypeError('Run Definition differs from checked Effect');
      }
      return bound;
    },
    issueRunDefinition(admission, definition, limits) {
      issuanceLimits(limits, 'Run Definition');
      if (definition === null || typeof definition !== 'object') {
        throw new TypeError('Invalid Run Definition request');
      }
      return inspect(checked(moon.strategyIssueRunDefinition(
        admissionToken(admission),
        definition.scopeId,
        definition.runId,
        definition.inputArtifactSetCid,
        definition.createdAt,
        definition.validUntil,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueEffectFreeRunReceipt(chain, provenance, limits) {
      issuanceLimits(limits, 'Run Receipt');
      if (chain === null || typeof chain !== 'object' ||
          provenance === null || typeof provenance !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(provenance.bindings) ||
          !Array.isArray(provenance.sourceEvidence) ||
          !Array.isArray(provenance.modelEvidence) ||
          !Array.isArray(provenance.barrierAttemptReceiptCids)) {
        throw new TypeError('Invalid Run Receipt request');
      }
      return inspect(checked(moon.strategyIssueEffectFreeRunReceipt(
        admissionToken(chain.admission),
        token(chain.runDefinition),
        token(chain.invocation),
        evidenceToken(chain.observation),
        chain.definitions.map(token),
        chain.artifacts.map(token),
        token(chain.manifest),
        evidenceToken(provenance.normalizationJournal),
        provenance.bindings.map(binding => binding.name),
        provenance.bindings.map(binding => binding.sha256),
        provenance.sourceEvidence.map(evidenceToken),
        provenance.modelEvidence.map(evidenceToken),
        provenance.barrierAttemptReceiptCids,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitCapturedResultSnapshot(definition, artifact, rowsWire, fields,
      limits) {
      issuanceLimits(limits, 'Captured Result snapshot');
      if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
          fields.some(field => typeof field !== 'string')) {
        throw new TypeError('Invalid Captured Result snapshot');
      }
      return inspectSnapshot(checked(
        moon.strategyAdmitCapturedResultSnapshot(
          token(definition),
          token(artifact),
          rowsWire,
          fields,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    admitCapturedEffectSourceArtifact(preview, memberIndex, invocation,
      artifact, storeAuthorityCid) {
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid captured Effect source artifact');
      }
      return inspectEffectSource(checked(
        moon.strategyAdmitCapturedEffectSourceArtifact(
          ownedPreview, memberIndex, token(invocation), token(artifact),
          storeAuthorityCid,
        ),
      ));
    },
    issueEffectSourceArtifactFromExport(input, receipt, invocation,
      retention, sourceBindingCid, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'Effect source Artifact');
      if (typeof moon.clientProgramIssueEffectSourceArtifact !== 'function' ||
          typeof sourceBindingCid !== 'string' ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid Effect source Artifact export');
      }
      return inspect(checked(moon.clientProgramIssueEffectSourceArtifact(
        input, receipt, token(invocation), token(retention),
        sourceBindingCid, storeAuthorityCid, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      )));
    },
    issueSourceFreeLocalEffectResultArtifact(owner, inputs, memberIndex,
      importing, definition, localInvocation, receipt, retention, context,
      limits) {
      issuanceLimits(limits, 'local Effect Result Artifact');
      if (!Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          context === null || typeof context !== 'object' ||
          !['admission', 'runDefinition', 'runInvocation', 'observation']
            .every(key => context[key] !== undefined)) {
        throw new TypeError('Invalid local Effect Result Artifact');
      }
      const issued = checked(
        moon.clientProgramIssueSourceFreeLocalEffectResultArtifact(
          owner, inputs, memberIndex, importing, definition, localInvocation,
          receipt, token(retention), admissionToken(context.admission),
          token(context.runDefinition), token(context.runInvocation),
          evidenceToken(context.observation),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        identity: moon.clientProgramLocalEffectResultArtifactCid(issued),
        wire: moon.clientProgramLocalEffectResultArtifactJson(issued),
        derivationWire:
          moon.clientProgramLocalEffectResultDerivationJson(issued),
        orderingWire: moon.clientProgramLocalEffectResultOrderingJson(issued),
      });
      localEffectArtifactTokens.set(value, issued);
      return value;
    },
    issueLocalEffectResultManifest(owner, invocation, artifacts, limits) {
      issuanceLimits(limits, 'local Effect Result Manifest');
      if (!Array.isArray(artifacts) || artifacts.length === 0) {
        throw new TypeError('Invalid local Effect Result Manifest');
      }
      const owned = artifacts.map(artifact => {
        const token = localEffectArtifactTokens.get(artifact);
        if (token === undefined) {
          throw new TypeError('Foreign local Effect Result Artifact');
        }
        return token;
      });
      const issued = checked(moon.clientProgramIssueLocalEffectResultManifest(
        owner, invocation, owned, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const value = Object.freeze({
        identity: moon.clientProgramLocalEffectResultManifestCid(issued),
        wire: moon.clientProgramLocalEffectResultManifestJson(issued),
      });
      localEffectManifestTokens.set(value, issued);
      return value;
    },
    localEffectSourceMatches(owner, inputs, memberIndex, manifest,
      invocation, artifact, source) {
      const ownedManifest = localEffectManifestTokens.get(manifest);
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedManifest === undefined || ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign local Effect source evidence');
      }
      return moon.clientProgramLocalEffectSourceMatches(
        owner, inputs, memberIndex, ownedManifest, invocation,
        ownedArtifact, effectSourceToken(source));
    },
    admitLocalEffectSourceEvidence(owner, inputs, memberIndex, manifest,
      invocation, artifact, source, limits) {
      issuanceLimits(limits, 'local Effect source evidence');
      const ownedManifest = localEffectManifestTokens.get(manifest);
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedManifest === undefined || ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign local Effect source evidence');
      }
      const issued = checked(moon.clientProgramAdmitLocalEffectSourceEvidence(
        owner, inputs, memberIndex, ownedManifest, invocation,
        ownedArtifact, effectSourceToken(source), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({kind: 'captured-local-effect-source'});
      localEffectSourceTokens.set(value, issued);
      return value;
    },
    issueSourceFreeLocalEffectIdentity(owner, inputs, memberIndex, artifact,
      limits) {
      issuanceLimits(limits, 'local Effect identity');
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          !Number.isSafeInteger(limits.maxWork) || limits.maxWork < 1) {
        throw new TypeError('Invalid local Effect identity owner');
      }
      const issued = checked(
        moon.clientProgramIssueSourceFreeLocalEffectIdentity(
          owner, inputs, memberIndex, ownedArtifact, limits.maxWork,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        identity: moon.clientProgramLocalEffectIdentityCid(issued),
        wire: moon.clientProgramLocalEffectIdentityJson(issued),
      });
      localEffectIdentityTokens.set(value, issued);
      return value;
    },
    checkSourceFreeLocalEffectPreviewIdentities(owner, inputs, wire,
      runIdentityCid, authoringContextCid, identities, limits) {
      issuanceLimits(limits, 'local Effect Preview identities');
      if (typeof wire !== 'string' ||
          typeof runIdentityCid !== 'string' ||
          typeof authoringContextCid !== 'string' ||
          !Array.isArray(identities)) {
        throw new TypeError('Invalid local Effect Preview identities');
      }
      const owned = identities.map(identity => {
        const token = localEffectIdentityTokens.get(identity);
        if (token === undefined) {
          throw new TypeError('Foreign local Effect identity');
        }
        return token;
      });
      return checked(
        moon.clientProgramCheckSourceFreeLocalEffectPreviewIdentities(
          owner, inputs, wire, runIdentityCid, authoringContextCid, owned,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    effectSourceArtifactPreviewBinding(artifact, invocationCid, sourceResult,
      storeAuthorityCid) {
      return checked(moon.clientProgramEffectSourceArtifactPreviewBinding(
        token(artifact), invocationCid, sourceResult, storeAuthorityCid));
    },
    capturedEffectSourceHoldingCid(source) {
      return moon.strategyCapturedEffectSourceHoldingCid(
        effectSourceToken(source));
    },
    capturedEffectSourceArtifactCid(source) {
      return moon.strategyCapturedEffectSourceArtifactCid(
        effectSourceToken(source));
    },
    capturedEffectSourceStoreAuthorityCid(source) {
      return moon.strategyCapturedEffectSourceStoreAuthorityCid(
        effectSourceToken(source));
    },
    admitCompletedResultSnapshot(exportHandle, limits) {
      issuanceLimits(limits, 'completed Result snapshot');
      return inspectSnapshot(checked(
        moon.strategyHostOutputExportAdmitCapturedResultSnapshot(
          exportHandle,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    admitPendingSourceStateAdvance(completeWire, observation, limits) {
      issuanceLimits(limits, 'pending source-state advance');
      if (typeof completeWire !== 'string') {
        throw new TypeError('Invalid pending source-state advance');
      }
      return inspectSourceAdvance(checked(
        moon.strategyAdmitPendingSourceStateAdvance(
          completeWire,
          evidenceToken(observation),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    issueEffectFreeCapturedRun(chain, evidence, limits) {
      issuanceLimits(limits, 'Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence)) {
        throw new TypeError('Invalid Captured Run request');
      }
      return inspect(checked(moon.strategyIssueEffectFreeCapturedRun(
        token(chain.runDefinition),
        token(chain.invocation),
        chain.definitions.map(token),
        chain.artifacts.map(token),
        token(chain.manifest),
        token(chain.receipt),
        evidence.snapshots.map(snapshotToken),
        evidence.pendingSourceStateAdvances.map(sourceAdvanceToken),
        evidenceToken(evidence.authoringContext),
        evidence.modelEvidence.map(evidenceToken),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitEffectComputationPreview(wire, runDefinition, authoring, limits) {
      issuanceLimits(limits, 'Effect computation Preview');
      if (typeof wire !== 'string' ||
          typeof authoring?.identity !== 'string') {
        throw new TypeError('Invalid Effect computation Preview');
      }
      token(runDefinition);
      evidenceToken(authoring);
      const preview = checked(moon.strategyAdmitEffectComputationPreview(
        wire, runDefinition.identity,
        authoring.identity,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      ));
      const owned = Object.freeze({kind: 'effect-computation-preview'});
      computationPreviewTokens.set(owned, preview);
      computationPreviewWires.set(owned, wire);
      return owned;
    },
    effectComputationPreviewLedgerIdentity(preview) {
      const admitted = computationPreviewTokens.get(preview);
      if (admitted === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return admitted;
    },
    effectComputationPreviewSemanticCid(preview) {
      const admitted = computationPreviewTokens.get(preview);
      if (admitted === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return moon.strategyEffectPreviewSemanticCid(admitted);
    },
    effectComputationPreviewWire(preview) {
      const wire = computationPreviewWires.get(preview);
      if (wire === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return wire;
    },
    effectPrivateEvidenceBinding(preview, storeAuthorityCid) {
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return Object.freeze({
        name: 'effect_preview',
        semanticCid: moon.strategyEffectPreviewSemanticCid(ownedPreview),
        holdingCid: checked(moon.strategyEffectPreviewPrivateHoldingCid(
          ownedPreview, storeAuthorityCid,
        )),
        wire: computationPreviewWires.get(preview),
      });
    },
    effectComputationCaptureHoldingCid(runDefinition, storeAuthorityCid) {
      if (typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid Effect computation capture holding');
      }
      return checked(moon.strategyEffectComputationCaptureHoldingCid(
        token(runDefinition), storeAuthorityCid,
      ));
    },
    effectComputationRecordHoldingCid(runDefinition, storeAuthorityCid) {
      if (typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid Effect computation record holding');
      }
      return checked(moon.strategyEffectComputationRecordHoldingCid(
        token(runDefinition), storeAuthorityCid,
      ));
    },
    effectfulComputationEvidenceChainValid(chain, preview, limits) {
      issuanceLimits(limits, 'Effectful computation evidence chain');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(chain?.definitions) ||
          !Array.isArray(chain.artifacts)) {
        throw new TypeError('Invalid Effectful computation evidence chain');
      }
      return moon.strategyEffectfulComputationEvidenceChainValid(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), ownedPreview,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      );
    },
    capturedEffectSourceRecoveryInventoryValid(preview, sources) {
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources) ||
          sources.some(value => !Number.isSafeInteger(value?.memberIndex))) {
        throw new TypeError('Invalid recovered Effect source inventory');
      }
      return moon.strategyCapturedEffectSourceRecoveryInventoryValid(
        ownedPreview, sources.map(value => value.memberIndex),
        sources.map(value => token(value.artifact)),
      );
    },
    issueEffectfulCapturedRun(chain, evidence, preview, plans, limits) {
      issuanceLimits(limits, 'Effectful Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.effectSources) ||
          !Array.isArray(evidence.localEffectSources) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence) ||
          !Array.isArray(plans) ||
          plans.some(value => !value || typeof value.name !== 'string' ||
            typeof value.wire !== 'string')) {
        throw new TypeError('Invalid Effectful Captured Run request');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return inspect(checked(moon.strategyIssueEffectfulCapturedRun(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.receipt),
        evidence.snapshots.map(snapshotToken),
        evidence.effectSources.map(effectSourceToken),
        evidence.localEffectSources.map(localEffectSourceToken),
        evidence.pendingSourceStateAdvances.map(sourceAdvanceToken),
        evidenceToken(evidence.authoringContext),
        evidence.modelEvidence.map(evidenceToken), ownedPreview,
        plans.map(value => value.name), plans.map(value => value.wire),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      )));
    },
    issueEffectfulFinalRunReceipt(chain, preview, receipts, limits) {
      issuanceLimits(limits, 'final Effectful Run Receipt');
      if (chain === null || typeof chain !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          receipts === null || typeof receipts !== 'object' ||
          typeof receipts.setWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string')) {
        throw new TypeError('Invalid final Effectful Run Receipt');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return inspect(checked(moon.strategyIssueEffectfulFinalRunReceipt(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), ownedPreview, receipts.setWire,
        receipts.memberWires, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueEffectSetApplyReceiptFromMembers(preview, members, replayed, limits) {
      issuanceLimits(limits, 'Effect Set Apply Receipt');
      if (!Array.isArray(members) ||
          members.some(member => typeof member?.wire !== 'string') ||
          !Array.isArray(replayed) ||
          replayed.some(value => typeof value !== 'boolean')) {
        throw new TypeError('Invalid Effect Set Apply Receipt request');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return inspect(checked(
        moon.strategyIssueEffectSetApplyReceiptFromMembers(
          ownedPreview, members.map(member => member.wire), replayed,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        ),
      ));
    },
    effectSetReceiptRunDisposition(preview, receipts, limits) {
      issuanceLimits(limits, 'Effect Set Run disposition');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined ||
          typeof receipts?.setWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string')) {
        throw new TypeError('Invalid Effect Set Run disposition');
      }
      return checked(moon.strategyEffectSetReceiptRunDisposition(
        ownedPreview, receipts.setWire, receipts.memberWires,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      ));
    },
    // The public state of a Run whose complete admitted Effect Set has
    // unknown outcomes: `needs_reconciliation` naming exactly those Effects.
    effectReconciliationRunState(preview, receipts, {runId, updatedAt,
      resultNames}, limits) {
      issuanceLimits(limits, 'Effect reconciliation Run state');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined ||
          typeof receipts?.setWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string') ||
          !Array.isArray(resultNames) ||
          resultNames.some(name => typeof name !== 'string')) {
        throw new TypeError('Invalid Effect reconciliation Run state');
      }
      return checked(moon.strategyEffectReconciliationRunState(
        ownedPreview, receipts.setWire, receipts.memberWires, runId,
        updatedAt, resultNames, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth,
      ));
    },
    recordTransition(previous, next, uncommittedConfirmed) {
      return moon.strategyPublicationRecordTransition(
        previous === undefined ? undefined : token(previous),
        token(next),
        uncommittedConfirmed,
      );
    },
    recordAllowsCommit(record) {
      return moon.strategyPublicationRecordAllowsCommit(token(record));
    },
    publicationAttemptAction(record, activeChecked, indexIssued) {
      return moon.strategyPublicationAttemptAction(
        record === undefined ? undefined : token(record),
        activeChecked,
        indexIssued,
      );
    },
    publicationSetupAction(
      existingChecked,
      existingFound,
      existingEvidenceValidated,
      existingFinalized,
      initialActiveChecked,
      contractsPersisted,
      attemptCreated,
    ) {
      return moon.strategyPublicationSetupAction(
        existingChecked,
        existingFound,
        existingEvidenceValidated,
        existingFinalized,
        initialActiveChecked,
        contractsPersisted,
        attemptCreated,
      );
    },
    publicationCancellationAction(record) {
      return moon.strategyPublicationCancellationAction(
        record === undefined ? undefined : token(record),
      );
    },
    committedPublicationFinalizationAction(record) {
      return moon.strategyCommittedPublicationFinalizationAction(
        record === undefined ? undefined : token(record),
      );
    },
    supersededPublicationFinalizationAction(record) {
      return moon.strategySupersededPublicationFinalizationAction(
        record === undefined ? undefined : token(record),
      );
    },
    publicationCommitFailureAction(
      reconciliationAttempted,
      reconciliationFailed,
      committedFound,
      unknownAppendAttempted,
    ) {
      return moon.strategyPublicationCommitFailureAction(
        reconciliationAttempted,
        reconciliationFailed,
        committedFound,
        unknownAppendAttempted,
      );
    },
    publicationUnknownRetryAction(
      reconciliationResolved,
      upstreamPending,
      upstreamRetryAvailable,
      upstreamRetryAttempted,
    ) {
      return moon.strategyPublicationUnknownRetryAction(
        reconciliationResolved,
        upstreamPending,
        upstreamRetryAvailable,
        upstreamRetryAttempted,
      );
    },
    existingDeliveryAttemptAction(record) {
      return publicationAction('existingDelivery',
        moon.strategyExistingDeliveryAttemptAction(
          record === undefined ? undefined : token(record),
        ));
    },
    beginResultAccessProgress() {
      return moon.strategyBeginResultAccessProgress();
    },
    resultAccessProgressAction(progress) {
      return publicationAction('resultAccess',
        moon.strategyResultAccessProgressAction(progress));
    },
    recordResultAccessRequestAuthorization(progress, authorized) {
      if (!moon.strategyRecordResultAccessRequestAuthorization(
        progress, authorized,
      )) throw new TypeError('Invalid Result access progression');
    },
    recordResultAccessResolution(progress, resolved) {
      if (!moon.strategyRecordResultAccessResolution(progress, resolved)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    recordResultAccessInitialAvailability(progress, available) {
      if (!moon.strategyRecordResultAccessInitialAvailability(
        progress, available,
      )) throw new TypeError('Invalid Result access progression');
    },
    recordResultAccessReadAdmission(progress, admitted) {
      if (!moon.strategyRecordResultAccessReadAdmission(progress, admitted)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    recordResultAccessGrant(progress, issued) {
      if (!moon.strategyRecordResultAccessGrant(progress, issued)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    deliveryFailureTerminalAction(cancellationObserved) {
      return publicationAction('failureTerminal',
        moon.strategyDeliveryFailureTerminalAction(cancellationObserved));
    },
    deliveryRecordRetryAction(nextRecord, recordCount) {
      return publicationAction('recordRetry',
        moon.strategyDeliveryRecordRetryAction(nextRecord, recordCount));
    },
    publicationPreparedReleaseAction(
      currentIndex,
      ownerCount,
      statusChecked,
      pending,
      releaseAttempted,
    ) {
      return moon.strategyPublicationPreparedReleaseAction(
        currentIndex,
        ownerCount,
        statusChecked,
        pending,
        releaseAttempted,
      );
    },
    publicationCleanupOwnerAction(
      currentIndex,
      ownerCount,
      statusChecked,
      pending,
      retryAvailable,
      retryAttempted,
    ) {
      return moon.strategyPublicationCleanupOwnerAction(
        currentIndex,
        ownerCount,
        statusChecked,
        pending,
        retryAvailable,
        retryAttempted,
      );
    },
    runChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, limits) {
      return moon.strategyRunPublicationChainValid(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        token(manifest),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      );
    },
    issueResultManifest(runDefinition, invocation, definitions, artifacts,
      limits) {
      issuanceLimits(limits, 'Result Manifest');
      return inspect(checked(moon.strategyIssueResultManifest(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueDurableResultBinding(chain, physical, limits) {
      issuanceLimits(limits, 'durable Result binding');
      if (chain === null || typeof chain !== 'object' ||
          physical === null || typeof physical !== 'object') {
        throw new TypeError('Invalid durable Result binding request');
      }
      return inspect(checked(moon.strategyIssueDurableResultBinding(
        token(chain.runDefinition),
        token(chain.definition),
        token(chain.invocation),
        token(chain.artifact),
        token(chain.ordering),
        token(chain.retention),
        physical.codecContractCid,
        physical.resultFields,
        physical.resultSchemaWire,
        physical.materialGenerationCid,
        physical.storeAuthorityCid,
        physical.rowCount,
        physical.byteCount,
        physical.physicalSha256,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issuePublicationRequest(runDefinition, definitions, intent, limits) {
      issuanceLimits(limits, 'Publication Request');
      if (intent === null || typeof intent !== 'object') {
        throw new TypeError('Invalid Publication Request intent');
      }
      return inspect(checked(moon.strategyIssuePublicationRequest(
        token(runDefinition),
        definitions.map(token),
        intent.tenantId,
        intent.authorityScopeCid,
        intent.publicationPolicyCid,
        intent.publicationTargetCid,
        intent.requestedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issuePublicationAttempt(request, runDefinition, attempt, limits) {
      issuanceLimits(limits, 'Publication Attempt');
      if (attempt === null || typeof attempt !== 'object') {
        throw new TypeError('Invalid Publication Attempt');
      }
      return inspect(checked(moon.strategyIssuePublicationAttempt(
        token(request),
        token(runDefinition),
        attempt.attemptId,
        attempt.fenceCid,
        attempt.externalIdempotencyKey,
        attempt.startedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    publicationPreflightValid(
      admission,
      runDefinition,
      invocation,
      definitions,
      retentions,
      evidenceContexts,
      request,
      attempt,
      programDefinitionCid,
    ) {
      return moon.strategyPublicationPreflightValid(
        admissionToken(admission),
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        retentions.map(token),
        evidenceContexts.map(value => value.computationContractCid),
        evidenceContexts.map(value => value.inputRelationCids),
        evidenceContexts.map(value => value.scopeCid),
        evidenceContexts.map(value => value.effectiveDataPolicyCid),
        evidenceContexts.map(value => value.authorityScopeCid),
        token(request),
        token(attempt),
        programDefinitionCid,
      );
    },
    issuePublicIndexEntry(chain, committedAt, limits) {
      issuanceLimits(limits, 'Public Index Entry');
      if (chain === null || typeof chain !== 'object' ||
          !Array.isArray(chain.durableBindings)) {
        throw new TypeError('Invalid publication chain');
      }
      return inspect(checked(moon.strategyIssuePublicIndexEntry(
        token(chain.runDefinition),
        token(chain.invocation),
        token(chain.manifest),
        token(chain.receipt),
        token(chain.capturedRun),
        chain.durableBindings.map(token),
        token(chain.request),
        token(chain.attempt),
        committedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    publicIndexSameCommittedContent(committed, candidate) {
      return moon.strategyPublicIndexSameCommittedContent(
        token(committed), token(candidate));
    },
    issuePublicationRecord(attempt, previous, update, limits) {
      issuanceLimits(limits, 'Publication Record');
      if (update === null || typeof update !== 'object') {
        throw new TypeError('Invalid Publication Record update');
      }
      return inspect(checked(moon.strategyIssuePublicationRecord(
        token(attempt),
        previous === undefined ? undefined : token(previous),
        update.state,
        update.observedAt,
        update.publicIndexEntry === undefined
          ? undefined : token(update.publicIndexEntry),
        update.failureCid,
        update.cleanupOwnerCids,
        update.uncommittedConfirmed,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    effectFreeChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, receipt, capturedRun, limits) {
      return moon.strategyEffectFreeRunEvidenceChainValid(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        token(manifest),
        token(receipt),
        token(capturedRun),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      );
    },
    effectFreeCommitValid(runDefinition, invocation, definitions, artifacts,
      derivations, orderings, retentions, durableBindings, manifest, receipt,
      capturedRun, request, attempt, indexEntry, limits) {
      return moon.strategyEffectFreePublicationCommitValid(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        derivations.map(token),
        orderings.map(token),
        retentions.map(token),
        durableBindings.map(token),
        token(manifest),
        token(receipt),
        token(capturedRun),
        token(request),
        token(attempt),
        token(indexEntry),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      );
    },
    effectfulCommitValid(chain, preview, receipts, request, attempt,
      indexEntry, limits) {
      issuanceLimits(limits, 'Effectful publication commit');
      if (chain === null || typeof chain !== 'object' ||
          !['definitions', 'artifacts', 'derivations', 'orderings',
            'retentions', 'durableBindings'].every(name =>
            Array.isArray(chain[name])) ||
          receipts === null || typeof receipts !== 'object' ||
          typeof receipts.setWire !== 'string' ||
          typeof receipts.finalWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string')) {
        throw new TypeError('Invalid Effectful publication commit');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return moon.strategyEffectfulPublicationCommitValid(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        chain.derivations.map(token), chain.orderings.map(token),
        chain.retentions.map(token), chain.durableBindings.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), ownedPreview, receipts.setWire,
        receipts.memberWires, receipts.finalWire, token(request),
        token(attempt), token(indexEntry), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      );
    },
    issueResultArtifact(exportHandle, invocation, retention, limits) {
      issuanceLimits(limits, 'Result Artifact');
      return inspect(checked(
        moon.strategyHostOutputExportIssueResultArtifact(
          exportHandle,
          token(invocation),
          token(retention),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    deliveryTransition(previous, next) {
      return moon.strategyDeliveryRecordTransition(
        previous === undefined ? undefined : token(previous),
        token(next),
      );
    },
    deliverySuccessValid(attempt, receipt, record) {
      return moon.strategyDeliverySuccessValid(
        token(attempt), token(receipt), token(record),
      );
    },
    resultSerializationContractCid(format, limits) {
      issuanceLimits(limits, 'Result serialization');
      return checked(moon.strategyResultSerializationContractCid(
        format,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
    },
    issueManifestReadGrant(index, manifest, grant, limits) {
      issuanceLimits(limits, 'Manifest read grant');
      if (grant === null || typeof grant !== 'object') {
        throw new TypeError('Invalid Manifest read grant');
      }
      return inspect(checked(moon.strategyIssueManifestReadGrant(
        token(index),
        token(manifest),
        grant.principalId,
        grant.purpose,
        grant.dataCeilingCid,
        grant.maxBytes,
        grant.maxUses,
        grant.expiresAt,
        grant.authorizationContextCid,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueResultReadGrant(index, manifest, grant, limits) {
      issuanceLimits(limits, 'Result read grant');
      if (grant === null || typeof grant !== 'object' ||
          !Array.isArray(grant.resultNames) ||
          !Array.isArray(grant.formats)) {
        throw new TypeError('Invalid Result read grant');
      }
      return inspect(checked(moon.strategyIssueResultReadGrant(
        token(index),
        token(manifest),
        grant.resultNames,
        grant.formats,
        grant.principalId,
        grant.purpose,
        grant.dataCeilingCid,
        grant.maxBytes,
        grant.maxUses,
        grant.expiresAt,
        grant.authorizationContextCid,
        grant.egressAdmissionCid,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueDeliveryAttempt(index, manifest, grant, attempt, limits) {
      issuanceLimits(limits, 'Delivery Attempt');
      if (attempt === null || typeof attempt !== 'object') {
        throw new TypeError('Invalid Delivery Attempt');
      }
      return inspect(checked(moon.strategyIssueDeliveryAttempt(
        token(index),
        token(manifest),
        token(grant),
        attempt.resultName,
        attempt.format,
        attempt.attemptId,
        attempt.requestedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    deliveryResultDefinitionCid(manifest, attempt) {
      return checked(moon.strategyDeliveryResultDefinitionCid(
        token(manifest),
        token(attempt),
      ));
    },
    resultReadRetentionPolicyCid(manifest, resultName) {
      if (typeof resultName !== 'string') {
        throw new TypeError('Invalid Result retention request');
      }
      return checked(moon.strategyResultReadRetentionPolicyCid(
        token(manifest), resultName,
      ));
    },
    manifestResultNames(manifest, limits) {
      issuanceLimits(limits, 'Manifest Result inventory');
      const wire = checked(moon.strategyManifestResultNames(
        token(manifest),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
      let names;
      try { names = JSON.parse(wire); }
      catch (error) {
        throw new TypeError('Invalid Manifest Result inventory', {cause: error});
      }
      if (!Array.isArray(names)) {
        throw new TypeError('Invalid Manifest Result inventory');
      }
      return Object.freeze([...names]);
    },
    resultReadDefinitionCid(manifest, resultName) {
      if (typeof resultName !== 'string') {
        throw new TypeError('Invalid Result definition request');
      }
      return checked(moon.strategyResultReadDefinitionCid(
        token(manifest), resultName,
      ));
    },
    runDefinitionRunId(runDefinition) {
      return checked(moon.strategyRunDefinitionRunId(token(runDefinition)));
    },
    resultReadAvailability(manifest, resultName, retention, observedAt) {
      if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
        throw new TypeError('Invalid Result availability request');
      }
      return checked(moon.strategyResultReadAvailability(
        token(manifest), resultName, token(retention), observedAt,
      ));
    },
    resultMetadataRetentionState(retention, observedAt) {
      if (typeof observedAt !== 'string') {
        throw new TypeError('Invalid Result metadata retention request');
      }
      return checked(moon.strategyResultMetadataRetentionState(
        token(retention), observedAt,
      ));
    },
    issueResultRetentionExtension(
      base, availableUntil, admittedAt, limits,
    ) {
      issuanceLimits(limits, 'Result retention extension');
      if (typeof availableUntil !== 'string' ||
          typeof admittedAt !== 'string') {
        throw new TypeError('Invalid Result retention extension');
      }
      return inspect(checked(moon.strategyIssueResultRetentionExtension(
        token(base),
        availableUntil,
        admittedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    resultReadExtendedAvailability(
      manifest, resultName, base, extension, observedAt,
    ) {
      if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
        throw new TypeError('Invalid extended Result availability request');
      }
      return checked(moon.strategyResultReadExtendedAvailability(
        token(manifest),
        resultName,
        token(base),
        token(extension),
        observedAt,
      ));
    },
    resultRetentionClockContractCid(retention) {
      return checked(moon.strategyResultRetentionClockContractCid(
        token(retention),
      ));
    },
    trustedClockNotBefore(previous, observedAt) {
      if (previous !== undefined && typeof previous !== 'string' ||
          typeof observedAt !== 'string') {
        return false;
      }
      return moon.strategyTrustedClockNotBefore(previous, observedAt);
    },
    projectCommittedPublicationState(record, index) {
      return checked(moon.strategyPublicationSnapshotState(
        record === undefined ? undefined : token(record),
        token(index),
      ));
    },
    issueSucceededRunState(request, limits) {
      issuanceLimits(limits, 'Succeeded Run state');
      if (request === null || typeof request !== 'object' ||
          typeof request.runId !== 'string' ||
          typeof request.updatedAt !== 'string' ||
          !Array.isArray(request.declaredResults) ||
          !Array.isArray(request.observations)) {
        throw new TypeError('Invalid succeeded Run state');
      }
      const names = [];
      const states = [];
      const reasons = [];
      const observedAt = [];
      for (const observation of request.observations) {
        if (observation === null || typeof observation !== 'object' ||
            typeof observation.name !== 'string' ||
            typeof observation.state !== 'string' ||
            typeof observation.reason !== 'string' ||
            typeof observation.observedAt !== 'string') {
          throw new TypeError('Invalid Result availability observation');
        }
        names.push(observation.name);
        states.push(observation.state);
        reasons.push(observation.reason);
        observedAt.push(observation.observedAt);
      }
      return checked(moon.strategyIssueSucceededRunState(
        request.runId,
        request.updatedAt,
        request.declaredResults,
        names,
        states,
        reasons,
        observedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
    },
    resultReadGrantAllowsBytes(grant, byteCount) {
      if (!Number.isSafeInteger(byteCount) || byteCount < 0) return false;
      return moon.strategyResultReadGrantAllowsBytes(
        token(grant), byteCount,
      );
    },
    manifestReadGrantAllowsBytes(grant, byteCount) {
      if (!Number.isSafeInteger(byteCount) || byteCount < 0) return false;
      return moon.strategyManifestReadGrantAllowsBytes(
        token(grant), byteCount,
      );
    },
    manifestReadGrantValidAt(grant, observedAt) {
      if (typeof observedAt !== 'string') return false;
      return moon.strategyManifestReadGrantValidAt(
        token(grant), observedAt,
      );
    },
    resultReadGrantValidAt(grant, observedAt) {
      if (typeof observedAt !== 'string') return false;
      return moon.strategyResultReadGrantValidAt(
        token(grant), observedAt,
      );
    },
    issueResultDeliveryReceipt(index, manifest, grant, attempt, delivered,
      limits) {
      issuanceLimits(limits, 'Result delivery receipt');
      if (delivered === null || typeof delivered !== 'object') {
        throw new TypeError('Invalid Result delivery receipt');
      }
      return inspect(checked(moon.strategyIssueResultDeliveryReceipt(
        token(index),
        token(manifest),
        token(grant),
        token(attempt),
        delivered.byteCount,
        delivered.sha256,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueDeliveryRecord(attempt, previous, update, limits) {
      issuanceLimits(limits, 'Delivery Record');
      if (update === null || typeof update !== 'object' ||
          !Array.isArray(update.cleanupOwnerCids)) {
        throw new TypeError('Invalid Delivery Record');
      }
      return inspect(checked(moon.strategyIssueDeliveryRecord(
        token(attempt),
        previous === undefined ? undefined : token(previous),
        update.state,
        update.confirmedByteCount,
        update.exposure,
        update.possibleUnconfirmedMaxBytes,
        update.deliveredSha256,
        update.receipt === undefined ? undefined : token(update.receipt),
        update.failureCid,
        update.observedAt,
        update.cleanupOwnerCids,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    prepareResultDeliverySerializer(format, schemaWire, fields, limits) {
      issuanceLimits(limits, 'Result delivery serializer');
      if (typeof schemaWire !== 'string' || !Array.isArray(fields)) {
        throw new TypeError('Invalid Result delivery serializer');
      }
      return checked(moon.strategyPrepareResultDeliverySerializer(
        format,
        schemaWire,
        fields,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
    },
    beginResultDelivery(serializer) {
      return checked(moon.strategyBeginResultDelivery(serializer));
    },
    nextResultDeliveryRow(serializer, rowWire) {
      if (typeof rowWire !== 'string') {
        throw new TypeError('Invalid Result delivery row');
      }
      return checked(moon.strategyNextResultDeliveryRow(serializer, rowWire));
    },
    finishResultDelivery(serializer) {
      return checked(moon.strategyFinishResultDelivery(serializer));
    },
    prepareDurableResultRowFrames(limits) {
      if (limits === null || typeof limits !== 'object' ||
          !Number.isSafeInteger(limits.maxBytes) || limits.maxBytes < 0 ||
          !Number.isSafeInteger(limits.maxRows) || limits.maxRows < 0 ||
          !Number.isSafeInteger(limits.maxRowBytes) ||
          limits.maxRowBytes < 1 ||
          !Number.isSafeInteger(limits.maxDepth) || limits.maxDepth < 1 ||
          !Number.isSafeInteger(limits.maxFrameBytes) ||
          limits.maxFrameBytes < 1) {
        throw new TypeError('Invalid durable Result row-frame limits');
      }
      return checked(moon.strategyPrepareDurableResultRowFrames(
        limits.maxBytes,
        limits.maxRows,
        limits.maxRowBytes,
        limits.maxDepth,
        limits.maxFrameBytes,
      ));
    },
    feedDurableResultRowFrames(frames, chunk) {
      if (!(chunk instanceof Uint8Array)) {
        throw new TypeError('Invalid durable Result row-frame chunk');
      }
      return checked(moon.strategyFeedDurableResultRowFrames(frames, chunk));
    },
    finishDurableResultRowFrames(frames) {
      const summary = checked(
        moon.strategyFinishDurableResultRowFrames(frames),
      );
      if (!Array.isArray(summary) || summary.length !== 2 ||
          summary.some(value => !Number.isSafeInteger(value) || value < 0)) {
        throw new TypeError('Invalid durable Result row-frame summary');
      }
      return Object.freeze({bytes: summary[0], rows: summary[1]});
    },
    cancelDurableResultRowFrames(frames) {
      moon.strategyCancelDurableResultRowFrames(frames);
    },
  });
  publicationControls.set(moon, control);
  return control;
}

function outputExportControl(moon, publications) {
  const evidenceFields = [
    'computationContractCid',
    'inputRelationCids',
    'scopeCid',
    'effectiveDataPolicyCid',
    'authorityScopeCid',
  ];
  const cidPattern = /^sha256:[0-9a-f]{64}$/u;
  const evidenceLimitFields = ['maxWireBytes', 'maxNodes', 'maxDepth'];
  const validEvidenceLimits = limits =>
    limits !== null && typeof limits === 'object' &&
    !Array.isArray(limits) &&
    Object.keys(limits).sort().join('\0') ===
      [...evidenceLimitFields].sort().join('\0') &&
    evidenceLimitFields.every(name =>
      Number.isSafeInteger(limits[name]) && limits[name] >= 0);
  const validEvidenceContext = value =>
    value !== null && typeof value === 'object' &&
    Object.keys(value).sort().join('\0') ===
      [...evidenceFields].sort().join('\0') &&
    ['computationContractCid', 'scopeCid', 'effectiveDataPolicyCid',
      'authorityScopeCid'].every(name => cidPattern.test(value[name])) &&
    Array.isArray(value.inputRelationCids) &&
    value.inputRelationCids.every(cid => cidPattern.test(cid));
  return Object.freeze({
    begin(output, limits) {
      if (!validOutputLimits(limits)) {
        throw new TypeError('Invalid output export limits');
      }
      return checked(moon.strategyHostOutputExportBegin(
        output,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      ));
    },
    beginResult(host, result, limits) {
      if (!Number.isSafeInteger(result) || result < 0 ||
          !validResultOutputLimits(limits)) {
        throw new TypeError('Invalid Result output export request');
      }
      return checked(moon.strategyHostResultOutputExportBegin(
        host,
        result,
        limits.maxResultFields,
        limits.maxResultMappingWork,
        limits.maxResultOrderWork,
        limits.maxResultWorkspaceEntries,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      ));
    },
    beginManagedResultImport(host, result, output, material, limits) {
      if (!Number.isSafeInteger(result) || result < 0 || output == null ||
          material == null || !validResultOutputLimits(limits)) {
        throw new TypeError('Invalid managed Result import request');
      }
      return checked(moon.strategyHostManagedResultImportBegin(
        host,
        result,
        output,
        material,
        limits.maxResultFields,
        limits.maxResultMappingWork,
        limits.maxResultOrderWork,
        limits.maxResultWorkspaceEntries,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      ));
    },
    appendManagedResultImport(value, row, limits) {
      if (typeof row !== 'string' || !validResultOutputLimits(limits)) {
        throw new TypeError('Invalid managed Result import row');
      }
      checked(moon.strategyHostManagedResultImportAppend(
        value,
        row,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxValueTextBytes,
      ));
    },
    finishManagedResultImport: value => checked(
      moon.strategyHostManagedResultImportFinish(value),
    ),
    cancelManagedResultImport: moon.strategyHostManagedResultImportCancel,
    next: value => checked(moon.strategyHostOutputExportNext(value)),
    finish: value => checked(moon.strategyHostOutputExportFinish(value)),
    identity(value) {
      return Object.freeze({
        orderedRowsCid: checked(moon.strategyHostOutputExportCid(value)),
        logicalRelationCid:
          checked(moon.strategyHostOutputExportLogicalRelationCid(value)),
        resultSchemaCid:
          checked(moon.strategyHostOutputExportResultSchemaCid(value)),
        resultSchemaWire:
          checked(moon.strategyHostOutputExportResultSchemaWire(value)),
        resultFields:
          checked(moon.strategyHostOutputExportResultFields(value)),
        codecContractCid:
          checked(moon.strategyHostOutputExportCodecContractCid(value)),
        bytes: checked(moon.strategyHostOutputExportBytes(value)),
        nodes: checked(moon.strategyHostOutputExportNodes(value)),
        rows: checked(moon.strategyHostOutputExportRows(value)),
        schemaBytes: checked(
          moon.strategyHostOutputExportSchemaBytes(value),
        ),
        schemaNodes: checked(
          moon.strategyHostOutputExportSchemaNodes(value),
        ),
        schemaFields: checked(
          moon.strategyHostOutputExportSchemaFields(value),
        ),
      });
    },
    issueResultEvidence(value, context, limits) {
      if (!validEvidenceContext(context) ||
          !validEvidenceLimits(limits)) {
        throw new TypeError('Invalid Result evidence issuance request');
      }
      checked(moon.strategyHostOutputExportIssueResultEvidence(
        value,
        context.computationContractCid,
        context.inputRelationCids,
        context.scopeCid,
        context.effectiveDataPolicyCid,
        context.authorityScopeCid,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
      return Object.freeze({
        derivation: publications.admit(
          'derivation_evidence',
          checked(moon.strategyHostOutputExportDerivationEvidenceJson(value)),
          limits,
        ),
        ordering: publications.admit(
          'ordering_evidence',
          checked(moon.strategyHostOutputExportOrderingEvidenceJson(value)),
          limits,
        ),
      });
    },
    cancel: moon.strategyHostOutputExportCancel,
    payloadFailureAction(
      writerExists,
      writerSealed,
      writerCancelAttempted,
      preparedPending,
      preparedReleaseAttempted,
      exportExists,
      exportReleased,
      exportCancelAttempted,
    ) {
      return moon.strategyDurablePayloadFailureAction(
        writerExists,
        writerSealed,
        writerCancelAttempted,
        preparedPending,
        preparedReleaseAttempted,
        exportExists,
        exportReleased,
        exportCancelAttempted,
      );
    },
    cleanupOwnerAction:
      publications.publicationCleanupOwnerAction,
  });
}

// Trusted assembly only. Standard entries bind this to their generated runtime;
// execution requests cannot supply a verifier, SQL or replacement runtime.
export function runtimeCore(moon) {
  const publications = publicationControl(moon);
  return Object.freeze({
    siteControl: siteControl(moon),
    remoteSiteControl: remoteSiteControl(moon),
    remoteTransferControl: remoteTransferControl(moon),
    remoteStandardSourceControl: remoteStandardSourceControl(moon),
    remoteCredentialControl: remoteCredentialControl(moon),
    effectApplicationControl: effectApplicationControl(moon),
    remoteBundleControl: remoteBundleControl(moon),
    publicationControl: publications,
    outputExportControl: outputExportControl(moon, publications),
    count: moon.strategyHostCount,
    programDefinitionCid: moon.strategyHostProgramDefinitionCid,
    programHasEffects: moon.strategyHostHasEffects,
    resultInventory(value) {
      const names = moon.strategyHostResultNames(value);
      if (!Array.isArray(names)) throw new TypeError('Invalid Result inventory');
      if (names.length === 0) return Object.freeze([]);
      const inventory = checked(moon.strategyHostPublicationInventory(value));
      const count = moon.strategyHostPublicationInventoryCount(inventory);
      if (count !== names.length) {
        throw new TypeError('Invalid Result inventory projection');
      }
      return Object.freeze(Array.from({length: count}, (_, index) => {
        const definitionContract = publications.admit(
          'result_definition',
          checked(moon.strategyHostPublicationInventoryDefinitionJson(
            inventory, index,
          )),
          {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64},
        );
        const definition = JSON.parse(definitionContract.wire);
        return Object.freeze({
          name: checked(
            moon.strategyHostPublicationInventoryName(inventory, index),
          ),
          task: checked(
            moon.strategyHostPublicationInventoryTask(inventory, index),
          ),
          definition: Object.freeze(definition),
          definitionContract,
        });
      }));
    },
    next: value => checked(moon.strategyHostNext(value)),
    nextTask: moon.strategyHostNextTask,
    managedProducer: moon.strategyHostManagedProducer,
    managedProducers: moon.strategyHostManagedProducers,
    managedMatches: moon.strategyHostManagedOutputMatches,
    managedCarrierMatches: moon.strategyHostCarrierManagedOutputMatches,
    managedInputMatches: moon.strategyHostManagedInputMatchesMaterial,
    selectManaged: moon.strategyHostSelectManagedRegistration,
    task: moon.strategyHostTask,
    taskCapacity: (value, task) => tuplePair(checked(
      moon.strategyHostTaskCapacity(value, task),
    )),
    registration: moon.strategyHostRegistration,
    completed: moon.strategyHostTaskCompleted,
    finished: moon.strategyHostFinished,
    stop: moon.strategyHostStop,
    requireActivation: moon.strategyHostRequireActivation,
    coverActivation: moon.strategyHostCoverActivation,
    authorizeActivation: moon.strategyHostAuthorizeActivation,
    closeOutputs: moon.strategyHostCloseOutputs,
    output: moon.strategyHostOutput,
    transferBegin: (value, source, transfer, retained, execution) => checked(
      moon.strategyHostTransferBegin(
        value, source, transfer, retained, execution,
      ),
    ),
    transferCharge: (value, transfer, bytes) => checked(
      moon.strategyHostTransferCharge(value, transfer, bytes),
    ),
    transferSettle: (value, transfer, confirmed) => checked(
      moon.strategyHostTransferSettle(value, transfer, confirmed),
    ),
    transferComplete: (value, transfer, retained) => checked(
      moon.strategyHostTransferComplete(value, transfer, retained),
    ),
    transferAbort: (value, transfer, confirmed) => checked(
      moon.strategyHostTransferAbort(value, transfer, confirmed),
    ),
    transferRelease: (value, receipt) => checked(
      moon.strategyHostTransferRelease(value, receipt),
    ),
    transferReceiptMatches: (receipt, transfer, source, bytes, retained) =>
      moon.strategyHostTransferReceiptMatches(
        receipt, transfer, source, bytes, retained,
      ),
    transferPending: moon.strategyHostTransferPending,
    transferProgressBegin: transfer =>
      moon.strategyHostBeginTransferProgress(transfer),
    transferRecordSourceStop: progress =>
      moon.strategyHostRecordTransferSourceStop(progress),
    transferRecordSourceSiteSettlement: progress =>
      moon.strategyHostRecordTransferSourceSiteSettlement(progress),
    transferRecordDestinationCreated: progress =>
      moon.strategyHostRecordTransferDestinationCreated(progress),
    transferRecordDestinationAdmission: (progress, value) =>
      moon.strategyHostRecordTransferDestinationAdmission(
        progress,
        value.distinctMaterial,
        value.distinctGeneration,
        value.rows,
        value.batches,
        value.maxBatchRows,
        value.maxBatchBytes,
        value.transferredBytes,
        value.retainedBytes,
        value.transferLimit,
        value.retentionLimit,
      ),
    transferRecordDestinationHolding: progress =>
      moon.strategyHostRecordTransferDestinationHolding(progress),
    transferRecordDestinationReclaimed: progress =>
      moon.strategyHostRecordTransferDestinationReclaimed(progress),
    transferRecordDestinationSiteSettlement: progress =>
      moon.strategyHostRecordTransferDestinationSiteSettlement(progress),
    transferRecordDestinationCleanupRelease: progress =>
      moon.strategyHostRecordTransferDestinationCleanupRelease(progress),
    transferRecordSiteHoldingRelease: progress =>
      moon.strategyHostRecordTransferSiteHoldingRelease(progress),
    transferCommitAction: progress => checked(
      moon.strategyHostTransferCommitAction(progress),
    ),
    transferCleanupAction: progress => checked(
      moon.strategyHostTransferCleanupAction(progress),
    ),
    transferReceipt: moon.strategyHostTransferReceipt,
    explain: (value, bytes, nodes) => JSON.parse(checked(moon.strategyHostExplain(value, bytes, nodes))),
    usage: value => Object.freeze(Object.fromEntries(
      moon.strategyHostUsage(value).map((count, index) => [usageKeys[index], count]),
    )),
  });
}
