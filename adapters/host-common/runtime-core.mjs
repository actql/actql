import {runtimeField, runtimeOptionalField, runtimeIsError, runtimeIsBoxedSome, runtimeUnboxedReferenceOption} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import {createLocalSigningMetadata} from './local-signing-metadata.mjs';
import {createInstallationPreparationMetadata} from './installation-preparation-metadata.mjs';
import {publicationAction} from './publication-action.mjs';
import {validWirePlanViewShape} from '../../packages/client-wire/index.mjs';
import {ledgerUsageFields, ledgerUsageSpentFields} from './ledger-contract.generated.mjs';
import {
  resultOutputLimitFields,
  validOutputLimits,
  validResultOutputLimits,
} from './result-output-limits.mjs';

const usageKeys = Object.freeze(ledgerUsageFields.map(({name}) =>
  name.replace(/_([a-z])/gu, (_, letter) => letter.toUpperCase())));
const spentUsageKeys = new Set(ledgerUsageSpentFields.map(name =>
  name.replace(/_([a-z])/gu, (_, letter) => letter.toUpperCase())));

// Both strategy and MultiCaptured bridges return this SAME Core projection.
// Refuse an old/malformed layout; missing counters are never padded to zero.
export function ledgerUsageSnapshot(counts) {
  if (!Array.isArray(counts) || counts.length !== usageKeys.length ||
      ledgerUsageFields.some(({bits}, index) => typeof counts[index] !== 'bigint' ||
        counts[index] < 0n || BigInt.asIntN(bits, counts[index]) !== counts[index])) {
    throw new TypeError('InvalidStrategyLedgerUsage');
  }
  return Object.freeze(Object.fromEntries(counts.map((count, index) => [usageKeys[index], count])));
}

// The generated exemptions come from Core's actual pending predicate. This
// is a counter observation only, never a physical stop or custody proof.
export function ledgerUsageHasPendingResources(counts) {
  const usage = ledgerUsageSnapshot(counts);
  return Object.entries(usage).some(([name, value]) => !spentUsageKeys.has(name) && value !== 0n);
}

// The strategy driver already holds the canonical named snapshot. Preserve
// that interface while applying exactly the same generated pending rule.
export function ledgerUsageSnapshotHasPendingResources(usage) {
  if (usage === null || typeof usage !== 'object' || Array.isArray(usage)) {
    throw new TypeError('InvalidStrategyLedgerUsage');
  }
  const fields = Object.getOwnPropertyDescriptors(usage);
  if (Reflect.ownKeys(fields).length !== usageKeys.length ||
      usageKeys.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) {
    throw new TypeError('InvalidStrategyLedgerUsage');
  }
  return ledgerUsageHasPendingResources(usageKeys.map(name => fields[name].value));
}

export function ledgerUsageDiagnostic(counts) {
  return Object.freeze(Object.fromEntries(Object.entries(ledgerUsageSnapshot(counts))
    .map(([name, value]) => [name, value.toString()])));
}
const tuplePair = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [runtimeField(value, 0), runtimeField(value, 1)]
    : undefined;
const siteControls = new WeakMap();
const remoteSiteControls = new WeakMap();
const remoteTransferControls = new WeakMap();
const remoteStandardSourceControls = new WeakMap();
const remoteCredentialControls = new WeakMap();
const effectApplicationControls = new WeakMap();
const remoteBundleControls = new WeakMap();
const publicationControls = new WeakMap();

// Translate the installed Node envelope only; Common owns contract ceilings.
function inferQuantityCapacity(value) {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(',') !== 'limits,perAttempt' ||
      ['limits', 'perAttempt'].some(scope => {
        const amount = value[scope];
        return amount === null || typeof amount !== 'object' || Array.isArray(amount) ||
          Object.keys(amount).sort().join(',') !== 'costUnits,durationMs,tokens' ||
          Object.values(amount).some(quantity => typeof quantity !== 'bigint' ||
            quantity < 0n || quantity > BigInt(Number.MAX_SAFE_INTEGER));
      })) {
    throw new TypeError('InvalidInstalledInferQuantityCapacity');
  }
  return {
    limits: {tokens: value.limits.tokens, cost_units: value.limits.costUnits,
      duration_ms: value.limits.durationMs},
    per_attempt: {tokens: value.perAttempt.tokens, cost_units: value.perAttempt.costUnits,
      duration_ms: value.perAttempt.durationMs},
  };
}

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
    recoveredTargetGuards: (...args) => checked(
      moon.clientProgramRecoverEffectTargetGuards(...args)),
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
    prepareHoldingRestoration: moon.strategySitePrepareHoldingRestoration,
    acquireRestoredHolding: moon.strategySiteAcquireRestoredHolding,
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
    pollOutputRequest: moon.strategyRemotePollOutputRequest,
    pollOutputIntent: moon.strategyRemotePollOutputIntent,
    outputIntentProjection(intent) {
      const projected = moon.strategyRemoteOutputIntentProjection(intent);
      const value = runtimeField(projected, 0);
      return Object.freeze({storeAuthorityCid: value.store_authority_cid,
        publicationAttemptCid: value.publication_attempt_cid,
        resultDefinitionCid: value.result_definition_cid,
        orderingEvidenceCid: value.ordering_evidence_cid,
        coordinatorAuthority: value.coordinator_authority,
        transferAttemptId: value.transfer_attempt,
        transferRoute: runtimeField(projected, 1),
        destinationSite: value.destination_site_key,
        destinationSiteGeneration: value.destination_site_generation,
        transferMaxBytes: value.transfer_max_bytes,
        transferExpiresAtMilliseconds: value.transfer_expires_unix_ms,
        sourceGrantCid: value.source_grant_cid,
        destinationGrantCid: value.destination_grant_cid,
        routeCapabilityCid: value.route_capability_cid,
        transferOrigin: value.transfer_origin});
    },
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
    coordinatorOutputReportAckJson: (record, body) => checked(
      moon.strategyRemoteCoordinatorOutputReportAckJson(record, body)),
    admitOutputReportReply: (body, result) => checked(
      moon.strategyRemoteOutputReportReplyAdmit(body, result)),
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
    pollCancelJson: value => checked(moon.strategyRemotePollCancelJson(value)),
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
    responseCanRetireCancellationDelivery:
      moon.strategyRemoteDispatchResponseCanRetireCancellationDelivery,
    coordinatorCanRetireCancellationDelivery:
      moon.strategyRemoteCoordinatorCanRetireCancellationDelivery,
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
    coordinatorDeliveryEnvelopeJson: (request, body) => checked(
      moon.strategyRemoteCoordinatorDeliveryEnvelopeJson(request, body),
    ),
    coordinatorDeliveryContextCurrent: (request, context) => checked(
      moon.strategyRemoteCoordinatorDeliveryContextCurrent(request,
        context.coordinatorAuthority, context.siteKey, context.siteGeneration,
        context.authorizationCurrent, context.cancellationRequested),
    ),
    coordinatorRedeliveryEligible: (record, request, notSeenBody, context) => checked(
      moon.strategyRemoteCoordinatorRedeliveryEligible(record, request,
        notSeenBody, context.coordinatorAuthority, context.siteKey,
        context.siteGeneration, context.authorizationCurrent,
        context.cancellationRequested),
    ),
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
    coordinatorTransitionExpectedHistoryJson: transition => checked(
      moon.strategyRemoteCoordinatorTransitionExpectedHistoryJson(transition)),
    coordinatorTransitionHistoryJson: transition => checked(
      moon.strategyRemoteCoordinatorTransitionHistoryJson(transition)),
    coordinatorTransitionIsReplay: moon.strategyRemoteCoordinatorTransitionIsReplay,
    coordinatorObservationIssueCode: error => error?.code === 'MoonBitHostFailure'
      ? moon.strategyRemoteCoordinatorObservationIssueCode(error.cause) : '',
    coordinatorRecordHistoryJson: record => checked(
      moon.strategyRemoteCoordinatorRecordHistoryJson(record)),
    restoreCoordinatorHistoryJson: (record, body, evidence) => checked(
      moon.strategyRemoteCoordinatorHistoryRestore(record, body, evidence)),
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
    restoreFailedPartialRuntimeCustody(record, expectedRevision, sourceRequestCid,
      sourceWire, materialGeneration, sourceMeasurementCid, measurement,
      sourceOwner, sourceGeneration, processRequestCid, processMaterialGeneration,
      processOwner, processGeneration) {
      return checked(moon.strategyRemoteRuntimeRestoreFailedPartialCustody(record,
        expectedRevision, sourceRequestCid, sourceWire, materialGeneration,
        sourceMeasurementCid, measurement, sourceOwner, sourceGeneration,
        processRequestCid, processMaterialGeneration, processOwner, processGeneration));
    },
    restoreCompletedCleanupRuntimeCustody(record, evidence, subject, measurement) {
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
    admitDurableRecordJson: body => checked(moon.strategyRemoteDurableRecordAdmitJson(body)),
    restoreDurableRecord: (journal, durable) => checked(
      moon.strategyRemoteDurableRecordRestore(journal, durable)),
    recordDurableJson: record => checked(moon.strategyRemoteRecordDurableJson(record)),
    admissionDurableJson: admission => checked(moon.strategyRemoteAdmissionDurableJson(admission)),
    transitionDurableJson: transition => checked(moon.strategyRemoteTransitionDurableJson(transition)),
    transitionExpectedRevision: moon.strategyRemoteTransitionExpectedRevision,
    durableRecordJson: moon.strategyRemoteDurableRecordJson,
    durableRecordRevision: moon.strategyRemoteDurableRecordRevision,
    durableRecordKey: moon.strategyRemoteDurableRecordKey,
    durableRecordIdentity: moon.strategyRemoteDurableRecordIdentity,
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
      grant.namespaceId,
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
    prepareAuthenticationRequest: (...args) => checked(
      moon.strategyCredentialAuthenticationRequest(...args),
    ),
    bindAuthenticationUse: (...args) => checked(
      moon.strategyCredentialAuthenticationUseBind(...args),
    ),
    checkAuthenticationOperation: (...args) => checked(
      moon.strategyCredentialAuthenticationOperationCheck(...args),
    ),
  });
  remoteCredentialControls.set(moon, control);
  return control;
}

