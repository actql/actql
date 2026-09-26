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
  InvalidRunId
  InvalidObservationTime(String)
  Encoding
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

///|
fn availability_state_text(state : ResultAvailabilityState) -> String {
  match state {
    Available => "available"
    Unavailable => "unavailable"
    Unknown => "unknown"
  }
}

///|
fn availability_reason_text(reason : ResultAvailabilityReason) -> String {
  match reason {
    ConfirmedPresent => "confirmed_present"
    RetentionExpired => "retention_expired"
    Deleted => "deleted"
    PolicyUnavailable => "policy_unavailable"
    IntegrityFailed => "integrity_failed"
    NotPublished => "not_published"
    StoreQueryFailed => "store_query_failed"
    ClockUncertain => "clock_uncertain"
    VerificationPending => "verification_pending"
  }
}

///|
fn action_for_succeeded_run(
  observations : Array[ResultAvailability],
) -> RunNextAction {
  let unknown : Array[String] = []
  let available : Array[String] = []
  for observation in observations {
    match observation.state {
      Unknown => unknown.push(observation.name)
      Available => available.push(observation.name)
      Unavailable => ()
    }
  }
  if !unknown.is_empty() {
    RefreshAvailability(unknown)
  } else if !available.is_empty() {
    ReadResult(available)
  } else {
    NoAction
  }
}

