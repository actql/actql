///|
/// Portable progression for one publication attempt after no committed index
/// was found. Environment adapters perform the selected Store or clock
/// operation, then report the resulting observation to this planner.
pub(all) enum PublicationAttemptRuntimeAction {
  PublicationAppendPreparing
  PublicationCheckActive
  PublicationAppendCommitting
  PublicationIssueIndex
  PublicationCommitIndex
  PublicationRequireReconciliation
  PublicationRejectMissingIndex
  PublicationRejectTerminal
  PublicationAttemptInvalid
} derive(Eq, Debug)

///|
fn publication_record_state(record : PublicationContract) -> String? {
  if record.name != "publication_record" {
    return None
  }
  contract_string(record, "state")
}

///|
/// Select the next publication action from the admitted record and the
/// observations made for that exact record. `active_checked` is reset after
/// appending a new record. An index can only be issued after the current
/// committing record has passed its cancellation boundary.
pub fn prepare_publication_attempt_step(
  record : PublicationContract?,
  active_checked : Bool,
  index_issued : Bool,
) -> PublicationAttemptRuntimeAction {
  match record {
    None =>
      if active_checked || index_issued {
        PublicationAttemptInvalid
      } else {
        PublicationAppendPreparing
      }
    Some(value) =>
      match publication_record_state(value) {
        Some("preparing") =>
          if index_issued {
            PublicationAttemptInvalid
          } else if !active_checked {
            PublicationCheckActive
          } else {
            PublicationAppendCommitting
          }
        Some("committing") =>
          if index_issued && !active_checked {
            PublicationAttemptInvalid
          } else if !active_checked {
            PublicationCheckActive
          } else if !index_issued {
            PublicationIssueIndex
          } else {
            PublicationCommitIndex
          }
        Some("publication_unknown") => PublicationRequireReconciliation
        Some("succeeded") => PublicationRejectMissingIndex
        Some("failed") | Some("cancelled") => PublicationRejectTerminal
        _ => PublicationAttemptInvalid
      }
  }
}

///|
pub fn publication_attempt_runtime_action_code(
  action : PublicationAttemptRuntimeAction,
) -> Int {
  match action {
    PublicationAppendPreparing => 0
    PublicationCheckActive => 1
    PublicationAppendCommitting => 2
    PublicationIssueIndex => 3
    PublicationCommitIndex => 4
    PublicationRequireReconciliation => 5
    PublicationRejectMissingIndex => 6
    PublicationRejectTerminal => 7
    PublicationAttemptInvalid => 8
  }
}

///|
/// Cancellation only appends a terminal record while the exact attempt is in
/// an active state. A committing attempt requires durable confirmation that
/// no publication commit exists before cancellation can become terminal.
pub(all) enum PublicationCancellationAction {
  PublicationCancellationRethrow
  PublicationCancelPreparing
  PublicationCancelCommitting
} derive(Eq, Debug)

///|
pub fn prepare_publication_cancellation_step(
  record : PublicationContract?,
) -> PublicationCancellationAction {
  match record {
    Some(value) =>
      match publication_record_state(value) {
        Some("preparing") => PublicationCancelPreparing
        Some("committing") => PublicationCancelCommitting
        _ => PublicationCancellationRethrow
      }
    None => PublicationCancellationRethrow
  }
}

///|
pub fn publication_cancellation_action_code(
  action : PublicationCancellationAction,
) -> Int {
  match action {
    PublicationCancellationRethrow => 0
    PublicationCancelPreparing => 1
    PublicationCancelCommitting => 2
  }
}

///|
/// Finalization is separate from index commit. The public index can already
/// be durable while the append-only attempt record still needs its terminal
/// observation, including after a lost response and reconciliation.
pub(all) enum PublicationFinalizationAction {
  PublicationFinalizationFinished
  PublicationAppendSucceeded
  PublicationAppendSuperseded
  PublicationSupersededConfirmed
  PublicationFinalizationInvalid
} derive(Eq, Debug)

///|
pub fn prepare_committed_publication_finalization(
  record : PublicationContract?,
) -> PublicationFinalizationAction {
  match record {
    Some(value) =>
      match publication_record_state(value) {
        Some("succeeded") => PublicationFinalizationFinished
        Some("committing") | Some("publication_unknown") =>
          PublicationAppendSucceeded
        _ => PublicationFinalizationInvalid
      }
    None => PublicationFinalizationInvalid
  }
}

