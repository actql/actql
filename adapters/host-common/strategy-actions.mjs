// Names for decisions already made by the installed MoonBit authority. This
// boundary only decodes its closed numeric ABI: it stores no lifecycle state,
// selects no transition, and grants no permission or physical release.
function actionNames(names, errorCode) {
  return code => {
    if (!Number.isSafeInteger(code) || code < 0 || code >= names.length) {
      throw Object.assign(new Error(errorCode), {code: errorCode});
    }
    return names[code];
  };
}

// The ordering is the existing *_action_code / *_outcome_code ABI in
// execution_site/operation_failure.mbt and physical_strategy/host_*.mbt.
export const strategyAction = Object.freeze({
  holding: actionNames([
    'RetainedSiteStartClose', 'RetainedSiteAwaitClose',
    'RetainedSiteAwaitCleanup', 'RetainedSiteReleaseHolding',
    'RetainedSiteHoldingFinished', 'RetainedSiteHoldingInvalid',
  ], 'InvalidExecutionSiteHoldingAction'),
  close: actionNames([
    'RetainedSiteCloseStart', 'RetainedSiteCloseAwaitPhysical',
    'RetainedSiteCloseAwaitCleanup', 'RetainedSiteCloseFinished',
    'RetainedSiteCloseInvalid',
  ], 'InvalidExecutionSiteCloseAction'),
  failure: actionNames([
    'FailedSiteAwaitStop', 'FailedSiteSettle', 'FailedSiteFinished',
  ], 'InvalidExecutionSiteFailureAction'),
  taskSuccess: actionNames([
    'HostTaskCheckSiteCompletion', 'HostTaskRejectSiteCompletion',
    'HostTaskCheckCommonCompletion', 'HostTaskRejectCommonCompletion',
    'HostTaskRetainConnectorOutput', 'HostTaskRetainCoreOutput',
    'HostTaskSettleSiteOperation', 'HostTaskValidateManagedBinding',
    'HostTaskRejectManagedBinding', 'HostTaskSuccessFinished',
    'HostTaskSuccessInvalid',
  ], 'InvalidExecutionSiteHostTaskSuccessAction'),
  cleanup: actionNames([
    'HostCleanupRetryKnown', 'HostCleanupAwaitCloses', 'HostCleanupPending',
    'HostCleanupFailed', 'HostCleanupFinished',
  ], 'InvalidExecutionSiteHostCleanupAction'),
  outcome: actionNames([
    'HostTasksCompleted', 'HostTasksFailed', 'HostTaskRunInvalid',
  ], 'InvalidExecutionSiteHostTaskRunOutcome'),
  managedFallback: actionNames([
    'ManagedCandidateLegacyAllowed', 'ManagedCandidateEstimateUnavailable',
    'ManagedCandidateTransferUnavailable', 'ManagedCandidateNoCompatibleStrategy',
  ], 'InvalidManagedCandidateFallback'),
});