///|
/// Issue the canonical succeeded-Run state from exact Store observations.
/// The environment adapter observes storage and policy facts; this portable
/// owner fixes the aggregate and the only state-consistent next action.
pub fn issue_succeeded_run_state(
  run_id : String,
  updated_at : String,
  declared_results : Array[String],
  observations : Array[ResultAvailability],
  observed_at : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RunStateIssue] {
  if run_id.is_empty() {
    return Err(InvalidRunId)
  }
  if observations.length() != observed_at.length() ||
    !valid_timestamp(updated_at) {
    return Err(InvalidObservationTime("run"))
  }
  for index, timestamp in observed_at {
    if !valid_timestamp(timestamp) {
      return Err(InvalidObservationTime(observations[index].name))
    }
  }
  let ordered = observations.copy()
  ordered.sort_by((left, right) => {
    @canonical.compare_utf16(left.name, right.name)
  })
  let times : Array[String] = []
  for item in ordered {
    let mut found = false
    for index, original in observations {
      if original.name == item.name {
        times.push(observed_at[index])
        found = true
      }
    }
    if !found {
      return Err(MissingAvailability(item.name))
    }
  }
  let declared = declared_results.copy()
  declared.sort_by(@canonical.compare_utf16)
  let action = action_for_succeeded_run(ordered)
  let all_available = ordered.all(item => item.state == Available)
  match
    validate_run_state(
      Succeeded,
      declared,
      ordered,
      all_available,
      action,
      false,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "next_action")
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    match action {
      ReadResult(results) => {
        @encode.string_value(writer, "read_result")
        @encode.key(writer, "results")
        @encode.begin_array(writer)
        for result in results {
          @encode.string_value(writer, result)
        }
        @encode.end_array(writer)
      }
      RefreshAvailability(results) => {
        @encode.string_value(writer, "refresh_availability")
        @encode.key(writer, "results")
        @encode.begin_array(writer)
        for result in results {
          @encode.string_value(writer, result)
        }
        @encode.end_array(writer)
      }
      NoAction => @encode.string_value(writer, "none")
      _ => return Err(ActionStatusMismatch)
    }
    @encode.end_object(writer)
    @encode.key(writer, "result_availability")
    @encode.begin_object(writer)
    for index, observation in ordered {
      @encode.key(writer, observation.name)
      @encode.begin_object(writer)
      @encode.key(writer, "observed_at")
      @encode.string_value(writer, times[index])
      @encode.key(writer, "reason")
      @encode.string_value(writer, availability_reason_text(observation.reason))
      @encode.key(writer, "state")
      @encode.string_value(writer, availability_state_text(observation.state))
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "result_available")
    @encode.bool_value(writer, all_available)
    @encode.key(writer, "run_id")
    @encode.string_value(writer, run_id)
    @encode.key(writer, "status")
    @encode.string_value(writer, "succeeded")
    @encode.key(writer, "updated_at")
    @encode.string_value(writer, updated_at)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-run-state/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Portable string boundary used by environment adapters. State and reason
/// tokens are decoded here so adapters cannot own a second relation table.
pub fn issue_succeeded_run_state_wire(
  run_id : String,
  updated_at : String,
  declared_results : Array[String],
  names : Array[String],
  states : Array[String],
  reasons : Array[String],
  observed_at : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RunStateIssue] {
  if names.length() != states.length() ||
    names.length() != reasons.length() ||
    names.length() != observed_at.length() {
    return Err(MissingAvailability("observation"))
  }
  let observations : Array[ResultAvailability] = []
  for index, name in names {
    let state = match states[index] {
      "available" => Available
      "unavailable" => Unavailable
      "unknown" => Unknown
      _ => return Err(AvailabilityReasonMismatch(name))
    }
    let reason = match reasons[index] {
      "confirmed_present" => ConfirmedPresent
      "retention_expired" => RetentionExpired
      "deleted" => Deleted
      "policy_unavailable" => PolicyUnavailable
      "integrity_failed" => IntegrityFailed
      "not_published" => NotPublished
      "store_query_failed" => StoreQueryFailed
      "clock_uncertain" => ClockUncertain
      "verification_pending" => VerificationPending
      _ => return Err(AvailabilityReasonMismatch(name))
    }
    observations.push({ name, state, reason, })
  }
  issue_succeeded_run_state(
    run_id, updated_at, declared_results, observations, observed_at, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
/// Project a Run before its publication index is committed. The caller
/// supplies the durable dispatch claim, a confirmed pre-dispatch failure and
/// the checked Result inventory; this owner chooses the phase, availability
/// and action. Loss of worker observation after a reservation does not prove
/// Run failure. Effect reconciliation has a distinct state and cannot be
/// inferred from an interrupted Effect-free Compute.
pub fn issue_effect_free_unpublished_run_state_wire(
  run_id : String,
  updated_at : String,
  declared_results : Array[String],
  dispatch_reserved : Bool,
  pre_dispatch_failure_confirmed : Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  cancelled_before_start? : Bool = false,
) -> Result[String, RunStateIssue] {
  if run_id.is_empty() {
    return Err(InvalidRunId)
  }
  if !valid_timestamp(updated_at) {
    return Err(InvalidObservationTime("run"))
  }
  if pre_dispatch_failure_confirmed && !dispatch_reserved {
    return Err(ActionStatusMismatch)
  }
  let status = if cancelled_before_start && !pre_dispatch_failure_confirmed {
    RunOutcomeStatus::Cancelled
  } else if !dispatch_reserved {
    RunOutcomeStatus::Preparing
  } else if pre_dispatch_failure_confirmed {
    RunOutcomeStatus::Failed
  } else {
    RunOutcomeStatus::Running
  }
  let names = declared_results.copy()
  names.sort_by(@canonical.compare_utf16)
  let observations : Array[ResultAvailability] = []
  for name in names {
    observations.push({ name, state: Unavailable, reason: NotPublished, })
  }
  match
    validate_run_state(status, names, observations, false, NoAction, false) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "next_action")
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "none")
    @encode.end_object(writer)
    @encode.key(writer, "result_availability")
    @encode.begin_object(writer)
    for name in names {
      @encode.key(writer, name)
      @encode.begin_object(writer)
      @encode.key(writer, "observed_at")
      @encode.string_value(writer, updated_at)
      @encode.key(writer, "reason")
      @encode.string_value(writer, "not_published")
      @encode.key(writer, "state")
      @encode.string_value(writer, "unavailable")
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "result_available")
    @encode.bool_value(writer, false)
    @encode.key(writer, "run_id")
    @encode.string_value(writer, run_id)
    @encode.key(writer, "status")
    @encode.string_value(
      writer,
      match status {
        RunOutcomeStatus::Preparing => "preparing"
        RunOutcomeStatus::Running => "running"
        RunOutcomeStatus::Failed => "failed"
        RunOutcomeStatus::Cancelled => "cancelled"
        _ => return Err(Encoding)
      },
    )
    if status is RunOutcomeStatus::Failed {
      @encode.key(writer, "terminal_error")
      @encode.begin_object(writer)
      @encode.key(writer, "code")
      @encode.string_value(writer, "ACTQL_E_UNPUBLISHED_RUN")
      @encode.key(writer, "message")
      @encode.string_value(writer, "Run ended before publication")
      @encode.end_object(writer)
    }
    @encode.key(writer, "updated_at")
    @encode.string_value(writer, updated_at)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-run-state/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// An independent, revisioned physical-control observation. Request acceptance
/// alone is never stop evidence; missing workers and elapsed time are not
/// inputs. A confirmed unstarted Run is stopped only after cancellation has
/// durably excluded any later start claim.
pub fn issue_run_control_observation_wire(
  revision : Int,
  cancellation_requested : Bool,
  physically_unstarted : Bool,
  pre_dispatch_failure_confirmed : Bool,
  physical_close_confirmed : Bool,
) -> Result[String, RunStateIssue] {
  if revision < 0 {
    return Err(ActionStatusMismatch)
  }
  let stopped = physical_close_confirmed ||
    pre_dispatch_failure_confirmed ||
    (cancellation_requested && physically_unstarted)
  let writer = @encode.writer(1024, 16, 4) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "cancellation_requested")
    @encode.bool_value(writer, cancellation_requested)
    @encode.key(writer, "physical_stop")
    @encode.string_value(writer, if stopped { "confirmed" } else { "unknown" })
    @encode.key(writer, "revision")
    @encode.number_value(writer, revision.to_double())
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}