function remoteBundleControl(moon) {
  let control = remoteBundleControls.get(moon);
  if (control !== undefined) return control;
  control = Object.freeze({
    catalogIncarnationValid: moon.strategyRemoteBundleCatalogIncarnationValid,
    prepareDistribution: members => checked(moon.strategyRemoteBundleDistributionPrepare(members)),
    distributionIdentity: moon.strategyRemoteBundleDistributionIdentity,
    distributionJson: value => checked(moon.strategyRemoteBundleDistributionJson(value)),
    distributionProjection: moon.strategyRemoteBundleDistributionProjection,
    distributionContains: moon.strategyRemoteBundleDistributionContains,
    admitDistributionJson: (body, cid) => checked(
      moon.strategyRemoteBundleDistributionAdmitJson(body, cid)),
    prepareHoldScope: value => checked(moon.strategyRemoteBundleHoldScopePrepare(
      value.distribution, value.coordinatorAuthority, value.workspaceId,
      value.authorityScopeCid, value.environment, value.setRevisionCid,
      value.runtimeBundleCid, value.siteKey, value.siteGeneration, value.attemptId)),
    holdScopeIdentity: moon.strategyRemoteBundleHoldScopeIdentity,
    holdScopeJson: value => checked(moon.strategyRemoteBundleHoldScopeJson(value)),
    holdScopeProjection: moon.strategyRemoteBundleHoldScopeProjection,
    admitHoldScopeJson: (distribution, body, cid) => checked(
      moon.strategyRemoteBundleHoldScopeAdmitJson(distribution, body, cid)),
    prepareHoldBinding: value => checked(moon.strategyRemoteBundleHoldBindingPrepare(
      value.distribution, value.catalogIncarnation, value.coordinatorAuthority,
      value.workspaceId, value.authorityScopeCid, value.environment,
      value.setRevisionCid, value.runtimeBundleCid, value.siteKey,
      value.siteGeneration, value.initialRevision, value.attemptId)),
    prepareHoldBindingFromScope: (scope, catalog, revision) => checked(
      moon.strategyRemoteBundleHoldBindingFromScope(scope, catalog, revision)),
    holdBindingIdentity: moon.strategyRemoteBundleHoldBindingIdentity,
    holdBindingJson: value => checked(moon.strategyRemoteBundleHoldBindingJson(value)),
    holdBindingProjection: moon.strategyRemoteBundleHoldBindingProjection,
    holdBindingMatchesScope: moon.strategyRemoteBundleHoldBindingMatchesScope,
    holdBindingScope: value => checked(moon.strategyRemoteBundleHoldBindingScope(value)),
    admitHoldBindingJson: (distribution, body, cid) => checked(
      moon.strategyRemoteBundleHoldBindingAdmitJson(distribution, body, cid)),
    observeHold: value => moon.strategyRemoteBundleHoldObservationProjection(
      moon.strategyRemoteBundleHoldObserve(value.catalogIncarnation,
        value.record, value.binding, value.exactLiveHold)),
    prepareHoldFence: value => checked(moon.strategyRemoteBundleHoldFencePrepare(
      value.catalogIncarnation, value.record, value.binding, value.exactLiveHold)),
    prepareHoldRetain: value => checked(moon.strategyRemoteBundleHoldRetainPrepare(
      value.catalogIncarnation, value.activeBundleCid, value.record,
      value.binding, value.maxOwners)),
    prepareCustodyContextQuery: (distribution, scope) => checked(
      moon.strategyRemoteBundleCustodyContextQueryPrepare(distribution, scope)),
    prepareCustodyRequest: (distribution, binding, operation) => checked(
      moon.strategyRemoteBundleCustodyRequestPrepare(distribution, binding, operation)),
    admitCustodyRequestJson: (body, cid) => checked(
      moon.strategyRemoteBundleCustodyRequestAdmitJson(body, cid)),
    custodyRequestIdentity: moon.strategyRemoteBundleCustodyRequestIdentity,
    custodyRequestJson: value => checked(moon.strategyRemoteBundleCustodyRequestJson(value)),
    custodyRequestOperation: moon.strategyRemoteBundleCustodyRequestOperation,
    custodyRequestDistribution: moon.strategyRemoteBundleCustodyRequestDistribution,
    custodyRequestScope: moon.strategyRemoteBundleCustodyRequestScope,
    custodyRequestBinding: moon.strategyRemoteBundleCustodyRequestBinding,
    prepareCustodyContextResponse: (request, binding) => checked(
      moon.strategyRemoteBundleCustodyContextResponsePrepare(request, binding)),
    prepareCustodyResponse: (request, value) => {
      const catalogPresent = value.catalogIncarnation !== undefined;
      const revisionPresent = value.revision !== undefined;
      if (catalogPresent && typeof value.catalogIncarnation !== 'string' ||
          revisionPresent && (!Number.isInteger(value.revision) ||
            value.revision < 0 || value.revision > 2147483647)) {
        throw new TypeError('InvalidRemoteBundleRetentionObservation');
      }
      return checked(moon.strategyRemoteBundleCustodyResponseFieldsPrepare(
        request, value.status, catalogPresent, value.catalogIncarnation ?? '',
        revisionPresent, value.revision ?? 0));
    },
    admitCustodyResponseJson: (request, body, cid) => checked(
      moon.strategyRemoteBundleCustodyResponseAdmitJson(request, body, cid)),
    custodyResponseIdentity: moon.strategyRemoteBundleCustodyResponseIdentity,
    custodyResponseJson: value => checked(moon.strategyRemoteBundleCustodyResponseJson(value)),
    custodyResponseKind: moon.strategyRemoteBundleCustodyResponseKind,
    custodyResponseBinding: moon.strategyRemoteBundleCustodyResponseBinding,
    custodyResponseObservation: moon.strategyRemoteBundleCustodyResponseObservationText,
    custodyResponseCatalog: value =>
      moon.strategyRemoteBundleCustodyResponseCatalogIncarnationText(value) || undefined,
    custodyResponseRevision: value => {
      const revision = moon.strategyRemoteBundleCustodyResponseRecordRevisionText(value);
      return revision === '' ? undefined : Number(revision);
    },
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
  const capturedComputationPreparations = new WeakMap();
  const contractBounds = new WeakMap();
  const issuedDeliveryGrants = new WeakMap();
  const issuedDeliveryAttempts = new WeakMap();
  const originalDeliveryAttempts = new WeakMap();
  const evidenceTokens = new WeakMap();
  const modelOriginalDocumentTokens = new WeakMap();
  const admissionTokens = new WeakMap();
  const compiledRunTokens = new WeakMap();
  const originalRunPlanTokens = new WeakMap();
  const originalInferRunTokens = new WeakMap();
  const restoredInferRuns = new WeakSet();
  const serializationPlanTokens = new WeakMap();
  const serializationGenerationTokens = new WeakMap();
  const serializationInputEvidenceTokens = new WeakMap();
  const compiledSourceFreeResultPolicy = compiled => {
    const value = compiledRunTokens.get(compiled);
    if (value === undefined) throw new TypeError('Foreign Client compiled Run');
    const original = moon.clientProgramCompiledRunSourceFreeResultPolicy(value);
    return original === undefined ? undefined : Object.freeze({
      kind: runtimeField(original, 0), cid: runtimeField(original, 1), wire: runtimeField(original, 2),
    });
  };
  const inferInvocationTokens = new WeakMap();
  const compiledRunResult = (result, code) => {
    try {
      return checked(result);
    } catch (error) {
      if (error.code !== 'MoonBitHostFailure') throw error;
      throw Object.assign(new Error(code, {cause: error.cause}), {code});
    }
  };
  const compiledContent = compiled => {
    const value = compiledRunTokens.get(compiled);
    if (value === undefined || !moon.clientProgramCompiledRunHasSerialization(value)) {
      throw new TypeError('Foreign Client compiled Content Run');
    }
    return value;
  };
  const prepareSerializationGraph = (checkedProgram, options, intermediate, request) => {
    const original = options?.resultDataPolicy;
    if (original?.kind !== 'data_policy' || typeof original.cid !== 'string' ||
        typeof original.wire !== 'string' ||
        !['task', 'step', 'maxRows', 'maxBytes'].every(key =>
          Number.isInteger(options[key]) && options[key] >= 0 &&
          options[key] <= 2147483647)) {
      throw new TypeError('Invalid Content compilation options');
    }
    let graph;
    if (request === undefined) {
      const issue = intermediate ? moon.clientProgramSerializationPlanComponent
        : moon.clientProgramSerializationPlanGraph;
      graph = compiledRunResult(issue(checkedProgram, options.task, options.step,
        original.cid, original.wire, options.maxRows, options.maxBytes), 'RunHostContentPlanRejected');
    } else {
      const issue = moon.clientProgramPrepareRequestSerializationGraph;
      if (typeof issue !== 'function') throw new TypeError('Request Content Graph constructor unavailable');
      graph = compiledRunResult(Reflect.apply(issue, moon, [request.parent, request.input,
        options.task, options.step, original.cid, original.wire, options.maxRows,
        options.maxBytes, !intermediate, request.contracts]), 'RunHostContentPlanRejected');
    }
    const selected = Object.freeze({task: options.task, step: options.step,
      wire: moon.clientProgramSerializationPlanGraphWire(graph)});
    serializationPlanTokens.set(selected, graph);
    return selected;
  };
  const contentCaptures = values => {
    if (values === undefined) return [];
    if (!Array.isArray(values)) throw new TypeError('Invalid Content capture inventory');
    return values.map(value => {
      const generation = serializationGenerationTokens.get(value);
      if (generation === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramSerializationCapture(generation),
        'Client Content capture unavailable');
    });
  };
  const prepareAcquiredSerializationGraph = (checkedProgram, options, intermediate, request) => {
    if (!['task', 'step', 'maxRows', 'maxBytes'].every(key =>
      Number.isInteger(options?.[key]) && options[key] >= 0 && options[key] <= 2147483647)) {
      throw new TypeError('Invalid acquired Content compilation options');
    }
    let graph;
    if (request === undefined) {
      const issue = intermediate ? moon.clientProgramAcquiredSerializationPlanComponent
        : moon.clientProgramAcquiredSerializationPlanGraph;
      graph = compiledRunResult(issue(checkedProgram, options.task, options.step,
        options.maxRows, options.maxBytes), 'RunHostContentPlanRejected');
    } else {
      const issue = moon.clientProgramPrepareRequestAcquiredSerializationGraph;
      if (typeof issue !== 'function') throw new TypeError('Request acquired Content Graph constructor unavailable');
      graph = compiledRunResult(Reflect.apply(issue, moon, [request.parent, request.input,
        options.task, options.step, options.maxRows, options.maxBytes,
        !intermediate, request.contracts]), 'RunHostContentPlanRejected');
    }
    const selected = Object.freeze({task: options.task, step: options.step,
      wire: moon.clientProgramSerializationPlanGraphWire(graph)});
    serializationPlanTokens.set(selected, graph);
    return selected;
  };
  const snapshotTokens = new WeakMap();
  const effectSourceTokens = new WeakMap();
  const localEffectSourceTokens = new WeakMap();
  const localEffectArtifactTokens = new WeakMap();
  const localEffectIdentityTokens = new WeakMap();
  const tableInputTokens = new WeakMap();
  const tablePreviewTokens = new WeakMap();
  const recoveredTablePreviewTokens = new WeakMap();
  const localEffectManifestTokens = new WeakMap();
  const localEffectDependencyTokens = new WeakMap();
  const localEffectImportTokens = new WeakMap();
  const inspectLocalEffectArtifact = issued => {
    const value = Object.freeze({
      identity: moon.clientProgramLocalEffectResultArtifactCid(issued),
      wire: moon.clientProgramLocalEffectResultArtifactJson(issued),
      derivationWire: moon.clientProgramLocalEffectResultDerivationJson(issued),
      orderingWire: moon.clientProgramLocalEffectResultOrderingJson(issued),
    });
    localEffectArtifactTokens.set(value, issued);
    return value;
  };
  const localEffectContext = context => {
    if (context === null || typeof context !== 'object' ||
        !['admission', 'runDefinition', 'runInvocation', 'observation']
          .every(key => context[key] !== undefined)) {
      throw new TypeError('Invalid local Effect Result context');
    }
    return [admissionToken(context.admission), token(context.runDefinition),
      token(context.runInvocation), evidenceToken(context.observation)];
  };
  const sourceAdvanceTokens = new WeakMap();
  const computationPreviewTokens = new WeakMap();
  const computationPreviewWires = new WeakMap();
  const inspect = (contract, limits) => {
    const value = Object.freeze({
      name: moon.strategyPublicationContractName(contract),
      identityField: moon.strategyPublicationContractIdentityField(contract),
      identity: moon.strategyPublicationContractIdentity(contract),
      wire: moon.strategyPublicationContractJson(contract),
    });
    tokens.set(value, contract);
    if (limits !== undefined) {
      // The actual issuer checked this complete immutable wire under these
      // bounds. Each JSON node needs at least one UTF-16 code unit; at most
      // three UTF-8 bytes encode one code unit. These conservative bounds
      // can prove a later looser limit without parsing or hashing again.
      contractBounds.set(value, Object.freeze({
        maxWireBytes: Math.min(limits.maxWireBytes, value.wire.length * 3),
        maxNodes: Math.min(limits.maxNodes, value.wire.length),
        maxDepth: limits.maxDepth,
      }));
    }
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
  const captureContractLimits = (limits, label) => issuanceLimits(Object.freeze({
    maxWireBytes: limits?.maxWireBytes,
    maxNodes: limits?.maxNodes,
    maxDepth: limits?.maxDepth,
  }), label);
  const capturedPreparationLimits = preparation => {
      // The same preparation owns the complete context envelope. Metadata
      // contract bounds cannot price embedded Result rows or their wrapper.
      const originalOption = moon.strategyCapturedRunPreparationLimits(preparation);
      const originalLimits = runtimeIsBoxedSome(originalOption)
        ? runtimeField(originalOption, 0) : undefined;
      if (!Array.isArray(originalLimits) || originalLimits.length !== 3 ||
          !Number.isSafeInteger(originalLimits[0]) ||
          !Number.isSafeInteger(originalLimits[1]) ||
          !Number.isSafeInteger(originalLimits[2]) ||
          originalLimits[0] < 0 || originalLimits[0] > 2147483647 ||
          originalLimits[1] < 0 || originalLimits[1] > 2147483647 ||
          originalLimits[2] < 0 || originalLimits[2] > 2147483647) {
        throw new TypeError('Invalid original Captured Run preparation limits');
      }
      return Object.freeze({maxWireBytes: originalLimits[0],
        maxNodes: originalLimits[1], maxDepth: originalLimits[2]});
  };
  const finishCapturedPreparation = async (preparation, signal,
    retainComputation = false) => {
    let finished = false;
    try {
      const limits = capturedPreparationLimits(preparation);
      while (true) {
        signal?.throwIfAborted();
        if (checked(moon.strategyCapturedRunAdvance(preparation, 256))) break;
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = inspect(checked(retainComputation
        ? moon.strategyCapturedRunFinishRetained(preparation)
        : moon.strategyCapturedRunFinish(preparation)), limits);
      if (retainComputation) {
        capturedComputationPreparations.set(captured, preparation);
      }
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.strategyCapturedRunCancel(preparation);
    }
  };
  const finishProgramSnapshot = async (publication, output, signal) => {
    signal?.throwIfAborted();
    const snapshot = checked(moon.clientProgramBeginSnapshot(publication, output));
    let finished = false;
    try {
      while (true) {
        signal?.throwIfAborted();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceSnapshot(snapshot, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original snapshot progress');
        }
        if (progress[0]) break;
        await new Promise(resolve => setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = inspectSnapshot(checked(moon.clientProgramFinishSnapshot(snapshot)));
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.clientProgramCancelSnapshot(snapshot);
    }
  };
  const programCaptureLimits = capture => {
    const extent = checked(moon.clientProgramCaptureLimits(capture));
    const maxWireBytes = runtimeField(extent, 0);
    const maxNodes = runtimeField(extent, 1);
    const maxDepth = runtimeField(extent, 2);
    if (!Number.isSafeInteger(maxWireBytes) || maxWireBytes < 0 ||
        maxWireBytes > 2147483647 ||
        !Number.isSafeInteger(maxNodes) || maxNodes < 0 || maxNodes > 2147483647 ||
        !Number.isSafeInteger(maxDepth) || maxDepth < 0 || maxDepth > 2147483647 ||
        runtimeField(extent, 3) !== undefined) {
      throw new TypeError('Invalid original capture extent');
    }
    return Object.freeze({maxWireBytes, maxNodes, maxDepth});
  };
  // Typed ordinary capture never exposes its inner issuer. The same Host
  // continuation owns cancellation throughout every await and publication.
  const finishProgramCapture = async (capture, signal) => {
    let finished = false;
    try {
      checked(moon.clientProgramStartCapture(capture));
      const limits = programCaptureLimits(capture);
      while (true) {
        signal?.throwIfAborted();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceCapture(capture, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original capture progress');
        }
        if (progress[0]) break;
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = inspect(checked(
        moon.clientProgramFinishCapture(capture)), limits);
      // The existing publication owner keeps this one typed continuation.
      // Its private issuer remains on the same preparation resource owner.
      capturedComputationPreparations.set(captured, {program: capture});
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.clientProgramCancelCapture(capture);
    }
  };
  const finishProgramValidation = async (validation, signal, requireCurrent) => {
    try {
      requireCurrent?.();
      checked(moon.clientProgramStartValidation(validation));
      while (true) {
        signal?.throwIfAborted();
        requireCurrent?.();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceValidation(validation, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original publication validation progress');
        }
        if (progress[0]) {
          signal?.throwIfAborted();
          requireCurrent?.();
          checked(moon.clientProgramFinishValidation(validation));
          return true;
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      moon.clientProgramCancelValidation(validation);
    }
  };
  const finishStoreValidation = async (validation, requireCurrent) => {
    try {
      while (true) {
        requireCurrent();
        const progress = tuplePair(checked(
          moon.clientStoreAdvanceOriginalValidation(validation, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original Store validation progress');
        }
        if (progress[0]) {
          requireCurrent();
          checked(moon.clientStoreFinishOriginalValidation(validation));
          return true;
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      moon.clientStoreCancelOriginalValidation(validation);
    }
  };
  const finishPublicationValidation = async (
    preparation, advance, finish, cancel, signal,
  ) => {
    try {
      while (true) {
        signal?.throwIfAborted();
        const progress = advance(preparation, 256);
        if (progress === -1) return false;
        if (progress === 1) {
          signal?.throwIfAborted();
          return finish(preparation);
        }
        if (progress !== 0) {
          throw new TypeError('Invalid publication validation progress');
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      cancel(preparation);
    }
  };
  control = Object.freeze({
    seal(name, bodyWire, limits) {
      limits = captureContractLimits(limits, 'publication contract');
      return inspect(checked(moon.strategyPublicationSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    // Data-only private retention parser; no resource/custody/current grant.
    privateContinuationRetentionShape: moon.clientProgramPrivateContinuationRetentionShape,
    admit(name, completeWire, limits) {
      limits = captureContractLimits(limits, 'publication contract');
      return inspect(checked(moon.strategyPublicationAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    admitOriginal(original, limits) {
      const retained = contractBounds.get(original);
      if (retained === undefined || !tokens.has(original)) return undefined;
      const required = captureContractLimits(limits, 'publication contract');
      return retained.maxWireBytes <= required.maxWireBytes &&
        retained.maxNodes <= required.maxNodes &&
        retained.maxDepth <= required.maxDepth ? original : undefined;
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
      limits = captureContractLimits(limits, 'Run Invocation');
      return inspect(checked(moon.strategyIssueRunInvocation(
        evidenceToken(template),
        evidenceToken(observation),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
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
    prepareCheckedClientSerializationGraph(checkedProgram, options) {
      return prepareSerializationGraph(checkedProgram, options, false);
    },
    prepareCheckedClientSerializationComponent(checkedProgram, options) {
      return prepareSerializationGraph(checkedProgram, options, true);
    },
    prepareCheckedClientRequestSerializationGraph(parent, input, contracts, checkedProgram, options, intermediate) {
      return prepareSerializationGraph(checkedProgram, options, intermediate, {parent, input, contracts});
    },
    prepareCheckedClientSerializedInferGraph(occurrence, selected, execution) {
      const graph = serializationPlanTokens.get(selected);
      if (graph === undefined) throw new TypeError('Foreign Content compilation graph');
      return compiledRunResult(moon.clientProgramSerializedInferPlanGraph(
        occurrence, graph, execution), 'RunHostContentInferPlanRejected');
    },
    startCheckedClientGeneratedInferExecution(compiled, generation, prepared, graph, provider) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartGeneratedInferExecution(
        prepared, run, original, graph, provider), 'RunHostContentInferInputRejected');
    },
    startCheckedClientGeneratedInferInputs(compiled, generation, graph, inputs, provider) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartGeneratedInferInputs(
        run, original, graph, inputs, provider), 'RunHostContentInferInputRejected');
    },
    startCheckedClientOriginalGeneratedInferExecution(compiled, generation, prepared, graph, provider,
      definition, consumer, readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartOriginalGeneratedInferExecution(
        prepared, run, original, graph, provider, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes),
      'RunHostContentInferInputRejected');
    },
    startCheckedClientOriginalGeneratedInferInputs(compiled, generation, graph, inputs, provider,
      definition, consumer, readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartOriginalGeneratedInferInputs(
        run, original, graph, inputs, provider, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes),
      'RunHostContentInferInputRejected');
    },
    startCheckedClientRestoredGeneratedInferExecution(compiled, definition, generation,
      prepared, graph, provider, bodies, snapshot, available) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client Content generation');
      }
      return compiledRunResult(moon.clientProgramStartRestoredGeneratedInferInput(
        prepared, run, token(definition), original, graph, bodies.registry, bodies.values,
        provider, snapshot.binding, snapshot.descriptorWire, snapshot.rows, available,
        bodies.fragment, bodies.ordered), 'RunHostContentInferInputRejected');
    },
    startCheckedClientRestoredGeneratedInferInputs(compiled, definition, generation,
      graph, inputs, provider, snapshot, available) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client Content generation');
      }
      return compiledRunResult(moon.clientProgramStartRestoredGeneratedInferInputs(
        run, token(definition), original, graph, inputs, provider, snapshot.binding,
        snapshot.descriptorWire, available), 'RunHostContentInferInputRejected');
    },
    startCheckedClientContentInferObservation(compiled, executions, generations, ledger, limits) {
      const run = compiledContent(compiled);
      if (!Array.isArray(generations)) throw new TypeError('Invalid Content capture inventory');
      const originals = generations.map(generation => {
        const original = serializationGenerationTokens.get(generation);
        if (original === undefined ||
            moon.clientProgramSerializationGenerationEvidence(original, run) === undefined) {
          throw new TypeError('Foreign Client Content generation');
        }
        return original;
      });
      return compiledRunResult(moon.clientProgramStartContentInferObservationIssuance(
        executions, originals, ledger, limits.maxSlots, limits.maxWireBytes, limits.maxWork),
      'RunHostContentInferObservationRejected');
    },
    prepareCheckedClientAcquiredSerializationGraph(checkedProgram, options) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, false);
    },
    prepareCheckedClientAcquiredSerializationComponent(checkedProgram, options) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, true);
    },
    prepareCheckedClientRequestAcquiredSerializationGraph(parent, input, contracts, checkedProgram, options, intermediate) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, intermediate, {parent, input, contracts});
    },
    readCurrentClientRunView(runDefinition, prepared, authorization, ref, state, snapshotCid, limits) {
      if (typeof moon.clientProgramCurrentRunView !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'),
          {code: 'ClientOperationUnavailable'});
      }
      return compiledRunResult(moon.clientProgramCurrentRunView(
        token(runDefinition), evidenceToken(prepared), evidenceToken(authorization),
        JSON.stringify(ref), JSON.stringify(state), snapshotCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostInspectRejected');
    },
    readCheckedClientStaticPlan(checkedProgram, kind, limits) {
      if (!['values', 'tasks', 'effects'].includes(kind) ||
          !Number.isSafeInteger(limits?.maxWireBytes) || limits.maxWireBytes < 1 ||
          !Number.isSafeInteger(limits?.maxNodes) || limits.maxNodes < 1 ||
          !Number.isSafeInteger(limits?.maxDepth) || limits.maxDepth < 1) {
        throw new TypeError('InvalidClientStaticPlanRequest');
      }
      const compile = kind === 'effects' ? moon.clientProgramCompileLocalEffects
        : kind === 'values' ? moon.clientProgramCompileLocalValues
          : moon.clientProgramCompileLocalTasks;
      const project = kind === 'effects' ? moon.clientProgramEffectfulStaticPlanView
        : kind === 'values' ? moon.clientProgramValuesStaticPlanView
          : moon.clientProgramTaskStaticPlanView;
      if (typeof compile !== 'function' || typeof project !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'),
          {code: 'ClientOperationUnavailable'});
      }
      // Compile the original checked owner only. In particular, do not issue
      // an allowed Run, allocate a request identity or open an execution.
      const compiled = compiledRunResult(compile(checkedProgram),
        'RunHostCompilationRejected');
      return compiledRunResult(project(checkedProgram, compiled,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostStaticPlanRejected');
    },
    captureOriginalClientRunPlan(compiled, original, definition, limits) {
      issuanceLimits(limits, 'Original Run plan');
      if (limits.maxWireBytes < 1 || limits.maxNodes < 1 || limits.maxDepth < 1) {
        throw new TypeError('Invalid Original Run plan issuance limits');
      }
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          !moon.clientProgramCompiledRunMatches(value, original) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original plan compilation');
      }
      if (typeof moon.clientProgramCompiledRunStaticPlanView !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      const wire = compiledRunResult(moon.clientProgramCompiledRunStaticPlanView(
        value, original, limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostOriginalPlanRejected');
      if (typeof compiled.compiledPlan.wire !== 'string' || typeof wire !== 'string' ||
          Buffer.byteLength(compiled.compiledPlan.wire) > limits.maxWireBytes ||
          Buffer.byteLength(wire) > limits.maxWireBytes) {
        throw new TypeError('Invalid Client original plan evidence');
      }
      const originalBytes = Object.freeze({compiledPlanWire: compiled.compiledPlan.wire,
        planViewWire: wire});
      const programCid = moon.clientProgramDefinitionCid(original);
      // The nominal compiler projection already bound its map to this Plan
      // and Program. Capture those immutable outputs, not a second stored-input
      // admission. Independent durable reads still use the full reader below.
      const selected = Object.freeze({});
      originalRunPlanTokens.set(selected, Object.freeze({original: originalBytes,
        runDefinitionCid: definition.identity, programCid,
        prepared: compiled.preparedEvidence.wire, authorization: compiled.authorization.wire}));
      return selected;
    },
    originalRunPlanAdmissionEvidence(selected, definition, programCid, evidence) {
      const retained = originalRunPlanTokens.get(selected);
      // Exact first-admission provenance is independent of current read or
      // control permission. A copied wire/CID cannot create this selection.
      token(definition);
      if (retained === undefined || retained.runDefinitionCid !== definition.identity ||
          retained.programCid !== programCid || retained.prepared !== evidence?.prepared ||
          retained.authorization !== evidence?.authorization) {
        throw new TypeError('Foreign Client original plan admission');
      }
      return retained.original;
    },
    readStoredRunPlanOriginal(original, definition, programCid, limits) {
      token(definition);
      issuanceLimits(limits, 'Original Run plan');
      if (original === null || typeof original !== 'object' || Array.isArray(original) ||
          Object.keys(original).sort().join(',') !== 'compiledPlanWire,planViewWire' ||
          limits.maxWireBytes < 1 || limits.maxNodes < 1 || limits.maxDepth < 1 ||
          ['compiledPlanWire', 'planViewWire'].some(field =>
            typeof original[field] !== 'string' || Buffer.byteLength(original[field]) > limits.maxWireBytes)) {
        throw new TypeError('Invalid Client original plan evidence');
      }
      const plan = control.admit('compiled_plan', original.compiledPlanWire, limits);
      const view = JSON.parse(original.planViewWire);
      if (!validWirePlanViewShape(view) ||
          plan.identity !== JSON.parse(definition.wire).compiled_plan_cid ||
          view.compiled_plan_cid !== plan.identity ||
          JSON.parse(plan.wire).program_definition_cid !== programCid) {
        throw new TypeError('Foreign Client original plan evidence');
      }
      if (typeof moon.clientProgramCheckLogicalMapBinding !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      const map = control.admitRunEvidence('logical_map', JSON.stringify(view.logical_map), limits);
      compiledRunResult(moon.clientProgramCheckLogicalMapBinding(evidenceToken(map), token(plan),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostOriginalMapRejected');
      return original.planViewWire;
    },
    // First admission retains only the actual compiler owner and its original
    // Result policy. A copied wire cannot supply the journal's original ticket.
    captureOriginalClientInferRun(compiled, checkedProgram, definition, request, environment, parameters) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          !moon.clientProgramCompiledRunMatches(value, checkedProgram) ||
          !moon.clientProgramMatchesRequestIdentity(checkedProgram, request) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original Infer Run');
      }
      const resultPolicyOriginal = control.compiledInferEvaluationPolicy(compiled);
      if (resultPolicyOriginal === undefined) throw new TypeError('Missing Client original Infer Result policy');
      const materialsWire = compiledRunResult(moon.clientProgramIssueInferRunMaterials(
        value, token(definition), environment, parameters), 'RunHostInferMaterialsRejected');
      const selected = Object.freeze({});
      originalInferRunTokens.set(selected, Object.freeze({
        original: Object.freeze({materialsWire, resultPolicyOriginal}),
        runDefinitionCid: definition.identity,
        request,
        prepared: compiled.preparedEvidence.wire, authorization: compiled.authorization.wire,
      }));
      return selected;
    },
    originalInferRunAdmissionEvidence(selected, definition, request, evidence) {
      const retained = originalInferRunTokens.get(selected);
      token(definition);
      if (retained === undefined || retained.runDefinitionCid !== definition.identity ||
          retained.request !== request || retained.prepared !== evidence?.prepared ||
          retained.authorization !== evidence?.authorization) {
        throw new TypeError('Foreign Client original Infer admission');
      }
      return retained.original;
    },
    // The same journal's already selected Run supplies the expected original.
    // Current installation, authority and physical input custody are not read or
    // issued here. The returned preparation and graph must stay together.
    admitStoredClientInferRunOriginal(original, definition, request, evidence, profiles, limits) {
      token(definition);
      issuanceLimits(limits, 'Original Infer Run');
      const keys = original === null || typeof original !== 'object' || Array.isArray(original)
        ? [] : Object.keys(original);
      if (keys.length !== 2 || !keys.includes('materialsWire') || !keys.includes('resultPolicyOriginal') ||
          typeof original.materialsWire !== 'string' || original.materialsWire.length === 0 ||
          Buffer.byteLength(original.materialsWire) > limits.maxWireBytes ||
          !Array.isArray(profiles) || profiles.length !== 7 || profiles.some(value => typeof value !== 'boolean')) {
        throw new TypeError('Invalid Client original Infer materials');
      }
      // A Source-backed Run retains its checked publication policy, not the
      // source-free unknown policy. This copy is evidence only: after restoring
      // the original compiler Owner, compare its complete policy below.
      const savedPolicy = original.resultPolicyOriginal;
      if (savedPolicy === null || typeof savedPolicy !== 'object' || Array.isArray(savedPolicy) ||
          Object.keys(savedPolicy).sort().join(',') !== 'cid,kind,wire' ||
          savedPolicy.kind !== 'data_policy' || typeof savedPolicy.cid !== 'string' ||
          typeof savedPolicy.wire !== 'string' || savedPolicy.wire.length === 0 ||
          Buffer.byteLength(savedPolicy.cid) > limits.maxWireBytes ||
          Buffer.byteLength(savedPolicy.wire) > limits.maxWireBytes) {
        throw new TypeError('Invalid Client original Infer Result policy');
      }
      const policy = Object.freeze({kind: savedPolicy.kind, cid: savedPolicy.cid, wire: savedPolicy.wire});
      const materials = compiledRunResult(moon.clientProgramAdmitInferRunMaterials(
        original.materialsWire, definition.identity, ...profiles), 'RunHostInferMaterialsRejected');
      let value = compiledRunResult(moon.clientProgramInferRunMaterialsCompiled(materials),
        'RunHostInferMaterialsRejected');
      const prepared = moon.clientProgramInferRunMaterialsPrepared(materials);
      const graph = moon.clientProgramInferRunMaterialsGraph(materials);
      if (graph === undefined || !moon.clientProgramMatchesRequestIdentity(prepared, request) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition)) ||
          inspectEvidence(moon.clientProgramCompiledRunPrepared(value)).wire !== evidence?.prepared ||
          inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)).wire !== evidence?.authorization) {
        throw new TypeError('Foreign Client original Infer materials');
      }
      value = compiledRunResult(moon.clientProgramBindCompiledInferResultPolicy(value,
        policy.cid, policy.wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostResultPolicyRejected');
      const actualPolicy = moon.clientProgramCompiledRunEvaluationPolicy(value);
      if (actualPolicy === undefined || runtimeField(actualPolicy, 0) !== policy.kind ||
          runtimeField(actualPolicy, 1) !== policy.cid || runtimeField(actualPolicy, 2) !== policy.wire) {
        throw new TypeError('Foreign Client original Infer Result policy');
      }
      const compiled = Object.freeze({kind: 'infer',
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(compiled, value);
      const restored = Object.freeze({compiled, prepared, graph, runDefinition: definition});
      restoredInferRuns.add(restored);
      return restored;
    },
    checkRestoredClientInferRunOwner(restored, checkedProgram) {
      if (!restoredInferRuns.has(restored) || restored.prepared !== checkedProgram) {
        throw new TypeError('Foreign Client restored Infer Run');
      }
      control.checkClientCompiledRunOwner(restored.compiled, checkedProgram);
      return restored;
    },
    checkedClientCompiledInferOriginal(compiled, checkedProgram, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original Infer compilation');
      }
      const original = moon.clientProgramCompiledInferOriginal(value, checkedProgram);
      if (original === undefined) throw new TypeError('Foreign Client original Infer preparation');
      return Object.freeze({graph: runtimeField(original, 0), execution: runtimeField(original, 1)});
    },
    prepareCheckedClientCompiledRun(checkedProgram, kind, policy, inferGraph, compilationOriginal) {
      if (!['values', 'tasks', 'infer', 'serialization'].includes(kind)) {
        throw new TypeError('Invalid Client compilation profile');
      }
      if ((kind === 'infer' || kind === 'serialization') !== (inferGraph !== undefined)) {
        throw new TypeError(kind === 'serialization'
          ? 'Content compilation requires its checked graph'
          : 'Infer compilation requires its checked graph');
      }
      const serializationGraph = kind === 'serialization'
        ? serializationPlanTokens.get(inferGraph) : undefined;
      if (kind === 'serialization' && serializationGraph === undefined) {
        throw new TypeError('Foreign Content compilation graph');
      }
      // The existing typed issuer below binds this artifact to the SAME
      // checked Program. A refused original never falls back to compilation.
      const compilation = compilationOriginal !== undefined ? compilationOriginal : compiledRunResult(kind === 'values'
        ? moon.clientProgramCompileLocalValues(checkedProgram)
        : kind === 'serialization'
          ? moon.clientProgramCompileLocalSerialization(checkedProgram, serializationGraph)
        : kind === 'infer'
          ? Array.isArray(inferGraph)
            ? moon.clientProgramCompileLocalInfers(checkedProgram, inferGraph)
            : moon.clientProgramCompileLocalInfer(checkedProgram, inferGraph)
          : moon.clientProgramCompileLocalTasks(checkedProgram),
      kind === 'values' ? 'RunHostCompilationRejected'
        : 'RunHostTaskCompilationRejected');
      // Pure staged originals use the existing Values/Tasks sum. The Request
      // Model compiler instead returns the original raw TaskCompilation;
      // its existing typed issuer validates that original and owner directly.
      // Unmigrated explicit compilation keeps its separate raw artifact entry.
      let value = compiledRunResult(compilationOriginal !== undefined
        ? kind === 'values'
          ? moon.clientProgramIssueOriginalValuesCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
          : kind === 'infer' || kind === 'serialization'
            ? moon.clientProgramIssueTaskCompiledRun(checkedProgram,
              compilation, policy.executionContextCid, policy.hostPolicyCid,
              policy.expiresAt)
          : moon.clientProgramIssueOriginalTaskCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
        : kind === 'values'
          ? moon.clientProgramIssueValuesCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
          : moon.clientProgramIssueTaskCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt), 'RunHostAdmissionRejected');
      if (kind === 'serialization' && compilationOriginal !== undefined &&
          moon.clientProgramCompiledRunSerializationGraph(value) !== serializationGraph) {
        throw new TypeError('Foreign Content compilation graph');
      }
      if (kind === 'infer') {
        const original = policy.resultDataPolicy;
        if (original?.kind !== 'data_policy' || typeof original.cid !== 'string' ||
            typeof original.wire !== 'string') throw new TypeError('InvalidHostResultDataPolicy');
        value = compiledRunResult(moon.clientProgramBindCompiledInferResultPolicy(
          value, original.cid, original.wire, 1000000, 100000, 64),
        'RunHostResultPolicyRejected');
      }
      const result = Object.freeze({
        kind,
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(
          moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(
          moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(
          moon.clientProgramCompiledRunAdmission(value)),
      });
      compiledRunTokens.set(result, value);
      return result;
    },
    admitSourceFreeResultPolicy(resultPolicy, limits) {
      if (resultPolicy?.kind !== 'data_policy' ||
          typeof resultPolicy.cid !== 'string' ||
          typeof resultPolicy.wire !== 'string' ||
          !Number.isSafeInteger(limits?.maxWireBytes) ||
          !Number.isSafeInteger(limits?.maxNodes) ||
          !Number.isSafeInteger(limits?.maxDepth)) {
        throw new TypeError('InvalidHostResultDataPolicy');
      }
      const original = checked(moon.clientProgramAdmitSourceFreeResultPolicyBody(
        resultPolicy.cid, resultPolicy.wire,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({kind: runtimeField(original, 0), cid: runtimeField(original, 1),
        wire: runtimeField(original, 2)});
    },
    adoptCheckedClientEffectInferRun(allowed, definition, resultPolicy, limits) {
      if (resultPolicy !== undefined &&
          (resultPolicy?.kind !== 'data_policy' ||
           typeof resultPolicy.cid !== 'string' ||
           typeof resultPolicy.wire !== 'string' ||
           !Number.isSafeInteger(limits?.maxWireBytes) ||
           !Number.isSafeInteger(limits?.maxNodes) ||
           !Number.isSafeInteger(limits?.maxDepth))) {
        throw new TypeError('InvalidHostResultDataPolicy');
      }
      const value = checked(resultPolicy === undefined
        ? moon.clientProgramEffectAllowedInferRun(allowed)
        : moon.clientProgramEffectAllowedInferRunWithPolicyBody(
          allowed, resultPolicy.cid, resultPolicy.wire,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      if (!moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Effect Infer Run Definition differs from admission');
      }
      const result = Object.freeze({kind: 'infer',
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(result, value);
      return result;
    },
    compiledSourceFreeResultPolicy,
    // Borrow the original admitted Effect compilation. No fresh Program,
    // authorization, Source observation or Command approval is issued here.
    adoptCheckedClientEffectSerializationRun(allowed, definition) {
      const value = compiledRunResult(moon.clientProgramEffectAllowedSerializationRun(allowed),
        'RunHostEffectContentAdmissionRejected');
      if (!moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Effect Content Run Definition differs from admission');
      }
      const result = Object.freeze({kind: 'serialization',
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(result, value);
      return result;
    },
    compiledSerializationGraph(compiled) {
      const value = compiledContent(compiled);
      const graph = moon.clientProgramCompiledRunSerializationGraph(value);
      if (graph === undefined) throw new TypeError('Content compilation graph unavailable');
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const selected = Object.freeze({task: runtimeField(coordinates, 0), step: runtimeField(coordinates, 1),
        wire: moon.clientProgramSerializationPlanGraphWire(graph)});
      serializationPlanTokens.set(selected, graph);
      return selected;
    },
    checkedClientSerializationGenerationLimits(compiled, selection) {
      const value = compiledContent(compiled);
      const graph = serializationPlanTokens.get(selection);
      if (graph === undefined || moon.clientProgramCompiledRunSerializationGraph(value) !== graph) {
        throw new TypeError('Foreign Content compilation graph');
      }
      // Read only the same nominal compiler output, not the caller-visible
      // wire/coordinates. These quantities constrain generation; they supply
      // neither current permission nor physical capacity or cleanup evidence.
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const id = `task_${runtimeField(coordinates, 0)}_serialize_${runtimeField(coordinates, 1)}`;
      const body = JSON.parse(moon.clientProgramSerializationPlanGraphWire(graph));
      const nodes = body.nodes?.filter(node => node.kind === 'content_barrier' && node.node_id === id);
      const bounds = nodes?.length === 1 ? nodes[0].barrier?.serialization?.bounds : undefined;
      if (bounds === undefined || !['max_rows', 'max_bytes'].every(name =>
        Number.isInteger(bounds[name]) && bounds[name] >= 0 && bounds[name] <= 2147483647)) {
        throw new TypeError('Content compilation generation bounds unavailable');
      }
      return Object.freeze({maxRows: bounds.max_rows, maxBytes: bounds.max_bytes});
    },
    inferSerializationGraph(inferGraph) {
      const graph = moon.clientProgramInferPlanSerializationGraph(inferGraph);
      if (graph === undefined) return undefined;
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const selected = Object.freeze({task: runtimeField(coordinates, 0), step: runtimeField(coordinates, 1),
        wire: moon.clientProgramSerializationPlanGraphWire(graph)});
      serializationPlanTokens.set(selected, graph);
      return selected;
    },
    compiledSerializationPolicy(compiled) {
      const value = compiledContent(compiled);
      const body = moon.clientProgramSerializationPolicyBody(value);
      return body === undefined ? undefined : Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)});
    },
    bindCheckedClientSerializationCapture(checkedProgram, graph, captured, observation) {
      const selection = serializationPlanTokens.get(graph);
      if (selection === undefined) throw new TypeError('Foreign Content compilation graph');
      if (typeof captured?.capture?.source !== 'function' || captured.logicalInput === undefined) {
        throw new TypeError('Invalid Content Source capture');
      }
      return compiledRunResult(moon.clientProgramAdmitSerializationCapturedInput(
        checkedProgram, selection, captured.capture.source(), captured.identity,
        captured.requirement, captured.logicalInput, observation.sourceEvidenceWire,
        observation.authorityScopeCid, observation.captureStartedAt, observation.captureCompletedAt,
        observation.keyedObservation?.observation),
      'RunHostContentCaptureRejected');
    },
    bindCheckedClientSerializationInputIdentity(compiled, input, receipt, limits, captured) {
      const value = compiledContent(compiled);
      issuanceLimits(limits, 'Content input Artifact');
      const evidence = compiledRunResult(moon.clientProgramSerializationInputIdentityBind(
        value, input, receipt, limits.maxWireBytes, limits.maxNodes, limits.maxDepth, captured),
      'RunHostContentInputIdentityRejected');
      const result = inspectEvidence(moon.clientProgramSerializationInputArtifact(evidence));
      serializationInputEvidenceTokens.set(result, evidence);
      return result;
    },
    bindCheckedClientEffectSerializationCapture(compiled, checkedEffect, captured, observation) {
      const value = compiledContent(compiled);
      if (typeof captured?.capture?.source !== 'function' || captured.logicalInput === undefined) {
        throw new TypeError('Invalid Effect Content Source capture');
      }
      return compiledRunResult(moon.clientProgramAdmitEffectSerializationCapturedInput(
        value, checkedEffect, captured.capture.source(), captured.identity,
        captured.requirement, captured.logicalInput, observation.sourceEvidenceWire,
        observation.authorityScopeCid, observation.captureStartedAt, observation.captureCompletedAt),
      'RunHostEffectContentCaptureRejected');
    },
    completeCheckedClientContentStep(compiled, definition, step, inputEvidence, candidate,
      content, available, limits) {
      const value = compiledContent(compiled);
      const identity = serializationInputEvidenceTokens.get(inputEvidence);
      if (identity === undefined) throw new TypeError('Foreign Content input identity');
      const generation = compiledRunResult(moon.clientProgramCompleteContentStep(
        step, value, token(definition), identity, candidate, content, available,
        limits.maxNodes, limits.maxTextBytes, limits.maxDepth, limits.maxWork, limits.maxNameBytes),
      'RunHostContentGenerationRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    completeCheckedClientSerializationGeneration(compiled, definition, input, inputEvidence, candidate,
      content, available, limits) {
      const value = compiledContent(compiled);
      const identity = serializationInputEvidenceTokens.get(inputEvidence);
      if (identity === undefined) throw new TypeError('Foreign Content input identity');
      const generation = compiledRunResult(moon.clientProgramSerializationGeneration(
        value, token(definition), input, identity, candidate, content, available, limits.maxNodes,
        limits.maxTextBytes, limits.maxDepth, limits.maxWork, limits.maxNameBytes),
      'RunHostContentGenerationRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    readmitCheckedClientSerializationGeneration(compiled, definition, graph, scope,
      expectedGenerationCid, evidence, candidate, content) {
      const run = compiledContent(compiled);
      const generation = compiledRunResult(moon.clientProgramReadmitSerializationGeneration(
        run, token(definition), graph, scope, expectedGenerationCid,
        evidenceToken(evidence.input), evidenceToken(evidence.derivation),
        evidenceToken(evidence.generation), candidate, content),
      'RunHostContentGenerationRecoveryRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    checkedClientSerializationByteHoldingCid(compiled, definition, storeAuthorityCid) {
      const value = compiledContent(compiled);
      return compiledRunResult(moon.clientProgramSerializationByteHoldingCid(
        value, token(definition), storeAuthorityCid), 'Client Content byte binding unavailable');
    },
    capturedContentGenerationCount(captured) {
      return compiledRunResult(moon.clientCapturedContentGenerationCount(token(captured)),
        'Captured Content inventory unavailable');
    },
    capturedContentGenerationStorage(captured, definition, storeAuthorityCid, index) {
      if (!Number.isSafeInteger(index) || index < 0) {
        throw new TypeError('Invalid Captured Content occurrence');
      }
      const value = compiledRunResult(moon.clientCapturedContentGenerationStorage(
        token(captured), token(definition), storeAuthorityCid, index),
      'Captured Content storage binding unavailable');
      return Object.freeze({holdingCid: runtimeField(value, 0), manifestCid: runtimeField(value, 1),
        contentCid: runtimeField(value, 2), byteCount: runtimeField(value, 3),
        bindings: Object.freeze(runtimeField(value, 4).map(binding => Object.freeze({
          name: runtimeField(binding, 0), semanticCid: runtimeField(binding, 1), wire: runtimeField(binding, 2), holdingCid: runtimeField(binding, 3),
        })))});
    },
    checkedClientSerializationRecoveryBindings(compiled, generation, storeAuthorityCid) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const bindings = compiledRunResult(moon.clientProgramSerializationRecoveryBindings(completion,
        value, storeAuthorityCid), 'Client Content recovery binding unavailable');
      return Object.freeze(bindings.map(binding => Object.freeze({
        name: runtimeField(binding, 0), semanticCid: runtimeField(binding, 1), wire: runtimeField(binding, 2), holdingCid: runtimeField(binding, 3),
      })));
    },
    checkedClientSerializationGenerationOutput(compiled, generation) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const output = moon.clientProgramSerializationGenerationOutput(completion, value);
      if (output === undefined) throw new TypeError('Client Content generation unavailable');
      return output;
    },
    exportCheckedClientContentGenerationOutput(compiled, definition, generation, storeAuthorityCid) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const exported = compiledRunResult(moon.clientProgramExportContentGenerationOutput(
        completion, value, token(definition), storeAuthorityCid),
      'Client Content completion export unavailable');
      return Object.freeze({binding: runtimeField(exported, 0), descriptorWire: runtimeField(exported, 1),
        rows: Object.freeze(runtimeField(exported, 2).slice())});
    },
    checkedClientSerializationGenerationEvidence(compiled, generation) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const evidence = moon.clientProgramSerializationGenerationEvidence(completion, value);
      if (evidence === undefined) throw new TypeError('Client Content generation unavailable');
      return inspectEvidence(evidence);
    },
    prepareCheckedClientRetainedContentOutput(compiled, definition, generation,
      storeAuthorityCid, completion, available) {
      const run = compiledRunTokens.get(compiled);
      const original = serializationGenerationTokens.get(generation);
      if (run === undefined || original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client retained Content output');
      }
      return compiledRunResult(moon.clientProgramPrepareRetainedContentOutput(
        original, run, token(definition), storeAuthorityCid, completion.binding,
        completion.descriptorWire, completion.rows, available),
      'Client Content completion recovery unavailable');
    },
    checkedClientCompiledEffectProgram(compiled, checkedEffect) {
      const value = compiledRunTokens.get(compiled);
      const original = value === undefined ? undefined
        : moon.clientProgramCompiledEffectProgram(value, checkedEffect);
      if (original === undefined) throw new TypeError('Foreign Client compiled Effect Run');
      return original;
    },
    checkedClientSerializationGenerationDerivation(compiled, generation) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const evidence = moon.clientProgramSerializationGenerationDerivation(completion, value);
      if (evidence === undefined) throw new TypeError('Client Content generation unavailable');
      return inspectEvidence(evidence);
    },
    issueCheckedClientSerializationInvocation(compiled, definition, generation, limits) {
      const value = compiledRunTokens.get(compiled);
      const completion = serializationGenerationTokens.get(generation);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      limits = captureContractLimits(limits, 'Content Invocation');
      const issued = compiledRunResult(moon.clientProgramIssueSerializationInvocation(
        value, token(definition), completion,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostContentInvocationRejected');
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    compiledInferSourceFreeResultPolicy: compiledSourceFreeResultPolicy,
    compiledInferEvaluationPolicy(compiled) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      const original = moon.clientProgramCompiledRunEvaluationPolicy(value);
      return original === undefined ? undefined : Object.freeze({
        kind: runtimeField(original, 0), cid: runtimeField(original, 1), wire: runtimeField(original, 2),
      });
    },
    checkClientCompiledRunOwner(compiled, checkedProgram) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          !moon.clientProgramCompiledRunMatches(value, checkedProgram)) {
        throw new TypeError('Foreign Client compiled Run');
      }
    },
    checkClientCompiledRunDefinition(compiled, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client compiled Run Definition');
      }
    },
    checkClientCompiledLocalExecutionOwner(compiled, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          moon.clientProgramCheckCompiledLocalExecutionOwner(value, token(definition)) !== true) {
        throw new TypeError('Foreign Client local execution owner');
      }
    },
    checkedClientRunCapturedContentCandidate(compiled, definition, acquisition, request,
      bindingWire, mediaType, contentCid, sizeBytes, limits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      return checked(moon.clientProgramRunCapturedContentCandidate(value, token(definition),
        acquisition, request, bindingWire, mediaType, contentCid, sizeBytes, ...limits));
    },
    checkedClientStoredRunCapturedContentCandidate(compiled, definition, acquisition,
      originalWire, bindingWire, limits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      return checked(moon.clientProgramStoredRunCapturedContentCandidate(value,
        token(definition), acquisition, originalWire, bindingWire, ...limits));
    },
    compiledRunResultTransformation(compiled, checkedProgram, result) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || !Number.isSafeInteger(result) || result < 0) {
        throw new TypeError('Foreign Client compiled Result');
      }
      return compiledRunResult(
        moon.clientProgramCompiledRunResultTransformation(
          value, checkedProgram, result), 'RunHostResultSelectionRejected');
    },
    clientRequiresQueryTime(prepared) {
      if (typeof moon.clientProgramRequiresQueryTime !== 'function') return false;
      const value = checked(moon.clientProgramRequiresQueryTime(prepared, 100000, 100000));
      if (typeof value !== 'boolean') throw new TypeError('Invalid Client query-time requirement');
      return value;
    },
    prepareClientQueryTime(prepared, request, createdAt) {
      if (typeof moon.clientProgramPrepareQueryTime !== 'function') {
        throw new TypeError('Client query-time preparation unavailable');
      }
      return checked(moon.clientProgramPrepareQueryTime(prepared, request, createdAt));
    },
    bindClientQueryTime(original, prepared, compiled, definition, request) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || typeof moon.clientProgramBindQueryTime !== 'function') {
        throw new TypeError('Foreign Client query-time compilation');
      }
      return checked(moon.clientProgramBindQueryTime(original, prepared, value, token(definition), request));
    },
    clientQueryTimeInvocationOriginal(original, prepared) {
      const project = moon.clientProgramQueryTimeInvocationOriginal;
      if (typeof project !== 'function') throw new TypeError('Client query-time original unavailable');
      // Opaque Option from the matching Core; never synthesize a JS tuple.
      return Reflect.apply(project, moon, [original, prepared]);
    },
    checkedClientManagedQueryInvocationOriginal(run, prepared, original) {
      const project = moon.clientProgramInstalledManagedRunInvocationOriginal;
      if (typeof project !== 'function') throw new TypeError('Client query-time original unavailable');
      const retained = Reflect.apply(project, moon, [run, prepared]);
      const compiled = compiledRunTokens.get(original.compiled);
      if (compiled === undefined || original.preparedProgram !== prepared ||
          runtimeOptionalField(retained, 0) !== original.queryTimePreparation ||
          runtimeOptionalField(retained, 1) !== original.requestIdentity ||
          runtimeOptionalField(retained, 2) !== compiled ||
          runtimeOptionalField(retained, 3) !== token(original.runDefinition) ||
          moon.clientProgramQueryTimeContext(original.queryTimePreparation) !== original.queryTime) {
        throw new TypeError('Foreign Client original query-time invocation');
      }
      control.checkClientCompiledRunOwner(original.compiled, prepared);
      return original;
    },
    restoreClientQueryTime(prepared, compiled, definition, request) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || typeof moon.clientProgramRestoreQueryTimePreparation !== 'function') {
        throw new TypeError('Foreign Client query-time compilation');
      }
      const preparation = checked(moon.clientProgramRestoreQueryTimePreparation(prepared, value, token(definition), request));
      const context = moon.clientProgramQueryTimeContext(preparation);
      if (context === undefined) throw new TypeError('Client query-time context unavailable');
      return Object.freeze({queryTimePreparation:preparation,queryTime:context});
    },
    defineCheckedClientCompiledRun(compiled, {namespaceId, runId,
      createdAt, validUntil, retainedDefinitionWire}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) {
        throw new TypeError('Foreign Client compiled Run');
      }
      return inspect(compiledRunResult(retainedDefinitionWire === undefined
        ? moon.clientProgramIssueCompiledRunDefinition(value,
          namespaceId, runId, createdAt, validUntil)
        : moon.clientProgramAdmitCompiledRunDefinition(value,
          retainedDefinitionWire), compiled.kind !== 'values'
        ? 'RunHostTaskDefinitionRejected'
        : retainedDefinitionWire === undefined
          ? 'RunHostSourceFreeDefinitionRejected'
          : 'RunHostSourceFreeAdmissionRejected'));
    },
    issueCheckedClientCompiledInvocation(compiled, definition,
      {dataPolicyCid, source}, limits, publicationPreparation, preparedProgram) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) {
        throw new TypeError('Foreign Client compiled Run');
      }
      limits = captureContractLimits(limits, 'Client Run Invocation');
      if (source !== undefined) {
        const sources = source.sources ?? [{captured: source.captured, sourceEvidence: source.sourceEvidence}];
        if (publicationPreparation === undefined || preparedProgram === undefined || compiled.kind !== 'tasks' ||
            !Array.isArray(sources) || sources.length < 1 || sources.length > 2 ||
            sources.some(({captured}) => captured?.capture === undefined || captured?.identity === undefined ||
              captured?.logicalInput === undefined)) {
          throw new TypeError('Invalid original publication invocation profile');
        }
        // The adopted original Plan selects the semantic input boundary.
        // A missing/copy/foreign capture cannot fall back to a Query ABI.
        const kind = checked(moon.clientProgramInstalledManagedPublicationSourceKind(
          publicationPreparation, preparedProgram));
        if (kind === 'whole-input') {
          if (sources.length !== 1 || source.keyedObservation !== undefined) {
            throw new TypeError('Invalid original publication invocation profile');
          }
          const {captured, sourceEvidence} = sources[0], capture = captured.capture;
          const original = Object.getOwnPropertyDescriptor(capture, 'originalWholeInput');
          if (original === undefined || !Object.hasOwn(original, 'value') || typeof original.value !== 'function') {
            throw new TypeError('Invalid original whole Source capture');
          }
          const issued = compiledRunResult(moon.clientProgramIssueWholeSourcePublicationInvocation(
            publicationPreparation, preparedProgram, value, token(definition),
            Reflect.apply(original.value, capture, []), captured.identity,
            evidenceToken(sourceEvidence), captured.logicalInput,
            source.authorityScopeCid, dataPolicyCid, source.captureStartedAt, source.captureCompletedAt,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostTaskInvocationRejected');
          return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
            invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
        }
        if (kind !== 'query' || sources.some(({captured}) => captured.requirement === undefined)) {
          throw new TypeError('Invalid original publication invocation profile');
        }
        const issued = compiledRunResult(moon.clientProgramIssueCapturedPublicationInvocation(
          publicationPreparation, preparedProgram, value, token(definition),
          sources.map(({captured}) => captured.capture.source()), sources.map(({captured}) => captured.identity),
          sources.map(({captured}) => captured.requirement), sources.map(({sourceEvidence}) => evidenceToken(sourceEvidence)),
          sources.map(({captured}) => captured.logicalInput), source.keyedObservation,
          source.authorityScopeCid, dataPolicyCid, source.captureStartedAt, source.captureCompletedAt,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostTaskInvocationRejected');
        return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
          invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
      }
      if (publicationPreparation !== undefined && compiled.kind !== 'values' && compiled.kind !== 'tasks') {
        throw new TypeError('Invalid original publication invocation profile');
      }
      const issued = compiledRunResult(publicationPreparation !== undefined
        ? moon.clientProgramIssuePublicationInvocation(publicationPreparation,
          preparedProgram, value, token(definition), dataPolicyCid,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : (compiled.kind !== 'values'
          ? moon.clientProgramIssueCompiledSourceFreeTaskInvocation(value,
            token(definition), dataPolicyCid,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
          : moon.clientProgramIssueCompiledValuesInvocation(value,
            token(definition), dataPolicyCid,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth))
      , 'RunHostInvocationRejected');
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    admitInferCapturedInput(prepared, captured, sourceEvidence, authorityScopeCid,
      dataPolicyCid, startedAt, completedAt) {
      return checked(moon.clientProgramAdmitInferCapturedInput(prepared,
        captured.inferStep, captured.capturedSource, captured.identity, captured.requirement,
        captured.logicalInput, evidenceToken(sourceEvidence), authorityScopeCid,
        dataPolicyCid, startedAt, completedAt));
    },
    admitComposedInferSources(occurrence, captures, sourceEvidence, authorityScopeCid,
      startedAt, completedAt, keyed) {
      return checked(moon.clientProgramAdmitComposedInferSources(occurrence,
        captures.map(value => value.capture.source()), captures.map(value => value.identity),
        captures.map(value => value.requirement), captures.map(value => value.logicalInput),
        sourceEvidence.map(evidenceToken), authorityScopeCid, startedAt, completedAt, keyed));
    },
    takeSourceEvidenceOriginal(capture) {
      const take = Object.getOwnPropertyDescriptor(capture ?? {}, 'takeSourceEvidenceOriginal')?.value;
      if (typeof take !== 'function') throw new TypeError('InstalledSourceEvidenceUnavailable');
      const evidence = inspectEvidence(Reflect.apply(take, capture, []));
      if (evidence.name !== 'source_evidence') throw new TypeError('InvalidInstalledSourceEvidence');
      return evidence;
    },
    keyedLookupPublicationEvidence(original) {
      const value = moon.clientProgramKeyedLookupObservationOriginals(original);
      if (value === undefined) throw new TypeError('Foreign keyed lookup observation');
      return Object.freeze({source: inspectEvidence(runtimeField(value, 1)),
        logicalRelationCid: runtimeField(value, 2)});
    },
    // Reuse the compiled owner retained at Run admission. The physical
    // adapter supplies its opaque execution and bounded verification owner;
    // this does not adopt external attempts or grant publication authority.
    modelPrivateHoldingCid(definition, storeAuthorityCid, role, slot) {
      const identity = moon.clientProgramModelPrivateHoldingCid(
        token(definition), storeAuthorityCid, role, slot);
      if (identity === undefined) throw new TypeError('InvalidModelPrivateHolding');
      return identity;
    },
    modelScopedPrivateHoldingCid(definition, storeAuthorityCid, entry, role, phase = 'settled') {
      const identity = moon.clientProgramModelScopedPrivateHoldingCid(token(definition),
        storeAuthorityCid, entry.scopeCid, entry.slotCid, entry.attemptCid,
        entry.attemptIndex, phase, role);
      if (identity === undefined) throw new TypeError('InvalidModelScopedPrivateHolding');
      return identity;
    },
    bindCheckedClientInferRun(compiled, execution, definition) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramBindInferRun(execution,
        value, token(definition)));
    },
    // Inspect only the original Core execution's issued value. Wire admission
    // remains a separate path; this view does not issue Store or send authority.
    inspectInferInvocationEvidence(originalMoon, execution, slot) {
      if (originalMoon !== moon || !Number.isSafeInteger(slot) || slot < 0 ||
          slot > 2147483647 ||
          typeof moon.clientProgramInferInvocationEvidence !== 'function') {
        throw new TypeError('Foreign Infer invocation evidence');
      }
      const evidence = moon.clientProgramInferInvocationEvidence(execution, slot);
      if (evidence === undefined) return undefined;
      if (moon.strategyRunEvidenceName(evidence) !== 'model_invocation_evidence') {
        throw new TypeError('Foreign Infer invocation evidence');
      }
      return inspectEvidence(evidence);
    },
    bindCheckedClientInferDispatch(compiled, execution, definition,
      {account, principalId, at, delegated, observeAccount, observeAt}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      if (typeof observeAccount !== 'function' ||
          typeof observeAt !== 'function') {
        throw new TypeError('Missing current Infer dispatch observations');
      }
      const admitted = checked(moon.clientProgramIssueInferDispatchAdmission(
        value, token(definition), account, principalId, at, delegated,
        observeAccount, observeAt));
      return checked(moon.clientProgramBindInferDispatchAdmission(execution,
        admitted));
    },
    readCheckedClientComposedInferSavedInputScope(compiled, definition, occurrence,
      graph, snapshotWire, authorityScopeCid, custodyAvailable) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' || typeof custodyAvailable !== 'function') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadSavedComposedInferInputScope(value, token(definition),
        occurrence, graph, snapshotWire, authorityScopeCid, custodyAvailable));
    },
    readCheckedClientInferSavedInputScope(compiled, definition, preparedProgram,
      step, graph, snapshotWire, authorityScopeCid, custodyAvailable) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' || typeof custodyAvailable !== 'function') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadSavedInferInputScope(value, token(definition),
        preparedProgram, step, graph, snapshotWire, authorityScopeCid, custodyAvailable));
    },
    bindCheckedClientInferModelScope(compiled, execution, definition,
      preparedCallSet, {scope, provider, expectedBoundary}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      // bindInferRun already retained this exact compilation in the active
      // owner. The portable binder compares actual input and every fixed call.
      checked(moon.clientProgramBindInferRun(execution, value, token(definition)));
      return checked(moon.clientProgramBindInferModelScope(execution,
        preparedCallSet, evidenceToken(scope), evidenceToken(provider), {...expectedBoundary,
          task_index: BigInt(expectedBoundary.task_index),
          strategy_revision: BigInt(expectedBoundary.strategy_revision)}));
    },
    bindCheckedClientInferModelDispatch(compiled, execution, definition,
      preparedCallSet, scope, {account, principalId, at, delegated,
        observeAccount, observeAt, enterCall}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function' ||
          typeof enterCall !== 'function') {
        throw new TypeError('Foreign Client compiled Infer dispatch');
      }
      const admitted = checked(moon.clientProgramIssueScopedInferDispatchAdmission(
        value, token(definition), scope, account, principalId, at, delegated,
        observeAccount, observeAt));
      checked(moon.clientProgramBindInferModelDispatch(execution, preparedCallSet,
        admitted, enterCall));
      return admitted;
    },
    // Installation-only async port. It uses the same original scoped
    // admission issuer; a persistence observation is never a fresh permit.
    bindCheckedClientInferModelEntryPersistence(compiled, execution, definition,
      preparedCallSet, scope, {account, principalId, at, delegated,
        observeAccount, observeAt, beginEntry}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function' ||
          typeof beginEntry !== 'function') {
        throw new TypeError('Foreign Client compiled Infer dispatch');
      }
      const admitted = checked(moon.clientProgramIssueScopedInferDispatchAdmission(
        value, token(definition), scope, account, principalId, at, delegated,
        observeAccount, observeAt));
      checked(moon.clientProgramBindInferModelEntryPersistence(execution,
        preparedCallSet, admitted, beginEntry));
      return admitted;
    },
    prepareCheckedClientRequestSerializationCompilation(parent, input, graph, contracts) {
      const original = serializationPlanTokens.get(graph);
      if (original === undefined) throw new TypeError('Foreign Content compilation graph');
      const compile = moon.clientProgramPrepareRequestSerializationCompilation;
      if (typeof compile !== 'function') throw new TypeError('Request Content compiler unavailable');
      // The actual typed constructor checks this SAME parent/input, checked
      // graph and contracts. No graph token or rebuilt compilation escapes.
      return compiledRunResult(Reflect.apply(compile, moon, [parent, input, original, contracts]),
        'RunHostTaskCompilationRejected');
    },
    prepareCheckedClientRequestKeyedSerializationCompilation(parent, input, selected, graph) {
      const original = serializationPlanTokens.get(graph);
      if (original === undefined) throw new TypeError('Foreign Content compilation graph');
      const compile = moon.clientProgramPrepareRequestKeyedSerializationCompilation;
      if (typeof compile !== 'function') throw new TypeError('Request keyed Content compiler unavailable');
      return compiledRunResult(Reflect.apply(compile, moon, [parent, input, selected, original]),
        'RunHostTaskCompilationRejected');
    },
    prepareCheckedClientRequestSerializationPlan(parent, input, request, compiled, definition,
      limits, workspace) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'serialization') {
        throw new TypeError('Foreign Client compiled Content preparation');
      }
      const prepare = moon.clientProgramPrepareRequestSerializationPlan;
      if (typeof prepare !== 'function') throw new TypeError('Request Content Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition),
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, workspace]));
    },
    prepareCheckedClientRequestModelSerializationPlan(parent, input, request, compiled, definition,
      limits, workspace, queryTime) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSerializationPlan;
      if (typeof prepare !== 'function') throw new TypeError('Request Model Content Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition),
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, workspace, queryTime]));
    },
    prepareCheckedClientEffectModelDemand(prepared, compiled, compilation, definition, occurrence, graph) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      // The nominal JS holder is not the native compiled Run. Unwrap only
      // its existing private association; Core binds the complete original
      // Effect/compilation/definition/occurrence tuple without another issuer.
      return checked(moon.clientProgramInstalledEffectModelDemandPrepare(
        prepared, value, compilation, token(definition), occurrence, graph));
    },
    prepareCheckedClientRequestModelSourceFreePlan(parent, input, original, request, compiled, definition,
      occurrence, graph, selected) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      // These are the original module, selected Limits and Run tokens. The
      // existing typed constructor checks their complete tuple; this binding
      // issues no Scope/Run and does not select bounds or compile again.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected]));
    },
    prepareCheckedClientRequestNodeModelSourceFreePlan(parent, input, original, request, compiled, definition,
      occurrence, graph, selected, installation) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestNodeModelSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Node Model Plan unavailable');
      const node = installation.nodeInstallation, census = installation.bootstrap;
      // SAME immutable installed declaration and opaque selected bounds. The
      // typed constructor validates layout/originals and the Request admits
      // these actual extents before Scope/read; no JS Ledger is constructed.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected, node.layout, node.installation,
        node.runtimeArtifactCid, node.layoutArtifactCid, node.probability,
        installation.modelRetainedBytes, installation.modelExecutionBytes,
        census.maxReservations, census.maxHoldings, census.maxDelegations]));
    },
    prepareCheckedClientRequestNodeModelCapturePlan(parent, input, original, request, compiled, definition,
      occurrence, graph, selected, installation) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestNodeModelCapturePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Node Model Plan unavailable');
      const node = installation.nodeInstallation, census = installation.bootstrap;
      // SAME immutable installed declaration and opaque selected bounds. The
      // typed constructor validates layout/originals and the Request admits
      // these actual extents before Scope/read; no JS Ledger is constructed.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected, node.layout, node.installation,
        node.runtimeArtifactCid, node.layoutArtifactCid, node.probability,
        installation.modelRetainedBytes, installation.modelExecutionBytes,
        census.maxReservations, census.maxHoldings, census.maxDelegations]));
    },
    bindCheckedClientMockModelCapturePlan(original, compiled, definition,
      occurrence, graph, selected) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const bind = moon.clientProgramInstalledMockModelCapturePlanBind;
      if (typeof bind !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(bind, moon, [original, value, token(definition),
        occurrence, graph, selected]));
    },
    checkedClientMockModelRunRequirements(prepared, compiled, definition, occurrence, graph,
      declarations, query, evidence, transport, scratch, registry, values, fragment, ordered) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInstalledMockModelManagedRunRequirements(
        prepared, value, token(definition), occurrence, graph, declarations,
        query, evidence, transport, scratch, registry, values, fragment, ordered));
    },
    prepareCheckedClientInferOriginalRead(compiled, definition, graph, scope, budget) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramPrepareInferOriginalRead(scope, value, token(definition),
        graph, budget.readRetainedBytes, budget.readExecutionBytes));
    },
    // Installation-only original bootstrap: caller custody must keep this
    // same scope on failure/recovery, never issue a replacement Ledger.
    // Initial allocation and the full preset projection require pre-funding
    // by the trusted installation; supplied numbers do not prove a layout.
    beginCheckedClientInferOriginalReadScope(compiled, definition, graph,
      {quantityCapacity, bootstrapRetainedBytes, bootstrapExecutionBytes,
        maxReservations, maxHoldings, maxDelegations}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramBeginInferOriginalReadScope(value,
        token(definition), graph, inferQuantityCapacity(quantityCapacity), bootstrapRetainedBytes,
        bootstrapExecutionBytes, maxReservations, maxHoldings, maxDelegations));
    },
    checkedClientInferOriginalReadScopeLive(compiled, definition, graph, scope) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof moon.clientProgramInferOriginalReadScopeLive !== 'function') {
        throw new TypeError('InferTrustedRuntimeScopeUnavailable');
      }
      // This lifetime observation neither exposes a Ledger nor substitutes
      // for allocation/current authority/egress or confirmed park invalidation.
      return moon.clientProgramInferOriginalReadScopeLive(scope, value,
        token(definition), graph) === true;
    },
    prepareCheckedClientInferNodeReadLayout(compiled, definition, graph, scope,
      {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramPrepareInferNodeReadLayout(scope, value,
        token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    // Data-only origin selection from the original checked Owner, before
    // park. Storage must be the same actual port's rechecked binding evidence;
    // matching strings/configuration cannot substitute for its opaque custody.
    checkedClientInferOriginalResourceOriginField(compiled, definition, graph, scope,
      {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}, storage, field) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInferOriginalResourceOriginField(scope,
        value, token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability, evidenceToken(storage), field));
    },
    checkCheckedClientInferOriginalParkedStorageOrigin(compiled, definition, graph, scope,
      park, document, {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}, storage) {
      const value = compiledRunTokens.get(compiled);
      const original = modelOriginalDocumentTokens.get(document);
      if (value === undefined || compiled.kind !== 'infer' || original === undefined) {
        throw new TypeError('Foreign Client original Model document');
      }
      return checked(moon.clientProgramCheckInferOriginalParkedStorageOrigin(scope,
        value, token(definition), graph, park, original, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability, evidenceToken(storage)));
    },
    // DATA-only comparison before a Scope exists. The existing Common Owner
    // reads expected origins from the checked Run/Plan, not this document.
    // Storage custody, funding and atomic original admission remain separate.
    checkCheckedClientInferOriginalPreRestoreOrigin(compiled, definition, graph, document, selected) {
      const value = compiledRunTokens.get(compiled);
      const original = modelOriginalDocumentTokens.get(document);
      if (value === undefined || compiled.kind !== 'infer' || original === undefined) {
        throw new TypeError('Foreign Client original Model document');
      }
      const originalDefinition = token(definition);
      if (typeof moon.clientProgramCheckInferOriginalPreRestoreOrigin !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      const {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability} = selected;
      return checked(moon.clientProgramCheckInferOriginalPreRestoreOrigin(value,
        originalDefinition, graph, original, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    // Explicit alternative to the normal descriptor issuer, not a fallback.
    // Bootstrap must already cover the dedicated Writer and finish-text borrow.
    prepareCheckedClientInferNodeReadState(compiled, definition, graph, scope,
      {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}, limits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      issuanceLimits(limits, 'Original Model state Writer');
      if (['maxWireBytes', 'maxNodes', 'maxDepth'].some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 0 || limits[key] > 2147483647) ||
        limits.maxNodes === 0) {
        throw new TypeError('Invalid original Model state Writer limits');
      }
      return checked(moon.clientProgramPrepareInferNodeReadState(scope, value,
        token(definition), graph, layout, installation, runtimeArtifactCid,
        layoutArtifactCid, probability, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    originalClientInferNodeReadStateRead(writer) {
      return checked(moon.clientProgramInferNodeReadStateRead(writer));
    },
    advanceCheckedClientInferNodeReadState(compiled, definition, graph, writer, quantum) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647) {
        throw new TypeError('Invalid original Model state Writer quantum');
      }
      const poll = moon.clientProgramInferNodeReadStatePoll(
        moon.clientProgramAdvanceInferNodeReadState(writer, value, token(definition), graph, quantum));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2)});
    },
    finishCheckedClientInferNodeReadState(compiled, definition, graph, writer) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramFinishInferNodeReadState(writer, value, token(definition), graph));
    },
    stopCheckedClientInferNodeReadState(compiled, definition, graph, scope, writer) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStopInferNodeReadState(writer, scope, value, token(definition), graph));
    },
    settleCheckedClientInferNodeReadState(compiled, definition, graph, writer, physicalCleanupComplete) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof physicalCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original read cleanup observation');
      }
      return checked(moon.clientProgramSettleInferNodeReadState(writer, value,
        token(definition), graph, physicalCleanupComplete));
    },
    // Do not derive whole-Run cleanup from read refusal, AbortSignal or a
    // saved response. The original census also checks every live child.
    finishCheckedClientInferOriginalReadScope(compiled, definition, graph,
      scope, originalRunCleanupComplete) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof originalRunCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original Run cleanup observation');
      }
      return checked(moon.clientProgramFinishInferOriginalReadScope(scope,
        value, token(definition), graph, originalRunCleanupComplete));
    },
    settleCheckedClientInferOriginalReadPreparation(compiled, definition, graph,
      read, physicalCleanupComplete) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof physicalCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original read cleanup observation');
      }
      return checked(moon.clientProgramSettleInferOriginalReadPreparation(read,
        value, token(definition), graph, physicalCleanupComplete));
    },
    stopCheckedClientInferOriginalReadPreparation(compiled, definition, graph,
      scope, read) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStopInferOriginalReadPreparation(scope,
        read, value, token(definition), graph));
    },
    claimCheckedClientInferOriginalComposedPreparation(compiled, definition, graph,
      read, readRetainedBytes, readExecutionBytes) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramClaimInferOriginalPreparation(read,
        value, token(definition), graph, readRetainedBytes, readExecutionBytes));
    },
    startCheckedClientOriginalComposedInferExecution(compiled, definition,
      occurrence, graph, prefix, inputs, provider, consumer, readRetainedBytes,
      readExecutionBytes, modelRetainedBytes, modelExecutionBytes, sources) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalComposedInferExecution(
        occurrence, graph, prefix, inputs, provider, value, token(definition),
        consumer, readRetainedBytes, readExecutionBytes, modelRetainedBytes,
        modelExecutionBytes, sources));
    },
    // Reuse the original compiled/definition token domains. A public wrapper
    // object cannot be passed as a nominal MoonBit compiled Run or contract.
    claimCheckedClientInferNodePreparationLayout(compiled, definition, graph, read,
      {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramClaimInferNodePreparationLayout(read,
        value, token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    startCheckedClientInferOriginalPreparation(compiled, definition, prepared,
      step, graph, registry, values, provider, consumer, readRetainedBytes,
      readExecutionBytes, modelRetainedBytes, modelExecutionBytes, fragment, ordered) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalInferExecution(prepared,
        step, graph, registry, values, provider, value, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes,
        modelExecutionBytes, fragment, ordered));
    },
    // Private installed Node inputs only. Canonical/body admission does not
    // issue capture authority, funded capacity or public async support.
    selectInstalledInitialJevDecisionProfile() {
      // Preserve the original Common value from THIS installed runtime. This
      // is the already registered physical precision selection, not a JS
      // reconstruction, provider capability, numerical loan or dispatch grant.
      if (typeof moon.clientProgramInitialJevDecisionProfile !== 'function') {
        throw new TypeError('Installed native Decision probability profile unavailable');
      }
      const profile = moon.clientProgramInitialJevDecisionProfile();
      if (profile === undefined || profile === null) {
        throw new TypeError('Installed native Decision probability profile unavailable');
      }
      return profile;
    },
    readInstalledModelResponseProfile(wire, expectedCid, limits) {
      issuanceLimits(limits, 'Model response profile');
      if (['maxWireBytes', 'maxNodes', 'maxDepth', 'maxMembers', 'maxWork']
          .some(key => !Number.isSafeInteger(limits[key]) || limits[key] < 0 ||
            limits[key] > 2147483647) ||
          typeof wire !== 'string' || wire.length > limits.maxWireBytes) {
        throw new TypeError('Invalid Model response profile limits');
      }
      return checked(moon.clientProgramReadModelResponseProfile(wire, expectedCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        limits.maxMembers, limits.maxWork));
    },
    bindInstalledModelRawCapturePolicy(policy, retention, metadata, clock, data) {
      return checked(moon.clientProgramBindModelRawCapturePolicy(
        evidenceToken(policy), retention, metadata, clock, data));
    },
    installedModelRawSelectionOriginals({retention, metadata, clock, data}) {
      // Existing Common bodies remain the authority for exact kind/CID/wire.
      // This projection cannot issue policy adoption, raw custody or sending.
      return moon.clientProgramModelRawSelectionOriginals(retention, metadata,
        clock, data).map(value => Object.freeze({kind: runtimeField(value, 0),
          cid: runtimeField(value, 1), wire: runtimeField(value, 2)}));
    },
    issueCheckedClientInferRawCapturePolicy(compiled, definition, dispatch, scope,
      {profile, installation, probability, storeAuthorityCid, retention, metadata,
        clock, data, selectedAt, availableUntil, deleteBy, extensionCeilingAt,
        metadataDeleteBy}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer raw policy');
      }
      return checked(moon.clientProgramIssueInferRawCapturePolicy(value,
        token(definition), dispatch, scope, profile, installation, probability,
        storeAuthorityCid, retention, metadata, clock, data, selectedAt,
        availableUntil, deleteBy, extensionCeilingAt, metadataDeleteBy));
    },
    registerCheckedClientInferRawCapture(compiled, definition, dispatch, scope,
      {policy, profile, installation, probability, account, at, storeAuthorityCid,
        selectionAvailable, observeAccount, observeAt, delegated}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof selectionAvailable !== 'function' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function') {
        throw new TypeError('Foreign Client compiled Infer raw capture');
      }
      return checked(moon.clientProgramRegisterInferRawCapture(value,
        token(definition), dispatch, scope, policy, profile, installation,
        probability, account, at, storeAuthorityCid, selectionAvailable,
        observeAccount, observeAt, delegated));
    },
    bindCheckedClientInferInvocation(compiled, execution, definition,
      verified, invocation, dataPolicyCid) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramBindInferInvocation(execution,
        value, token(definition), verified, token(invocation), dataPolicyCid));
    },
    bindIssuedClientInferInvocation(compiled, execution, definition, issued) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      const binding = checked(moon.clientProgramBindIssuedInferInvocation(
        execution, value, token(definition), issued));
      const result = Object.freeze({binding,
        observation: inspectEvidence(
          moon.clientProgramInferInvocationBindingObservation(binding)),
        invocation: inspect(
          moon.clientProgramInferInvocationBindingInvocation(binding))});
      inferInvocationTokens.set(result, {compiled: value, definition});
      return result;
    },
    checkedClientEffectInferInvocation(checkedEffect, compilation, definition, issued) {
      const retained = inferInvocationTokens.get(issued);
      if (retained === undefined || retained.definition.identity !== definition.identity ||
          !moon.clientProgramCompiledRunEffectMatches(retained.compiled, checkedEffect, compilation) ||
          !moon.clientProgramCheckCompiledRunDefinition(retained.compiled, token(definition)) ||
          moon.clientProgramInferInvocationBindingObservation(issued.binding) === undefined) {
        throw new TypeError('Foreign Effect Infer Invocation');
      }
      return Object.freeze({observation: issued.observation, invocation: issued.invocation,
        owner: token(issued.invocation)});
    },
    readCheckedClientInferSlotReplay(compiled, definition, observation,
      records, bundle, proofs, {maxSlots, maxSlotWireUnits}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadVerifiedInferSlotReplay(
        evidenceToken(observation), records, bundle, proofs, value, token(definition),
        maxSlots, maxSlotWireUnits));
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
    issueCheckedClientEffectCapturedInvocation(checkedEffect, compilation,
      admission, definition, capturedSource, source, limits) {
      issuanceLimits(limits, 'Client Effect Invocation');
      const issued = checked(moon.clientProgramIssueEffectCapturedInvocation(
        checkedEffect, compilation, admissionToken(admission), definition,
        capturedSource, source.sourceEvidenceWire, source.inputLogicalWire,
        source.sourceRef, source.sourceContractCid,
        source.authorityScopeCid, source.dataPolicyCid,
        source.captureStartedAt, source.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1)), owner: runtimeField(issued, 1)});
    },
    issueCheckedClientEffectMultiCapturedInvocation(checkedEffect, compilation,
      admission, definition, sources, context, limits) {
      issuanceLimits(limits, 'Client plural Effect Invocation');
      if (!Array.isArray(sources) || sources.length !== 2) {
        throw new TypeError('Incomplete Effect Source coverage');
      }
      const issued = checked(moon.clientProgramIssueEffectMultiCapturedInvocation(
        checkedEffect, compilation, admissionToken(admission), definition,
        sources.map(value => value.captured.capture.source()),
        sources.map(value => value.captured.identity),
        sources.map(value => value.captured.requirement),
        sources.map(value => value.sourceEvidenceWire),
        sources.map(value => moon.strategyRunEvidenceJson(value.captured.logicalInput)),
        context.authorityScopeCid, context.dataPolicyCid,
        context.captureStartedAt, context.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1)), owner: runtimeField(issued, 1)});
    },
    issueCheckedAcquiredLocalEffectInvocation(checkedEffect, capturedSource,
      identity, requirement, input, observation, authorityScopeCid,
      dataPolicyCid, limits) {
      issuanceLimits(limits, 'Acquired local Effect Invocation');
      return checked(moon.clientProgramIssueAcquiredLocalEffectInvocation(
        checkedEffect, capturedSource, identity, requirement, input,
        evidenceToken(observation), authorityScopeCid, dataPolicyCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    issueCheckedAcquiredEffectEvidence(checkedEffect, capturedSource,
      identity, requirement, input, observation, authorityScopeCid,
      dataPolicyCid, retention, limits, unit = 0, publicationRetention = retention) {
      issuanceLimits(limits, 'Acquired Effect evidence');
      if (!Number.isSafeInteger(unit) || unit < 0 || unit > 1) {
        throw new TypeError('Invalid acquired Effect Unit');
      }
      const issued = checked(unit === 0 && publicationRetention === retention
        ? moon.clientProgramIssueAcquiredEffectEvidence(
          checkedEffect, capturedSource, identity, requirement, input,
          evidenceToken(observation), authorityScopeCid, dataPolicyCid,
          token(retention), limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : moon.clientProgramIssueAcquiredEffectEvidenceAt(
          checkedEffect, unit, capturedSource, identity, requirement, input,
          evidenceToken(observation), authorityScopeCid, dataPolicyCid,
          token(retention), token(publicationRetention),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        invocation: moon.clientProgramAcquiredEffectInvocation(issued),
        bodies: Object.freeze([
          ...moon.clientProgramAcquiredEffectDependencyBodies(issued)
            .map(pair => Object.freeze({kind: runtimeField(pair, 0), wire: runtimeField(pair, 1),
              ...(runtimeField(pair, 0) === 'request_values' ? {
                cid: moon.clientProgramAcquiredEffectRequestCid(issued),
              } : {})})),
          Object.freeze({kind: 'result_retention_policy',
            wire: inspect(token(publicationRetention)).wire}),
        ]),
        catalogBodies: Object.freeze(checked(
          moon.clientProgramAcquiredEffectCatalogBodies(issued,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth))
          .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1),
            wire: runtimeField(body, 2)}))),
      });
      localEffectDependencyTokens.set(value, {kind: 'acquired', issued});
      return value;
    },
    issueSourceFreeEffectEvidence(owner, unit, limits) {
      issuanceLimits(limits, 'Source-free Effect dependency');
      const invocation = checked(moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        owner, unit, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const scope = control.seal('acquisition_scope',
        '{"sources":[],"version":"actql-acquisition-scope/0.1"}', limits);
      const value = Object.freeze({invocation, bodies: Object.freeze([
        Object.freeze({kind: 'acquisition_scope', wire: scope.wire}),
      ])});
      localEffectDependencyTokens.set(value, {kind: 'source_free', issued: invocation});
      return value;
    },
    issueEffectResultImportObservation(owner, inputs, captured, manifest,
      artifact, limits) {
      issuanceLimits(limits, 'Effect Result import observation');
      const ownedManifest = localEffectManifestTokens.get(manifest);
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedManifest === undefined || ownedArtifact === undefined) {
        throw new TypeError('Foreign Effect Result import evidence');
      }
      const issued = checked(moon.clientProgramIssueEffectResultImportObservation(
        owner, inputs, captured, ownedManifest, ownedArtifact,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        wire: moon.clientProgramEffectResultImportObservationJson(issued),
      });
      localEffectImportTokens.set(value, issued);
      return value;
    },
    issueImportedEffectEvidence(owner, inputs, unit, observations, limits) {
      issuanceLimits(limits, 'Imported Effect evidence');
      if (!Array.isArray(observations)) {
        throw new TypeError('Invalid Effect Result import observations');
      }
      const owned = observations.map(value => {
        const issued = localEffectImportTokens.get(value);
        if (issued === undefined) {
          throw new TypeError('Foreign Effect Result import observation');
        }
        return issued;
      });
      const issued = checked(moon.clientProgramIssueImportedEffectEvidence(
        owner, inputs, unit, owned, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const value = Object.freeze({
        invocation: moon.clientProgramImportedEffectInvocation(issued),
        bodies: Object.freeze([
          Object.freeze({kind: 'acquisition_scope',
            wire: moon.clientProgramImportedEffectScopeJson(issued)}),
          ...observations.map(value => Object.freeze({
            kind: 'result_import_observation', wire: value.wire})),
          ...moon.clientProgramImportedEffectRelationBodies(issued).map(wire =>
            Object.freeze({kind: 'acquisition_relation', wire})),
        ]),
      });
      localEffectDependencyTokens.set(value, {kind: 'imported', issued});
      return value;
    },
    issueDependentLocalEffectResultArtifact(owner, inputs, exported,
      dependency, definition, receipt, retention, context, limits) {
      issuanceLimits(limits, 'Dependent local Effect Result Artifact');
      const owned = localEffectDependencyTokens.get(dependency);
      if (owned === undefined) {
        throw new TypeError('Foreign local Effect dependency evidence');
      }
      const exactContext = localEffectContext(context);
      const result = owned.kind === 'source_free'
        ? moon.clientProgramIssueSourceFreeExportedLocalEffectResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'acquired'
        ? moon.clientProgramIssueAcquiredEffectLocalResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : moon.clientProgramIssueImportedEffectLocalResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth);
      return inspectLocalEffectArtifact(checked(result));
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
      limits = captureContractLimits(limits, 'Run Definition');
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
      )), limits);
    },
    issueEffectFreeRunReceipt(chain, provenance, limits) {
      limits = captureContractLimits(limits, 'Run Receipt');
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
        contentCaptures(provenance.contentGenerations),
      )), limits);
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
    capturedEffectSourceMatchesPreview(preview, memberIndex, invocation,
      source, localEvidence, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'captured Effect source Preview');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0 || typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid captured Effect source Preview');
      }
      return checked(moon.strategyCapturedEffectSourceMatchesPreview(ownedPreview,
        memberIndex, token(invocation), effectSourceToken(source),
        localEffectSourceToken(localEvidence), storeAuthorityCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    reserveEffectCaptureRecovery(parent, input, request, runDefinition, encryptedBytes, limits) {
      issuanceLimits(limits, 'Effect capture recovery');
      if (!Number.isSafeInteger(encryptedBytes) || encryptedBytes < 0 || encryptedBytes > 2147483647 ||
          typeof moon.clientProgramReserveRequestEffectCaptureRecovery !== 'function') {
        throw new TypeError('Invalid Effect capture recovery Resource');
      }
      return checked(moon.clientProgramReserveRequestEffectCaptureRecovery(
        parent, input, request, token(runDefinition), encryptedBytes,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    admitCapturedEffectSourceFromCapture(preview, memberIndex, invocation,
      artifact, capturedRun, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'recovered Effect source');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0 || typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid recovered Effect source');
      }
      return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromCapture(
        ownedPreview, memberIndex, token(invocation), token(artifact),
        token(capturedRun), storeAuthorityCid, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth)));
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
    issueEffectTableSourceArtifactFromExport(input, receipt, invocation,
      retention, sourceBindingCid, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'private Table source Artifact');
      if (typeof moon.clientProgramIssueEffectTableSourceArtifact !== 'function' ||
          typeof sourceBindingCid !== 'string' || typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid private Table source export');
      }
      return inspect(checked(moon.clientProgramIssueEffectTableSourceArtifact(
        input, receipt, token(invocation), token(retention), sourceBindingCid,
        storeAuthorityCid, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    admitCapturedEffectSourceFromTableInput(preview, memberIndex, invocation,
      artifact, input, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'captured private Table source');
      const ownedPreview = computationPreviewTokens.get(preview);
      const ownedInput = localEffectArtifactTokens.get(input);
      if (ownedPreview === undefined || ownedInput === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Invalid captured private Table source owner');
      }
      const relation = checked(moon.strategyPublicationAdmit('result_artifact',
        moon.clientProgramLocalEffectResultArtifactJson(ownedInput),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromTableInput(
        ownedPreview, memberIndex, token(invocation), token(artifact), relation,
        storeAuthorityCid)));
    },
    admitCapturedEffectSourceFromResult(preview, memberIndex, invocation,
      artifact, result, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'captured Table source');
      const ownedPreview = computationPreviewTokens.get(preview);
      const ownedResult = localEffectArtifactTokens.get(result);
      if (ownedPreview === undefined || ownedResult === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Invalid captured Table source owner');
      }
      const publicationResult = checked(moon.strategyPublicationAdmit('result_artifact',
        moon.clientProgramLocalEffectResultArtifactJson(ownedResult),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromResult(
        ownedPreview, memberIndex, token(invocation), token(artifact),
        publicationResult, storeAuthorityCid)));
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
      return inspectLocalEffectArtifact(issued);
    },
    issueSourceFreeExportedLocalEffectResultArtifact(owner, inputs, exported,
      definition, invocation, receipt, retention, context, limits) {
      issuanceLimits(limits, 'source-free local Manifest Result');
      return inspectLocalEffectArtifact(checked(
        moon.clientProgramIssueSourceFreeExportedLocalEffectResultArtifact(
          owner, inputs, exported, invocation, definition, receipt,
          token(retention), ...localEffectContext(context),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    issueSourceFreeLocalEffectTableArtifact(owner, inputs, memberIndex,
      importing, definition, localInvocation, receipt, retention, context, limits) {
      issuanceLimits(limits, 'private Table semantic Artifact');
      if (!Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Invalid private Table member');
      }
      return inspectLocalEffectArtifact(checked(
        moon.clientProgramIssueSourceFreeLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, localInvocation,
          receipt, token(retention), ...localEffectContext(context),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    issueDependentLocalEffectTableArtifact(owner, inputs, memberIndex,
      importing, dependency, definition, receipt, retention, context, limits) {
      issuanceLimits(limits, 'dependent private Table semantic Artifact');
      const owned = localEffectDependencyTokens.get(dependency);
      if (owned === undefined || !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign private Table dependency evidence');
      }
      const exactContext = localEffectContext(context);
      const result = owned.kind === 'source_free'
        ? moon.clientProgramIssueSourceFreeLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, owned.issued,
          receipt, token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'imported'
        ? moon.clientProgramIssueImportedLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, owned.issued,
          receipt, token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : undefined;
      if (result === undefined) {
        throw new TypeError('UnavailableAcquiredPrivateTableEvidence');
      }
      return inspectLocalEffectArtifact(checked(result));
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
    prepareEffectCommandContentArtifact(owner, inputs, memberIndex, artifact, limits) {
      const owned = localEffectArtifactTokens.get(artifact);
      if (owned === undefined || ![memberIndex, limits?.maxFields, limits?.maxWork]
        .every(value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid original Effect Content Artifact');
      }
      checked(moon.clientProgramEffectCommandContentPrepareArtifact(
        owner, inputs, memberIndex, owned, limits.maxFields, limits.maxWork));
    },
    releaseEffectCommandContentArtifact(artifact, quantum) {
      const owned = localEffectArtifactTokens.get(artifact);
      if (owned === undefined || !Number.isSafeInteger(quantum) || quantum <= 0) {
        throw new TypeError('Invalid original Effect Content retirement');
      }
      return moon.clientProgramEffectCommandContentReleaseArtifact(owned, quantum);
    },
    borrowEffectCommandContent(owner, inputs, memberIndex, artifact, row,
      inputName, limits) {
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      if (ownedArtifact === undefined || typeof inputName !== 'string' ||
          ![memberIndex, row, limits?.maxFields, limits?.maxWork].every(
            value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid original Effect Content input');
      }
      const view = checked(moon.clientProgramEffectCommandContentBorrow(
        owner, inputs, memberIndex, ownedArtifact, row, inputName,
        limits.maxFields, limits.maxWork));
      let original = {view, owner, inputs, memberIndex,
        artifact: ownedArtifact, row, inputName};
      const current = () => original !== undefined &&
        moon.clientProgramEffectCommandContentMatches(original.view,
          original.owner, original.inputs, original.memberIndex,
          original.artifact, original.row, original.inputName);
      // A physical preparation retains this view before awaiting. Its wire is
      // observed DATA, not byte custody, a capacity loan or a read/send grant.
      return Object.freeze({binding: view, current,
        matchesIssued(issued) {
          const retained = original;
          return retained !== undefined &&
            moon.clientProgramEffectCommandContentMatchesIssued(retained.view, issued) &&
            original === retained;
        },
        wire() {
          if (!current()) throw new TypeError('Original Effect Content unavailable');
          return checked(moon.clientProgramEffectCommandContentWire(original.view));
        },
        release() {
          if (original === undefined) return;
          moon.clientProgramEffectCommandContentRelease(original.view);
          original = undefined;
        }});
    },
    recoverEffectCommandContent({compiled, prepared, definition, captured, preview,
      invocation, source, storeAuthorityCid, generationIndex, memberIndex, row,
      inputName, candidate, issued, limits}) {
      issuanceLimits(limits, 'Recovered Effect Content');
      const run = compiledContent(compiled);
      const admittedPreview = computationPreviewTokens.get(preview);
      if (admittedPreview === undefined || typeof inputName !== 'string' ||
          ![generationIndex, memberIndex, row, limits.maxFields, limits.maxWork]
            .every(value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid recovered Effect Content input');
      }
      const original = {run, prepared, definition: token(definition), captured: token(captured),
        preview: admittedPreview, memberIndex, row, inputName};
      const view = checked(moon.clientProgramRecoverEffectCommandContent(run, prepared,
        original.definition, original.captured, admittedPreview, token(invocation), effectSourceToken(source),
        storeAuthorityCid, generationIndex, memberIndex, row, inputName, candidate, issued,
        limits.maxFields, limits.maxWork, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      let retained = original;
      const current = () => retained !== undefined &&
        moon.clientProgramRecoveredEffectCommandContentMatches(view, original.run,
          original.prepared, original.definition, original.captured, original.preview,
          original.memberIndex, original.row, original.inputName) && retained === original;
      return Object.freeze({binding: view, current,
        matchesIssued(value) {
          return retained !== undefined &&
            moon.clientProgramRecoveredEffectCommandContentMatchesIssued(view, value) &&
            retained === original;
        },
        wire() {
          if (!current()) throw new TypeError('Recovered Effect Content unavailable');
          return checked(moon.clientProgramRecoveredEffectCommandContentWire(view));
        },
        release() {
          if (retained === undefined) return;
          moon.clientProgramRecoveredEffectCommandContentRelease(view);
          retained = undefined;
        }});
    },
    localEffectTableStorageMapping(artifact, limits) {
      issuanceLimits(limits, 'Table storage mapping');
      const owned = localEffectArtifactTokens.get(artifact);
      if (owned === undefined) throw new TypeError('Foreign Table input Artifact');
      const issued = checked(moon.clientProgramLocalEffectTableStorageMapping(
        owned, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({
        identity: moon.clientProgramLocalTableStorageMappingCid(issued),
        wire: moon.clientProgramLocalTableStorageMappingJson(issued),
      });
    },
    admitLocalTableStorageMapping(wire, limits) {
      issuanceLimits(limits, 'Local Table storage mapping');
      if (typeof wire !== 'string') throw new TypeError('Invalid Local Table mapping');
      const admitted = checked(moon.clientProgramAdmitLocalTableStorageMapping(
        wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({
        identity: moon.clientProgramLocalTableStorageMappingCid(admitted),
        wire: moon.clientProgramLocalTableStorageMappingJson(admitted),
      });
    },
    bindTableInput(owner, inputs, memberIndex, artifact, identity, scope,
      operationWire, mappingWire, limits) {
      issuanceLimits(limits, 'Table input');
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      const ownedIdentity = localEffectIdentityTokens.get(identity);
      if (ownedArtifact === undefined || ownedIdentity === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          typeof operationWire !== 'string' || typeof mappingWire !== 'string') {
        throw new TypeError('Invalid Table input owner');
      }
      const issued = checked(moon.clientProgramBindTableInput(
        owner, inputs, memberIndex, ownedArtifact, ownedIdentity, scope,
        operationWire, mappingWire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      // Content/owner binding only. Nothing stages or dispatches a Table write.
      const value = Object.freeze({
        wire: moon.clientProgramTableInputOperationJson(issued),
      });
      tableInputTokens.set(value, issued);
      return value;
    },
    tableInputMatchesSource(input, artifact, identity) {
      const ownedInput = tableInputTokens.get(input);
      const ownedArtifact = localEffectArtifactTokens.get(artifact);
      const ownedIdentity = localEffectIdentityTokens.get(identity);
      if (ownedInput === undefined || ownedArtifact === undefined ||
          ownedIdentity === undefined) {
        throw new TypeError('Foreign Table input source');
      }
      return moon.clientProgramTableInputMatchesSource(ownedInput,
        ownedArtifact, ownedIdentity);
    },
    tableInputStorageMappingWire(input) {
      const owned = tableInputTokens.get(input);
      if (owned === undefined) throw new TypeError('Foreign Table input');
      return moon.clientProgramTableInputStorageMappingJson(owned);
    },
    tableInputSchemaWire(input) {
      const owned = tableInputTokens.get(input);
      if (owned === undefined) throw new TypeError('Foreign Table input');
      return moon.clientProgramTableInputSchemaWire(owned);
    },
    checkRecoveredTableSchemaWire(preview, wire, limits) {
      issuanceLimits(limits, 'recovered Table schema');
      const owned = recoveredTablePreviewTokens.get(preview);
      if (owned === undefined || typeof wire !== 'string') {
        throw new TypeError('Foreign recovered Table schema');
      }
      checked(moon.clientProgramCheckRecoveredTableSchemaWire(owned, wire,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return wire;
    },
    bindRecoveredTablePreview(preview, memberIndex, invocation, source,
      capturedRun, scope, mappingWire, storeAuthorityCid, limits, tableLimits) {
      issuanceLimits(limits, 'recovered Table Preview');
      issuanceLimits(tableLimits, 'recovered Table material');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0 || typeof mappingWire !== 'string' ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid recovered Table Preview');
      }
      const issued = checked(moon.clientProgramBindRecoveredTablePreview(
        ownedPreview, memberIndex, token(invocation), effectSourceToken(source),
        token(capturedRun), scope, mappingWire, storeAuthorityCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        tableLimits.maxWireBytes, tableLimits.maxNodes, tableLimits.maxDepth));
      const value = Object.freeze({
        subjectCid: moon.clientProgramRecoveredTablePreviewSubjectCid(issued),
        operationWire: moon.clientProgramRecoveredTablePreviewOperationJson(issued),
        mappingWire: moon.clientProgramRecoveredTablePreviewMappingJson(issued),
      });
      recoveredTablePreviewTokens.set(value, issued);
      return value;
    },
    recoveredTablePreviewMatchesSource(preview, source) {
      const owned = recoveredTablePreviewTokens.get(preview);
      if (owned === undefined) throw new TypeError('Foreign recovered Table Preview');
      return moon.clientProgramRecoveredTablePreviewMatchesSource(owned,
        effectSourceToken(source));
    },
    bindTablePreview(input, capturedPreview, memberIndex) {
      const ownedInput = tableInputTokens.get(input);
      if (ownedInput === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0) throw new TypeError('Invalid Table Preview input');
      const issued = checked(moon.clientProgramBindTablePreview(ownedInput,
        capturedPreview, memberIndex));
      const value = Object.freeze({
        subjectCid: moon.clientProgramTablePreviewSubjectCid(issued),
        operationWire: moon.clientProgramTablePreviewOperationJson(issued),
      });
      tablePreviewTokens.set(value, issued);
      return value;
    },
    tablePreviewInputAvailable(preview) {
      const owned = tablePreviewTokens.get(preview);
      if (owned === undefined) throw new TypeError('Foreign Table Preview');
      return moon.clientProgramTablePreviewInputAvailable(owned);
    },
    localTableCommitResponse(responseWire, statusCode, limits) {
      issuanceLimits(limits, 'Local Table physical response');
      if (typeof responseWire !== 'string' || !Number.isSafeInteger(statusCode)) {
        throw new TypeError('Invalid Local Table physical response');
      }
      return checked(moon.clientProgramLocalTableCommitResponse(responseWire,
        statusCode, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    tablePreviewCommitOutcome(preview, responseWire, statusCode, limits) {
      issuanceLimits(limits, 'Table commit outcome');
      const owned = tablePreviewTokens.get(preview);
      const recovered = recoveredTablePreviewTokens.get(preview);
      if (recovered !== undefined && typeof responseWire === 'string' &&
          Number.isSafeInteger(statusCode)) {
        return checked(moon.clientProgramRecoveredTablePreviewCommitOutcome(
          recovered, responseWire, statusCode, limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth));
      }
      if (owned === undefined || typeof responseWire !== 'string' ||
          !Number.isSafeInteger(statusCode)) {
        throw new TypeError('Invalid Table commit response owner');
      }
      return checked(moon.clientProgramTablePreviewCommitOutcome(owned,
        responseWire, statusCode, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
    },
    tablePreviewLedgerBinding(preview) {
      const owned = tablePreviewTokens.get(preview);
      const recovered = recoveredTablePreviewTokens.get(preview);
      if (recovered !== undefined) {
        const identity = moon.clientProgramRecoveredTablePreviewLedgerIdentity(recovered);
        const memberIndex = moon.clientProgramRecoveredTablePreviewMemberIndex(recovered);
        return Object.freeze({preview: identity, memberIndex,
          rowPreviewCid: moon.strategyEffectPreviewOrderedRowCid(identity, memberIndex, 0),
          operationWire: moon.clientProgramRecoveredTablePreviewOperationJson(recovered)});
      }
      if (owned === undefined) throw new TypeError('Foreign Table Preview');
      const identity = moon.clientProgramTablePreviewLedgerIdentity(owned);
      const memberIndex = moon.clientProgramTablePreviewMemberIndex(owned);
      return Object.freeze({
        preview: identity, memberIndex,
        rowPreviewCid: moon.strategyEffectPreviewOrderedRowCid(identity, memberIndex, 0),
        operationWire: moon.clientProgramTablePreviewOperationJson(owned),
      });
    },
    admitTablePreviewClaim(preview, claim) {
      const binding = control.tablePreviewLedgerBinding(preview);
      return checked(moon.strategyEffectMemberRowAdmit(binding.preview,
        binding.memberIndex, 0, 'store', claim.scope, binding.rowPreviewCid,
        claim.locator, claim.key));
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
    effectTableSourceArtifactPreviewBinding(artifact, invocationCid, sourceTableInput,
      storeAuthorityCid) {
      return checked(moon.clientProgramEffectTableSourceArtifactPreviewBinding(
        token(artifact), invocationCid, sourceTableInput, storeAuthorityCid));
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
    async admitCompletedResultSnapshot(exportHandle, outputLimits, signal, publicationResource) {
      if (publicationResource !== undefined) {
        return finishProgramSnapshot(publicationResource, exportHandle, signal);
      }
      // Bare row emission and captured admission share this bound; the latter
      // includes the canonical relation wrapper. Borrow the existing checked
      // output policy without constructing a second quota or projection cache.
      if (outputLimits === null || typeof outputLimits !== 'object' ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireBytes) ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireNodes) ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireDepth) ||
          outputLimits.maxLogicalWireBytes < 0 || outputLimits.maxLogicalWireBytes > 2147483647 ||
          outputLimits.maxLogicalWireNodes < 0 || outputLimits.maxLogicalWireNodes > 2147483647 ||
          outputLimits.maxLogicalWireDepth < 0 || outputLimits.maxLogicalWireDepth > 2147483647) {
        throw new TypeError('Invalid completed Result snapshot output limits');
      }
      signal?.throwIfAborted();
      const preparation = checked(moon.strategyHostOutputSnapshotBegin(
        exportHandle, outputLimits.maxLogicalWireBytes,
        outputLimits.maxLogicalWireNodes, outputLimits.maxLogicalWireDepth));
      let finished = false;
      try {
        while (true) {
          signal?.throwIfAborted();
          if (checked(moon.strategyHostOutputSnapshotAdvance(
            preparation, 256))) break;
          await new Promise(resolve => setTimeout(resolve, 0));
        }
        signal?.throwIfAborted();
        const snapshot = inspectSnapshot(checked(
          moon.strategyHostOutputSnapshotFinish(preparation)));
        finished = true;
        return snapshot;
      } finally {
        if (!finished) moon.strategyHostOutputSnapshotCancel(preparation);
      }
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
    async issueEffectFreeCapturedRun(chain, evidence, limits, signal, publicationResource) {
      limits = captureContractLimits(limits, 'Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence)) {
        throw new TypeError('Invalid Captured Run request');
      }
      signal?.throwIfAborted();
      if (publicationResource !== undefined) {
        if (evidence.pendingSourceStateAdvances.length !== 0 ||
            evidence.modelEvidence.length !== 0 ||
            (evidence.contentGenerations !== undefined &&
              (!Array.isArray(evidence.contentGenerations) ||
                evidence.contentGenerations.length !== 0))) {
          throw new TypeError('Invalid original program capture profile');
        }
        const capture = checked(moon.clientProgramPrepareCapture(
          publicationResource, token(chain.runDefinition), token(chain.invocation),
          chain.definitions.map(token), chain.artifacts.map(token),
          token(chain.manifest), token(chain.receipt),
          evidence.snapshots.map(snapshotToken),
          evidenceToken(evidence.authoringContext),
          evidence.modelEvidence.map(evidenceToken),
        ));
        return finishProgramCapture(capture, signal);
      }
      const preparation = moon.strategyBeginOriginalEffectFreeCapturedRun(
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
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
        contentCaptures(evidence.contentGenerations),
      );
      return finishCapturedPreparation(preparation, signal, true);
    },
    retireCapturedComputation(capturedRun) {
      token(capturedRun);
      const original = capturedComputationPreparations.get(capturedRun);
      if (original === undefined) return;
      // The publication operation owns this alias through reconciliation.
      // Cancel releases managed facts, not physical children or an ACK.
      if (original.program !== undefined) moon.clientProgramCancelCapture(original.program);
      else moon.strategyCapturedRunCancel(original);
      capturedComputationPreparations.delete(capturedRun);
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
    projectEffectComputationReview(preview, policy, limits) {
      issuanceLimits(limits, 'Effect review projection');
      const original = computationPreviewTokens.get(preview);
      const wire = computationPreviewWires.get(preview);
      if (original === undefined || wire === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return inspectEvidence(checked(moon.clientProgramProjectEffectReview(
        original, wire, policy.authorityScopeCid, policy.approvalClaims,
        policy.redactionPolicyCid, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth)));
    },
    // Private original Client/Checkpoint binding. These operations accept the
    // Common-issued opaque view, never a wire/CID reconstructed substitute.
    requestedEffectStopLifetime(original) {
      const lifetime = checked(moon.clientProgramRequestedEffectStopLifetime(original));
      return Object.freeze({createdAt: runtimeField(lifetime, 0),
        validUntil: runtimeField(lifetime, 1)});
    },
    requestedEffectStopIntentCid(original) {
      return moon.clientProgramRequestedEffectStopIntentCid(original);
    },
    restoreRequestedEffectStop(original, identity, materials, invocation, preview, limits) {
      const admitted = computationPreviewTokens.get(preview);
      if (admitted === undefined) throw new TypeError('Foreign Effect computation Preview');
      return runtimeUnboxedReferenceOption(checked(moon.clientProgramRestoreRequestedEffectStop(
        original.intent, original.referenceWire, identity, materials,
        token(invocation), admitted, limits)));
    },
    sealRequestedEffectStop(original, bodyWire, continuationWire, limits) {
      issuanceLimits(limits, 'Requested Effect stop');
      return checked(moon.clientProgramRequestedEffectStopCheckpoint(original,
        bodyWire, continuationWire, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
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
    capturedEffectSourceInventoryFromCaptureValid(preview, sources,
      invocation, capturedRun, storeAuthorityCid, limits) {
      issuanceLimits(limits, 'recovered Effect source inventory');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources) ||
          sources.some(value => !Number.isSafeInteger(value?.memberIndex)) ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid recovered Effect source inventory');
      }
      return moon.strategyCapturedEffectSourceInventoryFromCaptureValid(
        ownedPreview, sources.map(value => value.memberIndex),
        sources.map(value => token(value.artifact)), token(invocation),
        token(capturedRun), storeAuthorityCid, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth);
    },
    capturedEffectSourceInventoryFromResultsValid(preview, sources, limits) {
      issuanceLimits(limits, 'captured Table source inventory');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources)) {
        throw new TypeError('Invalid captured Table source inventory');
      }
      const results = sources.map(value => {
        const owned = localEffectArtifactTokens.get(value.result);
        if (owned === undefined || !Number.isSafeInteger(value.memberIndex)) {
          throw new TypeError('Foreign captured Table source Result');
        }
        return checked(moon.strategyPublicationAdmit('result_artifact',
          moon.clientProgramLocalEffectResultArtifactJson(owned),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      });
      return moon.strategyCapturedEffectSourceInventoryFromResultsValid(ownedPreview,
        sources.map(value => value.memberIndex),
        sources.map(value => token(value.artifact)), results);
    },
    capturedEffectSourceInventoryFromArtifactsValid(preview, sources, limits) {
      issuanceLimits(limits, 'captured Relation source inventory');
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined || !Array.isArray(sources)) {
        throw new TypeError('Invalid captured Relation source inventory');
      }
      const relations = sources.map(value => {
        const owned = localEffectArtifactTokens.get(value.result);
        if (owned === undefined || !Number.isSafeInteger(value.memberIndex)) {
          throw new TypeError('Foreign captured Relation source Artifact');
        }
        return checked(moon.strategyPublicationAdmit('result_artifact',
          moon.clientProgramLocalEffectResultArtifactJson(owned),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      });
      return moon.strategyCapturedEffectSourceInventoryFromArtifactsValid(ownedPreview,
        sources.map(value => value.memberIndex),
        sources.map(value => token(value.artifact)), relations);
    },
    localEffectResultPayloadBinding(artifact, runDefinition) {
      const owned = localEffectArtifactTokens.get(artifact);
      if (owned === undefined) {
        throw new TypeError('Foreign local Effect Result artifact');
      }
      const binding = checked(moon.clientProgramLocalEffectResultPayloadBinding(
        owned, token(runDefinition)));
      return Object.freeze({artifactCid: artifact.identity,
        physicalCid: runtimeField(binding, 0), byteCount: runtimeField(binding, 1)});
    },
    // Schema material from the authenticated capture, not current configuration.
    capturedEffectDependencySchemas(capturedRun) {
      const captured = inspect(token(capturedRun));
      const inventory = JSON.parse(captured.wire).effect_context?.effect_dependency_inventory;
      if (captured.name !== 'captured_run' || !Array.isArray(inventory) || inventory.length > 4096) {
        throw new TypeError('InvalidEffectDependencySchemas');
      }
      // Original canonical bodies admitted by the CapturedRun/dependency Owner,
      // never reconstructed from current Catalogs or observed row values.
      return Object.freeze(inventory.filter(entry => entry.kind === 'relation_schema').map(entry => {
        if (typeof entry.cid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(entry.cid) ||
            entry.body === null || typeof entry.body !== 'object' || Array.isArray(entry.body)) {
          throw new TypeError('InvalidEffectDependencySchemas');
        }
        return Object.freeze({cid: entry.cid, wire: JSON.stringify(entry.body)});
      }));
    },
    // Physical custody metadata is not semantic identity or permission.
    // Callers first validate the Captured Run chain; issuance binds receipts.
    capturedEffectDependencyPayloadBindings(capturedRun, bindings) {
      const captured = inspect(token(capturedRun));
      const inventory = JSON.parse(captured.wire).effect_context
        ?.effect_dependency_inventory;
      if (captured.name !== 'captured_run' || !Array.isArray(inventory) ||
          !Array.isArray(bindings) || bindings.length > 4096) {
        throw new TypeError('InvalidEffectDependencyPayloadBindings');
      }
      const required = new Set(inventory.filter(entry =>
        entry.kind === 'result_artifact' || entry.kind === 'table_input_artifact')
        .map(entry => entry.cid));
      const seen = new Set();
      const owned = bindings.map(binding => {
        if (binding === null || typeof binding !== 'object' ||
            Object.keys(binding).sort().join(',') !==
              'artifact_cid,byte_count,physical_cid' ||
            !required.has(binding.artifact_cid) ||
            seen.has(binding.artifact_cid) ||
            typeof binding.physical_cid !== 'string' ||
            !/^sha256:[0-9a-f]{64}$/u.test(binding.physical_cid) ||
            !Number.isSafeInteger(binding.byte_count) || binding.byte_count < 0) {
          throw new TypeError('InvalidEffectDependencyPayloadBindings');
        }
        seen.add(binding.artifact_cid);
        return Object.freeze({...binding});
      });
      if (seen.size !== required.size) {
        throw new TypeError('IncompleteEffectDependencyPayloadBindings');
      }
      return Object.freeze(owned);
    },
    async issueEffectfulCapturedRun(chain, evidence, preview, plans, limits, signal) {
      limits = captureContractLimits(limits, 'Effectful Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.effectSources) ||
          !Array.isArray(evidence.localEffectSources) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence) ||
          (evidence.dependencyInventoryWire !== undefined &&
            typeof evidence.dependencyInventoryWire !== 'string') ||
          !Array.isArray(plans) ||
          plans.some(value => !value || typeof value.name !== 'string' ||
            typeof value.wire !== 'string')) {
        throw new TypeError('Invalid Effectful Captured Run request');
      }
      const ownedPreview = computationPreviewTokens.get(preview);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      signal?.throwIfAborted();
      const preparation = checked(moon.strategyBeginEffectfulCapturedRun(
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
        evidence.dependencyInventoryWire,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
        contentCaptures(evidence.contentGenerations),
      ));
      return finishCapturedPreparation(preparation, signal);
    },
    prepareLocalEffectDependencyInventory(artifacts, bodies, limits) {
      issuanceLimits(limits, 'Effect dependency inventory');
      if (!Array.isArray(artifacts) || artifacts.length > 4096 ||
          !Array.isArray(bodies) || bodies.length > 4096) {
        throw new TypeError('Invalid Effect dependency inventory');
      }
      const roots = new Map();
      for (const artifact of artifacts) {
        const owned = localEffectArtifactTokens.get(artifact);
        if (owned === undefined) {
          throw new TypeError('Foreign Effect dependency root');
        }
        roots.set(artifact.identity, owned);
      }
      let remaining = Math.min(limits.maxWireBytes, 16 * 1024 * 1024);
      const entries = new Map();
      const encoder = new TextEncoder();
      for (const body of bodies) {
        const {kind, wire, cid} = body ?? {};
        if (typeof kind !== 'string' || typeof wire !== 'string' ||
            (cid !== undefined && typeof cid !== 'string')) {
          throw new TypeError('Invalid Effect dependency body');
        }
        // Check the aggregate input before parsing or retaining another
        // admitted body. Encoding/envelope limits are checked again by MoonBit.
        if (wire.length > remaining) {
          throw new RangeError('EffectDependencyBodyByteLimit');
        }
        const bytes = encoder.encode(wire).byteLength;
        if (bytes > remaining) {
          throw new RangeError('EffectDependencyBodyByteLimit');
        }
        remaining -= bytes;
        const admitted = checked(moon.clientProgramAdmitEffectDependencyBody(
          kind, cid, wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        const identity = moon.clientProgramEffectDependencyBodyCid(admitted);
        const key = `${kind}\0${identity}`;
        const previous = entries.get(key);
        if (previous !== undefined && previous.wire !== wire) {
          throw new TypeError('Conflicting Effect dependency body');
        }
        if (previous === undefined) entries.set(key, {wire, admitted});
      }
      return checked(moon.clientProgramIssueEffectDependencyInventory(
        [...entries.values()].map(value => value.admitted), [...roots.values()],
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    issueEffectfulFinalRunReceipt(chain, preview, receipts, limits) {
      limits = captureContractLimits(limits, 'final Effectful Run Receipt');
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
      )), limits);
    },
    issueEffectSetApplyReceiptFromMembers(preview, members, replayed, limits) {
      limits = captureContractLimits(limits, 'Effect Set Apply Receipt');
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
      ), limits);
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
      return publicationAction('attempt', moon.strategyPublicationAttemptAction(
        record === undefined ? undefined : token(record),
        activeChecked,
        indexIssued,
      ));
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
      return publicationAction('setup', moon.strategyPublicationSetupAction(
        existingChecked,
        existingFound,
        existingEvidenceValidated,
        existingFinalized,
        initialActiveChecked,
        contractsPersisted,
        attemptCreated,
      ));
    },
    publicationCancellationAction(record) {
      return publicationAction('cancellation',
        moon.strategyPublicationCancellationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    committedPublicationFinalizationAction(record) {
      return publicationAction('finalization',
        moon.strategyCommittedPublicationFinalizationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    supersededPublicationFinalizationAction(record) {
      return publicationAction('finalization',
        moon.strategySupersededPublicationFinalizationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    publicationCommitFailureAction(
      reconciliationAttempted,
      reconciliationFailed,
      committedFound,
      unknownAppendAttempted,
    ) {
      return publicationAction('commitFailure',
        moon.strategyPublicationCommitFailureAction(
          reconciliationAttempted,
          reconciliationFailed,
          committedFound,
          unknownAppendAttempted,
        ));
    },
    publicationUnknownRetryAction(
      reconciliationResolved,
      upstreamPending,
      upstreamRetryAvailable,
      upstreamRetryAttempted,
    ) {
      return publicationAction('unknownRetry',
        moon.strategyPublicationUnknownRetryAction(
          reconciliationResolved,
          upstreamPending,
          upstreamRetryAvailable,
          upstreamRetryAttempted,
        ));
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
      return publicationAction('preparedRelease',
        moon.strategyPublicationPreparedReleaseAction(
          currentIndex,
          ownerCount,
          statusChecked,
          pending,
          releaseAttempted,
        ));
    },
    publicationCleanupOwnerAction(
      currentIndex,
      ownerCount,
      statusChecked,
      pending,
      retryAvailable,
      retryAttempted,
    ) {
      return publicationAction('cleanupOwner',
        moon.strategyPublicationCleanupOwnerAction(
          currentIndex,
          ownerCount,
          statusChecked,
          pending,
          retryAvailable,
          retryAttempted,
        ));
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
      limits = captureContractLimits(limits, 'Result Manifest');
      return inspect(checked(moon.strategyIssueResultManifest(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issueDurableResultBinding(chain, physical, limits) {
      limits = captureContractLimits(limits, 'durable Result binding');
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
      )), limits);
    },
    resultPublicationContractByteBounds(inputRelationCids, maxSchemaBytes, limits) {
      limits = captureContractLimits(limits, 'Result publication capacity');
      if (!Array.isArray(inputRelationCids) ||
          !inputRelationCids.every(value => typeof value === 'string' &&
            /^sha256:[0-9a-f]{64}$/u.test(value)) ||
          !Number.isSafeInteger(maxSchemaBytes) || maxSchemaBytes < 0) {
        throw new TypeError('Invalid Result publication capacity');
      }
      const values = moon.strategyResultPublicationContractByteBounds(
        inputRelationCids, maxSchemaBytes, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      );
      if (!Array.isArray(values) || values.length !== 4 ||
          !values.every(value => Number.isSafeInteger(value) && value >= 0 &&
            value <= limits.maxWireBytes)) {
        throw new TypeError('Invalid Result publication capacity projection');
      }
      return Object.freeze([...values]);
    },
    ordinaryPublicationReceiptByteBound(plan, request, limits) {
      limits = captureContractLimits(limits, 'Publication receipt capacity');
      const provenance = plan.receiptEvidence;
      const value = moon.strategyOrdinaryPublicationReceiptByteBound(
        admissionToken(plan.admission), token(request), token(plan.invocation),
        evidenceToken(plan.observation), evidenceToken(plan.normalizationJournal),
        provenance.bindings.map(binding => binding.name),
        provenance.bindings.map(binding => binding.sha256),
        provenance.sourceEvidence.map(evidenceToken),
        provenance.modelEvidence.map(evidenceToken), provenance.barrierAttemptReceiptCids,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      );
      if (!Number.isSafeInteger(value) || value < 0 || value > limits.maxWireBytes) {
        throw new TypeError('Invalid publication receipt capacity projection');
      }
      return value;
    },
    ordinaryPublicationFrontierByteBounds(request, resultCount, limits) {
      limits = captureContractLimits(limits, 'Publication frontier capacity');
      if (!Number.isSafeInteger(resultCount) || resultCount < 0 || resultCount > 2147483647) {
        throw new TypeError('Invalid publication frontier inventory');
      }
      const values = moon.strategyOrdinaryPublicationFrontierByteBounds(
        token(request), resultCount, limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      );
      if (!Array.isArray(values) || values.length !== 6 ||
          !values.every(value => Number.isSafeInteger(value) && value >= 0 &&
            value <= limits.maxWireBytes)) {
        throw new TypeError('Invalid publication frontier capacity projection');
      }
      const manifest = moon.strategyOrdinaryPublicationManifestByteBound(
        token(request), limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      );
      if (!Number.isSafeInteger(manifest) || manifest < 0 || manifest > limits.maxWireBytes) {
        throw new TypeError('Invalid publication manifest capacity projection');
      }
      return Object.freeze({
        manifest,
        index: values[0],
        current: Object.freeze({preparing: values[1], committing: values[2],
          publicationUnknown: values[3], terminal: values[4]}),
        possibleForeignWinnerTerminal: values[5],
      });
    },
    issuePublicationRequest(runDefinition, definitions, intent, limits) {
      limits = captureContractLimits(limits, 'Publication Request');
      if (intent === null || typeof intent !== 'object') {
        throw new TypeError('Invalid Publication Request intent');
      }
      return inspect(checked(moon.strategyIssuePublicationRequest(
        token(runDefinition),
        definitions.map(token),
        intent.namespaceId,
        intent.authorityScopeCid,
        intent.publicationPolicyCid,
        intent.publicationTargetCid,
        intent.requestedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issuePublicationAttempt(request, runDefinition, attempt, limits) {
      limits = captureContractLimits(limits, 'Publication Attempt');
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
      )), limits);
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
      limits = captureContractLimits(limits, 'Public Index Entry');
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
      )), limits);
    },
    publicIndexSameCommittedContent(committed, candidate) {
      return moon.strategyPublicIndexSameCommittedContent(
        token(committed), token(candidate));
    },
    issuePublicationRecord(attempt, previous, update, limits) {
      limits = captureContractLimits(limits, 'Publication Record');
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
      )), limits);
    },
    async effectFreeChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, receipt, capturedRun, limits, signal) {
      issuanceLimits(limits, 'Effect-free chain validation');
      signal?.throwIfAborted();
      const original = capturedComputationPreparations.get(capturedRun);
      if (original?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareChainValidation(
          original.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), token(manifest),
          token(receipt), token(capturedRun),
        ));
        return finishProgramValidation(validation, signal);
      }
      if (original !== undefined) limits = capturedPreparationLimits(original);
      const args = [
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
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
      ];
      const preparation = original === undefined
        ? moon.strategyBeginEffectFreeChainCheck(...args)
        : moon.strategyBeginEffectFreeChainCheckRetained(original, ...args);
      return finishPublicationValidation(preparation,
        moon.strategyEffectFreeChainCheckAdvance,
        moon.strategyEffectFreeChainCheckFinish,
        moon.strategyEffectFreeChainCheckCancel, signal);
    },
    // The selected Store read owns this full-original validation operation.
    // No preparation owner is reconstructed after reopen and no metadata
    // ceiling is reused for a larger independently admitted contract.
    async effectFreeStoredCommitValid(runDefinition, invocation, definitions, artifacts,
      derivations, orderings, retentions, durableBindings, manifest, receipt,
      capturedRun, request, attempt, indexEntry, requireCurrent) {
      if (typeof requireCurrent !== 'function') {
        throw new TypeError('Store publication validation owner unavailable');
      }
      requireCurrent();
      const retained = capturedComputationPreparations.get(capturedRun);
      if (retained?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareCommitValidation(
          retained.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), derivations.map(token),
          orderings.map(token), retentions.map(token), durableBindings.map(token),
          token(manifest), token(receipt), token(capturedRun), token(request),
          token(attempt), token(indexEntry),
        ));
        return finishProgramValidation(validation, undefined, requireCurrent);
      }
      const validation = checked(moon.clientStoreBeginOriginalCommitValidation(
        token(runDefinition), token(invocation), definitions.map(token),
        artifacts.map(token), derivations.map(token), orderings.map(token),
        retentions.map(token), durableBindings.map(token), token(manifest),
        token(receipt), token(capturedRun), token(request), token(attempt),
        token(indexEntry),
      ));
      return finishStoreValidation(validation, requireCurrent);
    },
    async effectFreeCommitValid(runDefinition, invocation, definitions, artifacts,
      derivations, orderings, retentions, durableBindings, manifest, receipt,
      capturedRun, request, attempt, indexEntry, limits) {
      issuanceLimits(limits, 'Effect-free commit validation');
      const original = capturedComputationPreparations.get(capturedRun);
      if (original?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareCommitValidation(
          original.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), derivations.map(token),
          orderings.map(token), retentions.map(token), durableBindings.map(token),
          token(manifest), token(receipt), token(capturedRun), token(request),
          token(attempt), token(indexEntry),
        ));
        // Commit reconciliation remains authoritative after cancellation.
        return finishProgramValidation(validation);
      }
      if (original !== undefined) limits = capturedPreparationLimits(original);
      const args = [
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
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
      ];
      const preparation = original === undefined
        ? moon.strategyBeginEffectFreeCommitCheck(...args)
        : moon.strategyBeginEffectFreeCommitCheckRetained(original, ...args);
      // A committed outcome is authoritative even after request cancellation.
      return finishPublicationValidation(preparation,
        moon.strategyEffectFreeCommitCheckAdvance,
        moon.strategyEffectFreeCommitCheckFinish,
        moon.strategyEffectFreeCommitCheckCancel);
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
      limits = captureContractLimits(limits, 'Result Artifact');
      return inspect(checked(
        moon.strategyHostOutputExportIssueResultArtifact(
          exportHandle,
          token(invocation),
          token(retention),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ), limits);
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
    describeCommittedResult(index, manifest, resultName, bindings,
      definition, schemaWire, format, limits) {
      issuanceLimits(limits, 'Result description');
      return JSON.parse(checked(moon.strategyDescribeCommittedResult(
        token(index), token(manifest), resultName, bindings.map(token),
        token(definition), schemaWire, format, limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth)));
    },
    issueManifestReadGrant(index, manifest, grant, limits) {
      limits = captureContractLimits(limits, 'Manifest read grant');
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
      )), limits);
    },
    issueResultReadGrant(index, manifest, grant, limits) {
      limits = captureContractLimits(limits, 'Result read grant');
      const bounds = Object.freeze({maxWireBytes: limits.maxWireBytes,
        maxNodes: limits.maxNodes, maxDepth: limits.maxDepth});
      if (grant === null || typeof grant !== 'object' ||
          !Array.isArray(grant.resultNames) ||
          !Array.isArray(grant.formats)) {
        throw new TypeError('Invalid Result read grant');
      }
      const result = inspect(checked(moon.strategyIssueResultReadGrant(
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
        bounds.maxWireBytes,
        bounds.maxNodes,
        bounds.maxDepth,
      )), limits);
      issuedDeliveryGrants.set(result, bounds);
      return result;
    },
    issueDeliveryAttempt(index, manifest, grant, attempt, limits) {
      limits = captureContractLimits(limits, 'Delivery Attempt');
      const bounds = Object.freeze({maxWireBytes: limits.maxWireBytes,
        maxNodes: limits.maxNodes, maxDepth: limits.maxDepth});
      if (attempt === null || typeof attempt !== 'object') {
        throw new TypeError('Invalid Delivery Attempt');
      }
      const result = inspect(checked(moon.strategyIssueDeliveryAttempt(
        token(index),
        token(manifest),
        token(grant),
        attempt.resultName,
        attempt.format,
        attempt.attemptId,
        attempt.requestedAt,
        bounds.maxWireBytes,
        bounds.maxNodes,
        bounds.maxDepth,
      )), limits);
      const original = Object.freeze({kind: 'issued-delivery-attempt'});
      const facts = Object.freeze({index, manifest, grant, attempt: result,
        request: Object.freeze({resultName: attempt.resultName, format: attempt.format,
          attemptId: attempt.attemptId, requestedAt: attempt.requestedAt}),
        limits: bounds});
      issuedDeliveryAttempts.set(result, {original,
        index: token(index), manifest: token(manifest), grant: token(grant)});
      originalDeliveryAttempts.set(original, facts);
      return result;
    },
    captureIssuedDeliveryAttempt(attempt, index, manifest, grant, limits) {
      token(attempt);
      const actualIndex = token(index), actualManifest = token(manifest), actualGrant = token(grant);
      const issued = issuedDeliveryAttempts.get(attempt);
      if (issued === undefined) return undefined;
      if (issued.index !== actualIndex || issued.manifest !== actualManifest || issued.grant !== actualGrant) {
        throw new TypeError('PublicationDeliveryOriginalMismatch');
      }
      issuanceLimits(limits, 'Delivery Attempt');
      const grantLimits = issuedDeliveryGrants.get(grant);
      const facts = originalDeliveryAttempts.get(issued.original);
      if (grantLimits === undefined || ['maxWireBytes', 'maxNodes', 'maxDepth'].some(
        key => limits[key] !== grantLimits[key] || limits[key] !== facts.limits[key])) return undefined;
      return issued.original;
    },
    readIssuedDeliveryAttempt(original) {
      const facts = originalDeliveryAttempts.get(original);
      if (facts === undefined) throw new TypeError('ForeignPublicationDeliveryOriginal');
      return facts;
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
    runDefinitionLifetime(runDefinition, expectedCid) {
      const lifetime = checked(moon.clientLocalCheckpointRunLifetime(
        token(runDefinition), expectedCid));
      return Object.freeze({createdAt: runtimeField(lifetime, 0),
        validUntil: runtimeField(lifetime, 1)});
    },
    // The Common reader checks the exact canonical document and embedded
    // resource CID. This private handle carries data, never restored custody.
    encodeModelOriginalResourceDocument(originWire, stateWire, cutWire, phase, limits) {
      if (![originWire, stateWire, cutWire, phase].every(value => typeof value === 'string')) {
        throw new TypeError('Invalid original Model document inputs');
      }
      issuanceLimits(limits, 'Original Model document');
      const {maxWireBytes, maxNodes, maxDepth} = limits;
      return checked(moon.clientProgramEncodeModelOriginalResourceDocument(
        originWire, stateWire, cutWire, phase, maxWireBytes, maxNodes, maxDepth));
    },
    readModelOriginalResourceDocument(wire, limits) {
      if (typeof wire !== 'string') throw new TypeError('Invalid original Model document');
      issuanceLimits(limits, 'Original Model document');
      const {maxWireBytes, maxNodes, maxDepth} = limits;
      const document = checked(moon.clientProgramReadModelOriginalResourceDocument(
        wire, maxWireBytes, maxNodes, maxDepth));
      const view = Object.freeze({kind: 'model-original-resource-document', wire});
      modelOriginalDocumentTokens.set(view, document);
      return view;
    },
    modelOriginalResourceOriginField(document, field) {
      const original = modelOriginalDocumentTokens.get(document);
      if (original === undefined) throw new TypeError('Foreign original Model document');
      if (typeof field !== 'string') throw new TypeError('Invalid original Model origin field');
      return moon.clientProgramModelOriginalResourceOriginField(original, field);
    },
    runCancellationConfirmed(facts) {
      const names = ['cancellationRequested', 'modelFenceRequired', 'modelFenced',
        'unresolvedModelCalls', 'unresolvedEffects', 'reconciliationRequired',
        'publicationCommitted', 'physicalStopConfirmed', 'cleanupConfirmed',
        'revisionUnchanged'];
      if (names.some(name => typeof facts?.[name] !== 'boolean')) {
        throw new TypeError('Invalid Run cancellation observations');
      }
      return moon.clientRunCancellationConfirmed(...names.map(name => facts[name]));
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
      limits = captureContractLimits(limits, 'Result retention extension');
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
      )), limits);
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
      limits = captureContractLimits(limits, 'Result delivery receipt');
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
      )), limits);
    },
    issueDeliveryRecord(attempt, previous, update, limits) {
      limits = captureContractLimits(limits, 'Delivery Record');
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
      )), limits);
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
  async function finishTransformation(preparation, signal) {
    let finished = false;
    try {
      while (true) {
        signal?.throwIfAborted();
        if (checked(moon.strategyHostResultTransformationAdvance(
          preparation, 256))) break;
        await new Promise(resolve => setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const exported = checked(
        moon.strategyHostResultTransformationFinish(preparation));
      finished = true;
      return exported;
    } finally {
      if (!finished) moon.strategyHostResultTransformationCancel(preparation);
    }
  }
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
    beginResult(host, result, limits, convertedOutput, selection, signal) {
      if (!Number.isSafeInteger(result) || result < 0 ||
          !validResultOutputLimits(limits)) {
        throw new TypeError('Invalid Result output export request');
      }
      signal?.throwIfAborted();
      const value = checked(moon.strategyHostResultTransformationBegin(
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
        convertedOutput,
        selection,
      ));
      return finishTransformation(value, signal);
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
    finishManagedResultImport(value, signal) {
      signal?.throwIfAborted();
      const preparation = checked(
        moon.strategyHostManagedResultTransformationBegin(value, undefined));
      return finishTransformation(preparation, signal);
    },
    async transformManagedResultImport(value, selection, signal) {
      signal?.throwIfAborted();
      const preparation = checked(
        moon.strategyHostManagedResultTransformationBegin(value, selection));
      return finishTransformation(preparation, signal);
    },
    cancelManagedResultImport: moon.strategyHostManagedResultImportCancel,
    next: value => checked(moon.strategyHostOutputExportNext(value)),
    rowsComplete: value => checked(moon.strategyHostOutputExportRowsComplete(value)),
    advance(value, quantum) {
      if (!Number.isInteger(quantum) || quantum < 1 || quantum > 64) {
        throw new TypeError('Invalid output export quantum');
      }
      const progress = moon.strategyHostOutputExportAdvance(value, quantum);
      return Object.freeze({batch: runtimeField(progress, 0), complete: runtimeField(progress, 1),
        work: runtimeField(progress, 2), issue: runtimeField(progress, 3)});
    },
    finish: value => checked(moon.strategyHostOutputExportFinish(value)),
    measurement(value) {
      const measured = checked(moon.strategyHostOutputExportMeasurement(value));
      return Object.freeze({rowCount: measured.row_count,
        admissionNodes: measured.admission_nodes,
        admissionTextBytes: measured.admission_text_bytes,
        admissionWork: measured.admission_work,
        columnRows: Object.freeze([...measured.column_rows]),
        columnBytes: Object.freeze([...measured.column_bytes]),
        columnNodes: Object.freeze([...measured.column_nodes]),
        columnMaxValueBytes: Object.freeze([...measured.column_max_value_bytes]),
        columnNullRows: Object.freeze([...measured.column_null_rows]),
        columnAdmittedDepths: Object.freeze([...measured.column_admitted_depths])});
    },
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
      return publicationAction('durablePayloadFailure',
        moon.strategyDurablePayloadFailureAction(
          writerExists,
          writerSealed,
          writerCancelAttempted,
          preparedPending,
          preparedReleaseAttempted,
          exportExists,
          exportReleased,
          exportCancelAttempted,
        ));
    },
    cleanupOwnerAction:
      publications.publicationCleanupOwnerAction,
  });
}

// Trusted assembly only. Standard entries bind this to their generated runtime;
// execution requests cannot supply a verifier, SQL or replacement runtime.
export function contentGenerationControl(moon, publications) {
  const barriers = new WeakSet();
  const encoders = new WeakSet();
  const candidates = new WeakSet();
  const storedCandidates = new WeakSet();
  const issuers = new WeakSet();
  const inputs = new WeakMap();
  const prefixes = new WeakSet();
  const workspaces = new WeakMap();
  const issued = new WeakSet();
  const outputs = new WeakSet();
  const resultPreparations = new WeakSet();
  const identityScans = new WeakMap();
  const familySteps = new WeakSet();
  const quantity = (value, minimum = 0) =>
    Number.isInteger(value) && value >= minimum && value <= 2147483647;
  const owned = (set, value, name) => {
    if (value === null || typeof value !== 'object' || !set.has(value)) {
      throw new TypeError(`Foreign ${name}`);
    }
    return value;
  };
  const referenceLimits = limits => {
    if (limits === null || typeof limits !== 'object' ||
        !['maxBytes', 'maxNodes', 'maxDepth', 'maxTextUnits'].every(
          key => quantity(limits[key], 1))) {
      throw new TypeError('Invalid Content reference limits');
    }
    return [limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxTextUnits];
  };
  return Object.freeze({
    effectFamily(program, graph, bodies, {generation, reference, contract, output, identitySlots},
      physical, retain, recovery) {
      const fields = [generation?.maxBytes, generation?.maxValueNodes,
        generation?.maxValueDepth, generation?.maxFrames, identitySlots,
        reference?.maxBytes, reference?.maxNodes, reference?.maxDepth,
        contract?.maxWireBytes, contract?.maxNodes, contract?.maxDepth];
      if (!fields.every(value => quantity(value)) || !validResultOutputLimits(output) ||
          !resultOutputLimitFields.every(name => quantity(output[name])) ||
          !['cancel', 'stopped', 'cleanup'].every(name => typeof physical?.[name] === 'function') ||
          typeof retain !== 'function' || !quantity(graph?.task) || !quantity(graph?.step)) {
        throw new TypeError('Invalid installed Content family');
      }
      const exported = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => output[name]));
      const workspace = exported === undefined ? undefined
        : moon.clientProgramContentStepWorkspace(...fields, exported);
      const provider = workspace === undefined ? undefined
        : moon.clientProgramEffectContentLocalProvider(program, graph.task, graph.step,
          bodies.registry, bodies.values, bodies.fragment, bodies.ordered, workspace,
          physical.cancel, physical.stopped, physical.cleanup, active => {
            familySteps.add(active);
            return retain(active) === true;
          }, recovery);
      if (provider === undefined) throw new TypeError('Installed Content family unavailable');
      return provider;
    },
    familyPendingPiece(step) {
      const value = moon.clientProgramContentStepPendingPiece(owned(familySteps, step, 'Content step'));
      return value === undefined ? undefined : Object.freeze({revision: runtimeField(value, 0), piece: runtimeField(value, 1)});
    },
    familyAcknowledgePiece(step, revision) {
      if (!quantity(revision, 1)) throw new TypeError('Invalid Content piece revision');
      return moon.clientProgramContentStepAcknowledgePiece(
        owned(familySteps, step, 'Content step'), revision);
    },
    familyInput(step) {
      const value = moon.clientProgramContentStepGenerationInput(owned(familySteps, step, 'Content step'));
      if (value === undefined) throw new TypeError('Content step input unavailable');
      inputs.set(runtimeField(value, 0), runtimeField(value, 2));
      encoders.add(runtimeField(value, 2));
      return Object.freeze({input: runtimeField(value, 0), receipt: runtimeField(value, 1), encoder: runtimeField(value, 2)});
    },
    familyByteCompletion(step) {
      const value = moon.clientProgramContentStepByteCompletion(owned(familySteps, step, 'Content step'));
      if (value === undefined) throw new TypeError('Content step completion unavailable');
      return Object.freeze({name: value.name, mediaType: value.media_type,
        contentCid: value.content_cid, sizeBytes: value.size_bytes, rowCount: value.row_count});
    },
    familyComplete(compiled, definition, step, inputEvidence, candidate, content, available, limits) {
      owned(familySteps, step, 'Content step');
      if (typeof available !== 'function' || !quantity(limits?.maxNodes, 1) ||
          !quantity(limits?.maxTextBytes) || !quantity(limits?.maxDepth) ||
          !quantity(limits?.maxWork, 1) || !quantity(limits?.maxNameBytes)) {
        throw new TypeError('Invalid compiled Content step completion');
      }
      return publications.completeCheckedClientContentStep(compiled, definition, step,
        inputEvidence, owned(candidates, candidate, 'Content candidate'),
        owned(issued, content, 'issued Content'), available, limits);
    },
    workspaceCapacity({generation, reference, contract, output, identitySlots}) {
      const fields = [generation?.maxBytes, generation?.maxValueNodes,
        generation?.maxValueDepth, generation?.maxFrames, identitySlots,
        reference?.maxBytes, reference?.maxNodes, reference?.maxDepth,
        contract?.maxWireBytes, contract?.maxNodes, contract?.maxDepth];
      if (!fields.every(value => quantity(value)) || !validResultOutputLimits(output) ||
          !resultOutputLimitFields.every(name => quantity(output[name]))) {
        throw new TypeError('Invalid Content workspace limits');
      }
      const exported = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => output[name]));
      const token = exported === undefined ? undefined
        : moon.clientProgramSerializationWorkspaceCapacity(...fields, exported);
      if (token === undefined) throw new TypeError('Content workspace unavailable');
      const bytes = moon.clientProgramSerializationCapacityBytes(token);
      const workspace = Object.freeze({retainedBytes: runtimeField(bytes, 0), executionBytes: runtimeField(bytes, 1)});
      workspaces.set(workspace, token);
      return workspace;
    },
    prefixCapacity(program, task, step, bodies, limits, workspace, source) {
      if (!quantity(limits?.maxRows) || !quantity(limits?.maxWork, 1) ||
          !quantity(limits?.maxEntries, 1) || !quantity(limits?.maxValueBytes) ||
          !quantity(limits?.maxValueNodes, 1) || !quantity(limits?.maxValueDepth) ||
          !quantity(limits?.maxFrames, 1)) {
        throw new TypeError('Invalid Content prefix limits');
      }
      const capacity = moon.clientProgramSerializationPrefixCapacity(program, task,
        step, bodies.registry, bodies.values, bodies.fragment, bodies.ordered,
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames,
        source !== undefined);
      if (capacity === undefined) throw new TypeError('Content prefix unavailable');
      if (workspace !== undefined && !workspaces.has(workspace)) {
        throw new TypeError('Foreign Content workspace capacity');
      }
      const retainedBytes = runtimeField(capacity, 0) + (workspace?.retainedBytes ?? 0n);
      const executionBytes = runtimeField(capacity, 1) + (workspace?.executionBytes ?? 0n);
      if (retainedBytes > 9223372036854775807n || executionBytes > 9223372036854775807n) {
        throw new TypeError('Content capacity overflow');
      }
      return Object.freeze({retainedBytes, executionBytes});
    },
    prepareRequestPrefix(parent, input, request, compiled, definition, limits, workspace) {
      if (workspace !== undefined && !workspaces.has(workspace)) {
        throw new TypeError('Foreign Content workspace capacity');
      }
      return publications.prepareCheckedClientRequestSerializationPlan(parent, input, request, compiled,
        definition, limits, workspace === undefined ? undefined : workspaces.get(workspace));
    },
    prepareModelRequestPrefix(parent, input, request, compiled, definition, limits, workspace, queryTime) {
      if (workspace !== undefined && !workspaces.has(workspace)) {
        throw new TypeError('Foreign Content workspace capacity');
      }
      return publications.prepareCheckedClientRequestModelSerializationPlan(parent, input, request, compiled,
        definition, limits, workspace === undefined ? undefined : workspaces.get(workspace), queryTime);
    },
    prepareRequestKeyedPlan(parent, input, request, keyed, directDeclaration, contentDeclaration,
      maxBytes, maxWork, queryContract, evidenceContract, transfers, executions, contracts, task, step,
      limits, workspace) {
      const prepare = moon.clientProgramPrepareRequestKeyedContentPlan;
      if (typeof prepare !== 'function') throw new TypeError('Request keyed Content constructor unavailable');
      if (!quantity(maxBytes) || !quantity(maxWork, 1) ||
          !quantity(limits?.maxRows) || !quantity(limits?.maxWork, 1) ||
          !quantity(limits?.maxEntries, 1) || !quantity(limits?.maxValueBytes) ||
          !quantity(limits?.maxValueNodes, 1) || !quantity(limits?.maxValueDepth) ||
          !quantity(limits?.maxFrames, 1)) throw new TypeError('Invalid Content prefix limits');
      if (workspace !== undefined && !workspaces.has(workspace)) {
        throw new TypeError('Foreign Content workspace capacity');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, keyed,
        directDeclaration, contentDeclaration, maxBytes, maxBytes, maxWork,
        queryContract, evidenceContract, transfers, executions, maxBytes, maxWork,
        contracts, task, step, limits.maxRows, limits.maxWork, limits.maxEntries,
        limits.maxValueBytes, limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames,
        workspace === undefined ? undefined : workspaces.get(workspace)]));
    },
    requestPrefixCapacity(selected) {
      const value = moon.clientProgramPreparedInstalledSerializationPrefixRequirements(selected);
      if (!Array.isArray(value) || value.length !== 6 ||
          value.some(n => typeof n !== 'bigint' || n < 0n || n > 9223372036854775807n) ||
          value[0] !== 0n || value[1] !== 1n || value[2] !== 0n || value[3] !== 0n) {
        throw new TypeError('Invalid Content prefix requirements');
      }
      return Object.freeze({retainedBytes: value[4], executionBytes: value[5]});
    },
    startRequestPrefix(run, program, selected) {
      const prefix = checked(moon.clientProgramInstalledManagedSerializationPrefixStart(run, program, selected));
      prefixes.add(prefix); return prefix;
    },
    startRequestAcquiredPrefix(run, program, selected, capture) {
      const prefix = checked(moon.clientProgramInstalledManagedAcquiredSerializationPrefixStart(
        run, program, selected, capture));
      prefixes.add(prefix); return prefix;
    },
    cleanupRequestPrefix(run, selected) {
      return checked(moon.clientProgramInstalledManagedSerializationPrefixCleanup(run, selected));
    },
    requestKeyedPrefixCapacity(selected) {
      const value = checked(moon.clientProgramPreparedInstalledKeyedPrefixRequirements(selected));
      if (!Array.isArray(value) || value.length !== 6 ||
          value.some(n => typeof n !== 'bigint' || n < 0n || n > 9223372036854775807n) ||
          value[0] !== 0n || value[1] !== 1n || value[2] !== 0n || value[3] !== 0n) {
        throw new TypeError('Invalid keyed Content prefix requirements');
      }
      return Object.freeze({retainedBytes: value[4], executionBytes: value[5]});
    },
    startRequestKeyedPrefix(run, program, selected, source, lookup) {
      const prefix = checked(moon.clientProgramInstalledManagedKeyedSerializationPrefixStart(
        run, program, selected, source, lookup));
      prefixes.add(prefix); return prefix;
    },
    cleanupRequestKeyedPrefix(run, selected) {
      return checked(moon.clientProgramInstalledManagedKeyedSerializationPrefixCleanup(run, selected));
    },
    prefix(program, task, step, bodies, limits, ledger, workspace, source, keyed) {
      // Revalidate through the same provider before reserve/start. Capacity
      // inspection alone is neither a reservation nor permission to execute.
      this.prefixCapacity(program, task, step, bodies, limits, workspace, source);
      if (ledger === undefined) throw new TypeError('Content prefix requires the Run ledger');
      const prefix = checked(moon.clientProgramStartSerializationPrefix(program, task,
        step, bodies.registry, bodies.values, bodies.fragment, bodies.ordered,
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, ledger,
        workspace === undefined ? undefined : workspaces.get(workspace), source, keyed));
      prefixes.add(prefix);
      return prefix;
    },
    prefixAdvance(prefix, quantum) {
      const value = checked(moon.clientProgramSerializationPrefixAdvance(
        owned(prefixes, prefix, 'Content prefix'), quantum));
      return Object.freeze({output: runtimeField(value, 0), progress: runtimeField(value, 1), work: runtimeField(value, 2),
        stopped: runtimeField(value, 3), issue: runtimeField(value, 4)});
    },
    prefixWork(prefix) {
      return checked(moon.clientProgramSerializationPrefixWork(
        owned(prefixes, prefix, 'Content prefix')));
    },
    prefixCancel(prefix) {
      return moon.clientProgramSerializationPrefixCancel(
        owned(prefixes, prefix, 'Content prefix'));
    },
    prefixCleanup(prefix) {
      return checked(moon.clientProgramSerializationPrefixCleanup(
        owned(prefixes, prefix, 'Content prefix')));
    },
    prepare(program, task, step, maxWork) {
      const barrier = checked(moon.clientProgramPrepareSerialization(
        program, task, step, maxWork));
      barriers.add(barrier);
      return barrier;
    },
    encoder(barrier, limits) {
      owned(barriers, barrier, 'Content barrier');
      if (!quantity(limits?.maxRows) || !quantity(limits?.maxBytes) ||
          !quantity(limits?.maxValueNodes, 1) || !quantity(limits?.maxValueDepth) ||
          !quantity(limits?.maxFrames, 1)) {
        throw new TypeError('Invalid Content encoder limits');
      }
      const encoder = checked(moon.clientProgramSerializationEncoder(barrier,
        limits.maxRows, limits.maxBytes, limits.maxValueNodes,
        limits.maxValueDepth, limits.maxFrames));
      encoders.add(encoder);
      return encoder;
    },
    row(barrier, input, row, encoder) {
      return checked(moon.clientProgramSerializationRow(
        owned(barriers, barrier, 'Content barrier'), input, row,
        owned(encoders, encoder, 'Content encoder')));
    },
    bindInput(barrier, output, encoder) {
      const input = checked(moon.clientProgramSerializationBindInput(
        owned(barriers, barrier, 'Content barrier'), output,
        owned(encoders, encoder, 'Content encoder')));
      inputs.set(input, encoder);
      return input;
    },
    inputRows(input) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      return moon.clientProgramSerializationInputRows(input);
    },
    inputIdentityStart(input, limits, maxWork, maxWorkspaceSlots) {
      if (!inputs.has(input) || !validResultOutputLimits(limits) ||
          !quantity(maxWork) || !quantity(maxWorkspaceSlots) ||
          !resultOutputLimitFields.every(name => quantity(limits[name]))) {
        throw new TypeError('Invalid Content input identity limits');
      }
      const exportLimits = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => limits[name]));
      if (exportLimits === undefined) throw new TypeError('Invalid Content input identity limits');
      const scan = checked(moon.clientProgramSerializationInputIdentityStart(
        input, exportLimits, maxWork, maxWorkspaceSlots));
      identityScans.set(scan, input);
      return scan;
    },
    inputIdentityAdvance(scan, quantum) {
      if (!identityScans.has(scan) || !quantity(quantum, 1)) {
        throw new TypeError('Foreign or invalid Content input identity scan');
      }
      const next = moon.clientProgramSerializationInputIdentityAdvance(scan, quantum);
      return Object.freeze({ready: runtimeField(next, 0), work: runtimeField(next, 1), issue: runtimeField(next, 2)});
    },
    inputIdentityFinish(compiled, scan, limits, captured) {
      const input = identityScans.get(scan);
      if (input === undefined) throw new TypeError('Foreign Content input identity scan');
      const receipt = checked(moon.clientProgramSerializationInputIdentityFinish(scan));
      try {
        return publications.bindCheckedClientSerializationInputIdentity(compiled, input, receipt, limits, captured);
      } finally { moon.clientProgramSerializationInputIdentityReceiptCancel(receipt); }
    },
    inputIdentityCancel(scan) {
      if (!identityScans.has(scan)) throw new TypeError('Foreign Content input identity scan');
      return moon.clientProgramSerializationInputIdentityCancel(scan);
    },
    inputRow(input, row) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      return checked(moon.clientProgramSerializationInputRow(input, row));
    },
    inputAdvance(input, quantum) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      return this.advance(inputs.get(input), quantum);
    },
    inputFinish(input) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      return this.finish(inputs.get(input));
    },
    inputCancel(input) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      moon.clientProgramSerializationCancel(inputs.get(input));
    },
    output(input, candidate, content, available, limits) {
      if (!inputs.has(input) || typeof available !== 'function' ||
          !quantity(limits?.maxNodes, 1) || !quantity(limits?.maxTextBytes) ||
          !quantity(limits?.maxDepth) || !quantity(limits?.maxWork, 1) ||
          !quantity(limits?.maxNameBytes)) {
        throw new TypeError('Invalid Content output binding');
      }
      const result = moon.clientProgramSerializationOutput(input,
        owned(candidates, candidate, 'Content candidate'),
        owned(issued, content, 'issued Content'), available,
        limits.maxNodes, limits.maxTextBytes, limits.maxDepth,
        limits.maxWork, limits.maxNameBytes);
      if (runtimeIsError(result)) {
        const causeCode = moon.clientProgramSerializationOutputIssueCode(runtimeField(result, 0));
        throw Object.assign(new Error(`Content output rejected: ${causeCode}`,
          {cause: runtimeField(result, 0)}), {code: 'MoonBitHostFailure', causeCode});
      }
      const output = checked(result);
      outputs.add(output);
      return output;
    },
    outputRowWire(output, limits) {
      return checked(moon.clientProgramSerializationOutputRowWire(
        owned(outputs, output, 'Content output'), ...referenceLimits(limits).slice(0, 3)));
    },
    outputAvailable(output) {
      return moon.clientProgramSerializationOutputAvailable(
        owned(outputs, output, 'Content output'));
    },
    complete(compiled, definition, input, inputEvidence, candidate, content, available, limits) {
      if (!inputs.has(input) || typeof available !== 'function' ||
          !quantity(limits?.maxNodes, 1) || !quantity(limits?.maxTextBytes) ||
          !quantity(limits?.maxDepth) || !quantity(limits?.maxWork, 1) ||
          !quantity(limits?.maxNameBytes)) {
        throw new TypeError('Invalid compiled Content completion');
      }
      return publications.completeCheckedClientSerializationGeneration(compiled,
        definition, input, inputEvidence, owned(candidates, candidate, 'Content candidate'),
        owned(issued, content, 'issued Content'), available, limits);
    },
    recover(compiled, definition, graph, scope, expectedGenerationCid, evidence, candidate, content) {
      return publications.readmitCheckedClientSerializationGeneration(compiled, definition,
        graph, scope, expectedGenerationCid, evidence,
        owned(storedCandidates, candidate, 'stored Content candidate'),
        owned(issued, content, 'issued Content'));
    },
    completedOutput(compiled, generation) {
      const output = publications.checkedClientSerializationGenerationOutput(compiled, generation);
      outputs.add(output);
      return output;
    },
    resultOccurrence(compiled, program, result, limits) {
      publications.checkClientCompiledRunOwner(compiled, program);
      if (compiled.kind !== 'serialization' || !quantity(result) ||
          !quantity(limits?.maxWireBytes, 1) || !quantity(limits?.maxNodes, 1) ||
          !quantity(limits?.maxDepth)) {
        throw new TypeError('Invalid Content Result occurrence');
      }
      const occurrence = checked(moon.clientProgramSerializationResultOccurrence(
        program, result, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const definitionContract = publications.admit('result_definition',
        moon.strategyPublicationContractJson(runtimeField(occurrence, 2)), limits);
      return Object.freeze({name: runtimeField(occurrence, 0), task: runtimeField(occurrence, 1), definitionContract});
    },
    resultStart(program, result, output, limits) {
      if (!quantity(result) || !validResultOutputLimits(limits) ||
          !resultOutputLimitFields.every(name => quantity(limits[name]))) {
        throw new TypeError('Invalid Content Result export limits');
      }
      // This existing builder creates only shared finite export limits; it
      // supplies no Effect or publication authority.
      const exportLimits = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => limits[name]));
      if (exportLimits === undefined) throw new TypeError('Invalid Content Result export limits');
      const preparation = checked(moon.clientProgramSerializationResultStart(
        program, result, owned(outputs, output, 'Content output'), exportLimits));
      resultPreparations.add(preparation);
      return preparation;
    },
    resultAdvance(preparation, quantum) {
      if (!quantity(quantum, 1)) throw new TypeError('Invalid Content Result quantum');
      const result = moon.clientProgramSerializationResultProgress(
        owned(resultPreparations, preparation, 'Content Result preparation'), quantum);
      return Object.freeze({ready: runtimeField(result, 0), work: runtimeField(result, 1), issue: runtimeField(result, 2)});
    },
    resultFinish(preparation) {
      return checked(moon.clientProgramSerializationResultFinish(
        owned(resultPreparations, preparation, 'Content Result preparation')));
    },
    resultCancel(preparation) {
      return moon.clientProgramSerializationResultCancel(
        owned(resultPreparations, preparation, 'Content Result preparation'));
    },
    advance(encoder, quantum) {
      const value = moon.clientProgramSerializationAdvance(
        owned(encoders, encoder, 'Content encoder'), quantum);
      // Charge the reported delta before handling failure. Converting a failed
      // poll directly to an exception would discard its already consumed work.
      return Object.freeze({ready: runtimeField(value, 0), piece: runtimeField(value, 1), work: runtimeField(value, 2),
        issue: runtimeField(value, 3)});
    },
    finish(encoder) {
      const value = checked(moon.clientProgramSerializationFinish(
        owned(encoders, encoder, 'Content encoder')));
      return Object.freeze({name: runtimeField(value, 0), mediaType: runtimeField(value, 1),
        contentCid: runtimeField(value, 2), sizeBytes: runtimeField(value, 3), rowCount: runtimeField(value, 4)});
    },
    candidate(encoder, binding, limits) {
      const value = checked(moon.clientProgramGeneratedContentCandidate(
        owned(encoders, encoder, 'Content encoder'), JSON.stringify(binding),
        ...referenceLimits(limits)));
      candidates.add(value);
      return value;
    },
    recoveryCandidate(originalWire, binding, limits) {
      const value = checked(moon.clientProgramStoredGeneratedContentCandidate(
        originalWire, JSON.stringify(binding), ...referenceLimits(limits)));
      storedCandidates.add(value);
      return value;
    },
    inspect(candidate) {
      if (storedCandidates.has(candidate)) {
        const value = moon.clientProgramStoredGeneratedContentStorage(candidate);
        const wire = moon.clientProgramStoredGeneratedContentCandidateWire(candidate);
        const body = JSON.parse(wire);
        return Object.freeze({wire, identity: runtimeField(value, 0),
          storeCid: runtimeField(value, 1), workspaceScopeCid: runtimeField(value, 2),
          contentCid: runtimeField(value, 3), sizeBytes: runtimeField(value, 4), mediaType: body.media_type,
          effectiveDataPolicyCid: body.metadata.effective_data_policy_cid});
      }
      owned(candidates, candidate, 'Content candidate');
      const value = moon.clientProgramGeneratedContentStorage(candidate);
      const wire = moon.clientProgramGeneratedContentCandidateWire(candidate);
      // This body was constructed by the common owner, not admitted from
      // provider/author JSON. No identity is computed or normalized here.
      const body = JSON.parse(wire);
      return Object.freeze({wire,
        identity: moon.clientProgramGeneratedContentCandidateCid(candidate),
        storeCid: runtimeField(value, 0), workspaceScopeCid: runtimeField(value, 1),
        contentCid: runtimeField(value, 2), sizeBytes: runtimeField(value, 3),
        mediaType: body.media_type,
        effectiveDataPolicyCid: body.metadata.effective_data_policy_cid});
    },
    issuer(validate, authorize) {
      if (typeof validate !== 'function' || typeof authorize !== 'function') {
        throw new TypeError('Invalid Content issuer callbacks');
      }
      const issuer = moon.clientProgramRowReferenceIssuer(() => false,
        validate, authorize);
      issuers.add(issuer);
      return issuer;
    },
    issue(candidate, issuer, limits) {
      const restored = storedCandidates.has(candidate);
      const content = checked((restored ? moon.clientProgramIssueStoredGeneratedContent
        : moon.clientProgramIssueGeneratedContent)(
        owned(restored ? storedCandidates : candidates, candidate, 'Content candidate'),
        owned(issuers, issuer, 'Content issuer'), ...referenceLimits(limits)));
      issued.add(content);
      return content;
    },
  });
}

// Captured candidates are sealed by the checked keyed Source owner. This
// transport facade holds no acquisition, byte or cleanup state machine.
export function contentCaptureControl(moon, publications) {
  const candidates = new WeakSet();
  const issuers = new WeakSet();
  const args = limits => {
    const fields = ['maxBytes', 'maxNodes', 'maxDepth', 'maxTextUnits'];
    if (!fields.every(key => Number.isInteger(limits?.[key]) &&
        limits[key] > 0 && limits[key] <= 2147483647)) {
      throw new TypeError('Invalid captured Content reference limits');
    }
    return fields.map(key => limits[key]);
  };
  const own = (set, value) => {
    if (!set.has(value)) throw new TypeError('Foreign captured Content candidate');
    return value;
  };
  return Object.freeze({
    candidate(acquisition, request, binding, bytes, limits) {
      if (!Number.isInteger(bytes?.sizeBytes) || bytes.sizeBytes < 0 ||
          bytes.sizeBytes > 2147483647) {
        throw new TypeError('Invalid captured Content byte facts');
      }
      const value = checked(moon.clientProgramCapturedContentCandidate(
        acquisition, request, JSON.stringify(binding), bytes.mediaType,
        bytes.contentCid, bytes.sizeBytes, ...args(limits)));
      candidates.add(value);
      return value;
    },
    candidateForRun(compiled, definition, acquisition, request, binding, bytes, limits) {
      if (!Number.isInteger(bytes?.sizeBytes) || bytes.sizeBytes < 0 ||
          bytes.sizeBytes > 2147483647) throw new TypeError('Invalid captured Content byte facts');
      const value = publications.checkedClientRunCapturedContentCandidate(compiled,
        definition, acquisition, request, JSON.stringify(binding), bytes.mediaType,
        bytes.contentCid, bytes.sizeBytes, args(limits));
      candidates.add(value);
      return value;
    },
    recoveryCandidateForRun(compiled, definition, acquisition, originalWire, binding, limits) {
      const value = publications.checkedClientStoredRunCapturedContentCandidate(
        compiled, definition, acquisition, originalWire, JSON.stringify(binding), args(limits));
      candidates.add(value);
      return value;
    },
    holdingCid(candidate) {
      const value = moon.clientProgramCapturedContentHoldingCid(own(candidates, candidate));
      if (value === undefined) throw new TypeError('Captured Content requires original Run custody');
      return value;
    },
    reserveWorkspace(ledger, maxBytes, inventoryCount = 0) {
      return checked(moon.clientProgramReserveCapturedContentWorkspace(ledger, maxBytes, inventoryCount));
    },
    releaseWorkspace(ledger, reservation) {
      return checked(moon.clientProgramReleaseCapturedContentWorkspace(ledger, reservation));
    },
    reissuer(resolve) {
      if (typeof resolve !== 'function') throw new TypeError('Invalid captured Content resolver');
      return moon.clientProgramCapturedContentReissuer(resolve);
    },
    inspect(candidate) {
      own(candidates, candidate);
      const storage = moon.clientProgramCapturedContentStorage(candidate);
      const wire = moon.clientProgramCapturedContentWire(candidate);
      const body = JSON.parse(wire);
      return Object.freeze({wire,
        identity: moon.clientProgramCapturedContentCid(candidate),
        storeCid: runtimeField(storage, 0), workspaceScopeCid: runtimeField(storage, 1),
        contentCid: runtimeField(storage, 2), sizeBytes: runtimeField(storage, 3),
        mediaType: body.media_type,
        effectiveDataPolicyCid: body.metadata.effective_data_policy_cid});
    },
    issuer(validate, authorize) {
      if (typeof validate !== 'function' || typeof authorize !== 'function') {
        throw new TypeError('Invalid captured Content issuer callbacks');
      }
      const issuer = moon.clientProgramRowReferenceIssuer(() => false, validate, authorize);
      issuers.add(issuer);
      return issuer;
    },
    issue(candidate, issuer, limits) {
      return checked(moon.clientProgramIssueCapturedContent(
        own(candidates, candidate), own(issuers, issuer), ...args(limits)));
    },
  });
}

export function runtimeCore(moon) {
  const publications = publicationControl(moon);
  return Object.freeze({
    siteControl: siteControl(moon),
    managedExecutionProfileCid: moon.strategyHostManagedExecutionProfileCid,
    remoteSiteControl: remoteSiteControl(moon),
    remoteTransferControl: remoteTransferControl(moon),
    remoteStandardSourceControl: remoteStandardSourceControl(moon),
    remoteCredentialControl: remoteCredentialControl(moon),
    // Explicit private DATA view, not an installed issuer or signing permit.
    // Keep older unused runtime routes lazy; actual callers require this ABI.
    localSigningMetadata: () => createLocalSigningMetadata(moon),
    installationPreparationMetadata: () => createInstallationPreparationMetadata(moon),
    effectApplicationControl: effectApplicationControl(moon),
    remoteBundleControl: remoteBundleControl(moon),
    publicationControl: publications,
    outputExportControl: outputExportControl(moon, publications),
    contentGenerationControl: contentGenerationControl(moon, publications),
    contentCaptureControl: contentCaptureControl(moon, publications),
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
    preparationUsageIsolated: (value, holder) =>
      typeof moon.clientProgramPreparationBorrowUsageIsolated === 'function' &&
      moon.clientProgramPreparationBorrowUsageIsolated(holder, moon.strategyHostRun(value)) === true,
    usage: value => ledgerUsageSnapshot(moon.strategyHostUsage(value)),
  });
}
