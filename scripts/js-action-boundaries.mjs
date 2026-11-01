// Existing Owner decisions -> existing JS facade names. There are deliberately
// no action numbers here. Code assignments come only from the named Owner fn.
const publication = (kind, source, enumeration, projection, names) =>
  Object.freeze({family:'publication',kind,source,enumeration,projection,names});
const strategy = (kind, source, enumeration, projection, error, excluded = []) =>
  Object.freeze({family:'strategy',kind,source,enumeration,projection,error,excluded});
const runtime = 'src/run_publication/runtime_progress.mbt';
const delivery = 'src/run_publication/delivery_runtime_progress.mbt';
const cleanup = 'src/run_publication/cleanup_progress.mbt';
const site = 'src/execution_site/operation_failure.mbt';

export const actionBoundaries = Object.freeze([
  publication('resultAccess','src/run_publication/result_access_progress.mbt',
    'ResultAccessProgressAction','result_access_progress_action_code', {
      ResultAccessAuthorizeRequest:'authorize_request',
      ResultAccessResolveCommittedResult:'resolve_committed_result',
      ResultAccessCheckInitialAvailability:'check_initial_availability',
      ResultAccessAdmitRead:'admit_read',ResultAccessIssueGrant:'issue_grant',
      ResultAccessStartDelivery:'start_delivery',ResultAccessReject:'reject',
    }),
  publication('existingDelivery',delivery,'ExistingDeliveryAttemptAction',
    'existing_delivery_attempt_action_code', {
      DeliveryConfirmSucceededRecord:'confirm_succeeded_record',
      DeliveryRejectUnresolvedAttempt:'reject_unresolved_attempt',
      DeliveryRejectTerminalAttempt:'reject_terminal_attempt',
      ExistingDeliveryAttemptInvalid:'invalid',
    }),
  publication('failureTerminal',delivery,'DeliveryFailureTerminalAction',
    'delivery_failure_terminal_action_code', {
      DeliveryAppendFailed:'failed',DeliveryAppendCancelled:'cancelled',
    }),
  publication('recordRetry',delivery,'DeliveryRecordRetryAction',
    'delivery_record_retry_action_code', {
      DeliveryAppendNextRecord:'append_next_record',DeliveryRecordRetryFinished:'finished',
      DeliveryRecordRetryInvalid:'invalid',
    }),
  publication('setup',runtime,'PublicationSetupAction','publication_setup_action_code', {
    PublicationCheckExistingCommit:'check_existing_commit',
    PublicationValidateExistingEvidence:'validate_existing_evidence',
    PublicationFinalizeExistingCommit:'finalize_existing_commit',
    PublicationReturnExistingCommit:'return_existing_commit',
    PublicationCheckInitialActive:'check_initial_active',PublicationPersistContracts:'persist_contracts',
    PublicationCreateAttempt:'create_attempt',PublicationEnterAttemptProgress:'enter_attempt_progress',
    PublicationSetupInvalid:'invalid',
  }),
  publication('attempt',runtime,'PublicationAttemptRuntimeAction',
    'publication_attempt_runtime_action_code', {
      PublicationAppendPreparing:'append_preparing',PublicationCheckActive:'check_active',
      PublicationAppendCommitting:'append_committing',PublicationIssueIndex:'issue_index',
      PublicationCommitIndex:'commit_index',PublicationRequireReconciliation:'require_reconciliation',
      PublicationRejectMissingIndex:'reject_missing_index',PublicationRejectTerminal:'reject_terminal',
      PublicationAttemptInvalid:'invalid',
    }),
  publication('cancellation',runtime,'PublicationCancellationAction',
    'publication_cancellation_action_code', {
      PublicationCancellationRethrow:'rethrow',PublicationCancelPreparing:'cancel_preparing',
      PublicationCancelCommitting:'cancel_committing',
    }),
  publication('finalization',runtime,'PublicationFinalizationAction',
    'publication_finalization_action_code', {
      PublicationFinalizationFinished:'finished',PublicationAppendSucceeded:'append_succeeded',
      PublicationAppendSuperseded:'append_superseded',PublicationSupersededConfirmed:'superseded_confirmed',
      PublicationFinalizationInvalid:'invalid',
    }),
  publication('commitFailure',runtime,'PublicationCommitFailureAction',
    'publication_commit_failure_action_code', {
      PublicationReconcileCommit:'reconcile_commit',PublicationAppendUnknown:'append_unknown',
      PublicationReturnUnknown:'return_unknown',PublicationConfirmUncommittedFailure:'confirm_uncommitted_failure',
      PublicationAdoptCommittedIndex:'adopt_committed_index',PublicationCommitFailureInvalid:'invalid',
    }),
  publication('unknownRetry',runtime,'PublicationUnknownRetryAction',
    'publication_unknown_retry_action_code', {
      PublicationRetryReconcile:'reconcile',PublicationRetryUpstreamCleanup:'retry_upstream_cleanup',
      PublicationUnknownRetryFinished:'finished',PublicationUnknownRetryInvalid:'invalid',
    }),
  publication('preparedRelease',cleanup,'PublicationPreparedReleaseAction',
    'publication_prepared_release_action_code', {
      PublicationInspectPreparedRelease:'inspect',PublicationReleasePrepared:'release',
      PublicationAdvancePreparedRelease:'advance',PublicationPreparedReleaseFinished:'finished',
      PublicationPreparedReleaseInvalid:'invalid',
    }),
  publication('cleanupOwner',cleanup,'PublicationCleanupOwnerAction',
    'publication_cleanup_owner_action_code', {
      PublicationInspectCleanupOwner:'inspect',PublicationRetryCleanupOwner:'retry',
      PublicationAdvanceCleanupOwner:'advance',PublicationCleanupOwnersFinished:'finished',
      PublicationCleanupOwnerInvalid:'invalid',
    }),
  publication('durablePayloadFailure',cleanup,'DurablePayloadFailureAction',
    'durable_payload_failure_action_code', {
      DurablePayloadCancelWriter:'cancel_writer',DurablePayloadReleasePrepared:'release_prepared',
      DurablePayloadCancelExport:'cancel_export',DurablePayloadFailureFinished:'finished',
      DurablePayloadFailureInvalid:'invalid',
    }),
  strategy('holding',site,'RetainedSiteHoldingAction','retained_site_holding_action_code',
    'InvalidExecutionSiteHoldingAction'),
  strategy('close',site,'RetainedSiteCloseAction','retained_site_close_action_code',
    'InvalidExecutionSiteCloseAction'),
  strategy('failure',site,'FailedSiteOperationAction','failed_site_operation_action_code',
    'InvalidExecutionSiteFailureAction'),
  strategy('taskSuccess','src/physical_strategy_host/host_task_success.mbt','HostTaskSuccessAction',
    'host_task_success_action_code','InvalidExecutionSiteHostTaskSuccessAction'),
  strategy('cleanup','src/physical_strategy_host/host_cleanup_progress.mbt','HostCleanupRuntimeAction',
    'host_cleanup_runtime_action_code','InvalidExecutionSiteHostCleanupAction'),
  strategy('outcome','src/physical_strategy_host/host_outcome.mbt','HostTaskRunOutcome',
    'host_task_run_outcome_code','InvalidExecutionSiteHostTaskRunOutcome'),
  strategy('managedFallback','src/execution_site/candidate_selection.mbt','ManagedCandidateFallbackResult',
    'managed_candidate_fallback_projection','InvalidManagedCandidateFallback',
    ['ManagedCandidateFallbackInvalid']),
]);