///|
pub fn prepare_superseded_publication_finalization(
  record : PublicationContract?,
) -> PublicationFinalizationAction {
  match record {
    None => PublicationFinalizationFinished
    Some(value) =>
      match publication_record_state(value) {
        Some("cancelled") => PublicationSupersededConfirmed
        Some("failed") | Some("succeeded") => PublicationFinalizationFinished
        Some("committing") | Some("publication_unknown") =>
          PublicationAppendSuperseded
        _ => PublicationFinalizationInvalid
      }
  }
}

///|
pub fn publication_finalization_action_code(
  action : PublicationFinalizationAction,
) -> Int {
  match action {
    PublicationFinalizationFinished => 0
    PublicationAppendSucceeded => 1
    PublicationAppendSuperseded => 2
    PublicationSupersededConfirmed => 3
    PublicationFinalizationInvalid => 4
  }
}

///|
/// Progression after the physical public-index commit reports a failure. The
/// adapter reports whether an authoritative lookup failed, confirmed absence,
/// or found the exact commit. A failed lookup must first persist uncertainty;
/// it never authorizes a second commit attempt.
pub(all) enum PublicationCommitFailureAction {
  PublicationReconcileCommit
  PublicationAppendUnknown
  PublicationReturnUnknown
  PublicationConfirmUncommittedFailure
  PublicationAdoptCommittedIndex
  PublicationCommitFailureInvalid
} derive(Eq, Debug)

///|
pub fn prepare_publication_commit_failure_step(
  reconciliation_attempted : Bool,
  reconciliation_failed : Bool,
  committed_found : Bool,
  unknown_append_attempted : Bool,
) -> PublicationCommitFailureAction {
  if (reconciliation_failed && !reconciliation_attempted) ||
    (committed_found && (!reconciliation_attempted || reconciliation_failed)) ||
    (unknown_append_attempted && !reconciliation_failed) {
    return PublicationCommitFailureInvalid
  }
  if !reconciliation_attempted {
    return PublicationReconcileCommit
  }
  if reconciliation_failed {
    if !unknown_append_attempted {
      return PublicationAppendUnknown
    }
    return PublicationReturnUnknown
  }
  if committed_found {
    PublicationAdoptCommittedIndex
  } else {
    PublicationConfirmUncommittedFailure
  }
}

///|
pub fn publication_commit_failure_action_code(
  action : PublicationCommitFailureAction,
) -> Int {
  match action {
    PublicationReconcileCommit => 0
    PublicationAppendUnknown => 1
    PublicationReturnUnknown => 2
    PublicationConfirmUncommittedFailure => 3
    PublicationAdoptCommittedIndex => 4
    PublicationCommitFailureInvalid => 5
  }
}

///|
/// Retry progression for an unknown publication outcome. Reconciliation is
/// always performed before an independent upstream cleanup retry. Historical
/// retry errors are diagnostics and do not become current cleanup ownership.
pub(all) enum PublicationUnknownRetryAction {
  PublicationRetryReconcile
  PublicationRetryUpstreamCleanup
  PublicationUnknownRetryFinished
  PublicationUnknownRetryInvalid
} derive(Eq, Debug)

///|
pub fn prepare_publication_unknown_retry_step(
  reconciliation_resolved : Bool,
  upstream_pending : Bool,
  upstream_retry_available : Bool,
  upstream_retry_attempted : Bool,
) -> PublicationUnknownRetryAction {
  if upstream_retry_attempted && !reconciliation_resolved {
    return PublicationUnknownRetryInvalid
  }
  if !reconciliation_resolved {
    return PublicationRetryReconcile
  }
  if upstream_pending && upstream_retry_available && !upstream_retry_attempted {
    return PublicationRetryUpstreamCleanup
  }
  PublicationUnknownRetryFinished
}

///|
pub fn publication_unknown_retry_action_code(
  action : PublicationUnknownRetryAction,
) -> Int {
  match action {
    PublicationRetryReconcile => 0
    PublicationRetryUpstreamCleanup => 1
    PublicationUnknownRetryFinished => 2
    PublicationUnknownRetryInvalid => 3
  }
}
