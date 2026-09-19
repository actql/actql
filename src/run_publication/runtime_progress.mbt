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
