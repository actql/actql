///|
/// Immutable Run outcome. Current Result availability is validated separately
/// and never changes a terminal outcome.
pub(all) enum RunOutcomeStatus {
  Preparing
  Running
  WaitingCheckpoint
  Resuming
  NeedsReconciliation
  Succeeded
  Failed
  Cancelled
} derive(Eq, Debug)

///|
pub(all) enum ResultAvailabilityState {
  Available
  Unavailable
  Unknown
} derive(Eq, Debug)

///|
pub(all) enum ResultAvailabilityReason {
  ConfirmedPresent
  RetentionExpired
  Deleted
  PolicyUnavailable
  IntegrityFailed
  NotPublished
  StoreQueryFailed
  ClockUncertain
  VerificationPending
} derive(Eq, Debug)

///|
pub(all) struct ResultAvailability {
  name : String
  state : ResultAvailabilityState
  reason : ResultAvailabilityReason
} derive(Eq, Debug)

///|
/// The identity of an action is fixed independently of later authorization or
/// I/O. ReadResult is only an instruction to perform a separate authorized
/// read, not read authority itself.
pub(all) enum RunNextAction {
  ResolveCheckpoint
  Reconcile
  ReadResult(Array[String])
  RefreshAvailability(Array[String])
  NoAction
} derive(Eq, Debug)

///|
pub(all) enum RunStateIssue {
  EmptyDeclaredResults
  InvalidResultName(String)
  DuplicateDeclaredResult(String)
  DuplicateAvailability(String)
  MissingAvailability(String)
  ForeignAvailability(String)
  AvailabilityReasonMismatch(String)
  AggregateMismatch
  CheckpointMismatch
  ActionStatusMismatch
  EmptyActionResults
  DuplicateActionResult(String)
  UnknownActionResult(String)
  ResultNotAvailable(String)
  ResultNotUnknown(String)
} derive(Eq, Debug)

///|
fn canonical_result_name(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  match @canonical.normalize_nfc_lf(name) {
    Ok(value) => value == name
    Err(_) => false
  }
}

///|
fn reason_matches(
  state : ResultAvailabilityState,
  reason : ResultAvailabilityReason,
) -> Bool {
  match (state, reason) {
    (Available, ConfirmedPresent) => true
    (
      Unavailable,
      RetentionExpired
      | Deleted
      | PolicyUnavailable
      | IntegrityFailed
      | NotPublished,
    ) => true
    (Unknown, StoreQueryFailed | ClockUncertain | VerificationPending) => true
    _ => false
  }
}

///|
fn availability_state(
  observations : Array[ResultAvailability],
  name : String,
) -> ResultAvailabilityState? {
  for observation in observations {
    if observation.name == name {
      return Some(observation.state)
    }
  }
  None
}

///|
fn validate_targets(
  targets : Array[String],
  declared : Array[String],
  observations : Array[ResultAvailability],
  expected : ResultAvailabilityState,
) -> Result[Unit, RunStateIssue] {
  if targets.is_empty() {
    return Err(EmptyActionResults)
  }
  let seen : Array[String] = []
  for name in targets {
    if seen.contains(name) {
      return Err(DuplicateActionResult(name))
    }
    seen.push(name)
    if !declared.contains(name) {
      return Err(UnknownActionResult(name))
    }
    match availability_state(observations, name) {
      Some(state) if state == expected => ()
      Some(_) if expected == Available => return Err(ResultNotAvailable(name))
      Some(_) => return Err(ResultNotUnknown(name))
      None => return Err(MissingAvailability(name))
    }
  }
  Ok(())
}

///|
/// Validate the portable semantic projection of actql-run-state/0.1.
///
/// JSON Schema validates the closed wire shape. This function owns relations
/// between dynamic Result names, per-Result observations, their aggregate and
/// the action selected for the immutable Run outcome.
pub fn validate_run_state(
  status : RunOutcomeStatus,
  declared_results : Array[String],
  observations : Array[ResultAvailability],
  result_available : Bool,
  action : RunNextAction,
  has_checkpoint : Bool,
) -> Result[Unit, RunStateIssue] {
  if declared_results.is_empty() {
    return Err(EmptyDeclaredResults)
  }
  let declared_seen : Array[String] = []
  for name in declared_results {
    if !canonical_result_name(name) {
      return Err(InvalidResultName(name))
    }
    if declared_seen.contains(name) {
      return Err(DuplicateDeclaredResult(name))
    }
    declared_seen.push(name)
  }
  let observed_seen : Array[String] = []
  for observation in observations {
    if observed_seen.contains(observation.name) {
      return Err(DuplicateAvailability(observation.name))
    }
    observed_seen.push(observation.name)
    if !declared_results.contains(observation.name) {
      return Err(ForeignAvailability(observation.name))
    }
    if !reason_matches(observation.state, observation.reason) {
      return Err(AvailabilityReasonMismatch(observation.name))
    }
  }
  for name in declared_results {
    if !observed_seen.contains(name) {
      return Err(MissingAvailability(name))
    }
  }
  let all_available = observations.all(observation => {
    observation.state == Available
  })
  if result_available != all_available {
    return Err(AggregateMismatch)
  }
  match status {
    WaitingCheckpoint => {
      if !has_checkpoint {
        return Err(CheckpointMismatch)
      }
      if action is ResolveCheckpoint {
        return Ok(())
      }
      Err(ActionStatusMismatch)
    }
    NeedsReconciliation => {
      if has_checkpoint {
        return Err(CheckpointMismatch)
      }
      if action is Reconcile {
        return Ok(())
      }
      Err(ActionStatusMismatch)
    }
    Succeeded => {
      if has_checkpoint {
        return Err(CheckpointMismatch)
      }
      match action {
        ReadResult(targets) =>
          validate_targets(targets, declared_results, observations, Available)
        RefreshAvailability(targets) =>
          validate_targets(targets, declared_results, observations, Unknown)
        NoAction => Ok(())
        _ => Err(ActionStatusMismatch)
      }
    }
    _ => {
      if has_checkpoint {
        return Err(CheckpointMismatch)
      }
      if action is NoAction {
        return Ok(())
      }
      Err(ActionStatusMismatch)
    }
  }
}
