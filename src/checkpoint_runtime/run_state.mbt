///|
const RUN_STATE_VERSION : String = "actql-run-state/0.1"

///|
fn sorted_results(
  declared_results : Array[String],
) -> Result[Array[String], RunStateWireIssue] {
  let declared = declared_results.copy()
  declared.sort_by(@canonical.compare_utf16)
  Ok(declared)
}

///|
fn lifecycle_run_state_body(
  run_id : String,
  status : @publication.RunOutcomeStatus,
  updated_at : String,
  declared_results : Array[String],
  checkpoint : SealedCheckpoint?,
  limits : WireLimits,
  terminal_error? : (String, String),
  reconcile_effects? : Array[String] = [],
) -> Result[String, RunStateWireIssue] {
  if !canonical_text(run_id) {
    return Err(RunStateInvalidField("run_id"))
  }
  if !valid_timestamp(updated_at) {
    return Err(RunStateInvalidField("updated_at"))
  }
  if !valid_limits(limits) {
    return Err(RunStateEncoding)
  }
  let declared = match sorted_results(declared_results) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let observations : Array[@publication.ResultAvailability] = declared.map(name => {
    name,
    state: Unavailable,
    reason: NotPublished,
  })
  let action : @publication.RunNextAction = if checkpoint is Some(_) {
    ResolveCheckpoint
  } else if !reconcile_effects.is_empty() {
    Reconcile
  } else {
    NoAction
  }
  for index, effect in reconcile_effects {
    if !canonical_text(effect) || reconcile_effects[:index].contains(effect) {
      return Err(RunStateInvalidField("next_action.effects"))
    }
  }
  match
    @publication.validate_run_state(
      status,
      declared,
      observations,
      false,
      action,
      checkpoint is Some(_),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(RunStateRelation(issue))
  }
  let availability : Map[String, Json] = Map([])
  for name in declared {
    availability[name] = Json::object({
      "state": Json::string("unavailable"),
      "observed_at": Json::string(updated_at),
      "reason": Json::string("not_published"),
    })
  }
  let fields : Map[String, Json] = {
    "version": Json::string(RUN_STATE_VERSION),
    "run_id": Json::string(run_id),
    "status": Json::string(run_status_token(status)),
    "updated_at": Json::string(updated_at),
    "next_action": Json::object({ "kind": Json::string("none") }),
    "result_available": Json::boolean(false),
    "result_availability": Json::object(availability),
  }
  if !reconcile_effects.is_empty() {
    fields["next_action"] = Json::object({
      "kind": Json::string("reconcile"),
      "effects": string_array_json(reconcile_effects),
    })
  }
  if terminal_error is Some((code, message)) {
    fields["terminal_error"] = Json::object({
      "code": Json::string(code),
      "message": Json::string(message),
    })
  }
  if checkpoint is Some(artifact) {
    fields["checkpoint"] = Json::object({
      "checkpoint_id": Json::string(artifact.checkpoint.checkpoint_id),
      "checkpoint_cid": Json::string(artifact.checkpoint_cid),
      "kind": Json::string(checkpoint_kind_token(artifact.checkpoint.kind)),
    })
    fields["next_action"] = Json::object({
      "kind": Json::string("resolve_checkpoint"),
      "checkpoint_id": Json::string(artifact.checkpoint.checkpoint_id),
    })
  }
  match canonical_of(Json::object(fields), limits) {
    Some(value) =>
      match wire_of(value, limits) {
        Some(wire) => Ok(wire)
        None => Err(RunStateEncoding)
      }
    None => Err(RunStateEncoding)
  }
}

///|
/// Waiting projection. It requires a `PersistedCheckpoint`, so no caller can
/// claim a waiting Checkpoint before the journal committed it.
pub fn issue_waiting_run_state(
  checkpoint : PersistedCheckpoint,
  updated_at : String,
  declared_results : Array[String],
  limits : WireLimits,
) -> Result[String, RunStateWireIssue] {
  let artifact = checkpoint.artifact
  // A preparation Checkpoint precedes its Run, so it has no Run state.
  let run_id = match artifact.checkpoint.run_id() {
    Some(run_id) => run_id
    None => return Err(RunStateInvalidField("checkpoint.subject"))
  }
  lifecycle_run_state_body(
    run_id,
    WaitingCheckpoint,
    updated_at,
    declared_results,
    Some(artifact),
    limits,
  )
}

///|
/// Checkpoint lifecycle projections without a Checkpoint or Result: used for
/// `resuming`, `cancelled` and `failed` entered by this lifecycle, with no
/// Result published and no next action.
pub fn issue_lifecycle_run_state(
  run_id : String,
  status : @publication.RunOutcomeStatus,
  updated_at : String,
  declared_results : Array[String],
  limits : WireLimits,
) -> Result[String, RunStateWireIssue] {
  match status {
    Preparing | Running | Resuming | Failed | Cancelled =>
      lifecycle_run_state_body(
        run_id,
        status,
        updated_at,
        declared_results,
        None,
        limits,
      )
    _ => Err(RunStateInvalidField("status"))
  }
}

///|
priv suberror RunStateFailure {
  RunStateFailed(RunStateWireIssue)
}

///|
fn run_state_shape(
  value : @json.CanonicalValue,
  required : Array[String],
  optional : Array[String],
  prefix : String,
) -> Unit raise RunStateFailure {
  match closed_shape(value, required, optional) {
    Some(Unknown(key)) =>
      raise RunStateFailed(RunStateUnknownField(prefix + key))
    Some(Missing(key)) =>
      raise RunStateFailed(RunStateMissingField(prefix + key))
    Some(NotObject) => raise RunStateFailed(RunStateInvalidField(prefix))
    None => ()
  }
}

///|
fn run_state_text(
  value : @json.CanonicalValue,
  key : String,
) -> String raise RunStateFailure {
  match string_field(value, key) {
    Some(text) if text != "" => text
    _ => raise RunStateFailed(RunStateInvalidField(key))
  }
}

///|
fn run_state_names(
  value : @json.CanonicalValue,
  key : String,
) -> Array[String] raise RunStateFailure {
  match string_list_field(value, key) {
    Some(names) if !names.is_empty() => names
    _ => raise RunStateFailed(RunStateInvalidField("next_action." + key))
  }
}

///|
fn decode_availability(
  name : String,
  value : @json.CanonicalValue,
) -> @publication.ResultAvailability raise RunStateFailure {
  let prefix = "result_availability." + name + "."
  run_state_shape(
    value,
    ["state", "observed_at", "reason"],
    ["cause_cid"],
    prefix,
  )
  if !valid_timestamp(run_state_text(value, "observed_at")) {
    raise RunStateFailed(RunStateInvalidField(prefix + "observed_at"))
  }
  if @json.object_field(value, "cause_cid") is Some(_) &&
    !valid_cid(run_state_text(value, "cause_cid")) {
    raise RunStateFailed(RunStateInvalidField(prefix + "cause_cid"))
  }
  let state : @publication.ResultAvailabilityState = match
    run_state_text(value, "state") {
    "available" => Available
    "unavailable" => Unavailable
    "unknown" => Unknown
    _ => raise RunStateFailed(RunStateInvalidField(prefix + "state"))
  }
  let reason : @publication.ResultAvailabilityReason = match
    run_state_text(value, "reason") {
    "confirmed_present" => ConfirmedPresent
    "retention_expired" => RetentionExpired
    "deleted" => Deleted
    "policy_unavailable" => PolicyUnavailable
    "integrity_failed" => IntegrityFailed
    "not_published" => NotPublished
    "store_query_failed" => StoreQueryFailed
    "clock_uncertain" => ClockUncertain
    "verification_pending" => VerificationPending
    _ => raise RunStateFailed(RunStateInvalidField(prefix + "reason"))
  }
  { name, state, reason, }
}

///|
fn decode_run_state(
  value : @json.CanonicalValue,
  limits : WireLimits,
) -> RunStateView raise RunStateFailure {
  run_state_shape(
    value,
    [
      "version", "run_id", "status", "updated_at", "next_action", "result_available",
      "result_availability",
    ],
    ["checkpoint", "terminal_error"],
    "",
  )
  if string_field(value, "version") != Some(RUN_STATE_VERSION) {
    raise RunStateFailed(RunStateInvalidField("version"))
  }
  let run_id = run_state_text(value, "run_id")
  let status = match parse_run_status(run_state_text(value, "status")) {
    Some(status) => status
    None => raise RunStateFailed(RunStateInvalidField("status"))
  }
  if !valid_timestamp(run_state_text(value, "updated_at")) {
    raise RunStateFailed(RunStateInvalidField("updated_at"))
  }
  let (checkpoint_cid, checkpoint_id) = match
    @json.object_field(value, "checkpoint") {
    Some(checkpoint) => {
      run_state_shape(
        checkpoint,
        ["checkpoint_id", "checkpoint_cid", "kind"],
        [],
        "checkpoint.",
      )
      let cid = run_state_text(checkpoint, "checkpoint_cid")
      if !valid_cid(cid) {
        raise RunStateFailed(RunStateInvalidField("checkpoint.checkpoint_cid"))
      }
      if parse_checkpoint_kind(run_state_text(checkpoint, "kind")) is None {
        raise RunStateFailed(RunStateInvalidField("checkpoint.kind"))
      }
      (Some(cid), Some(run_state_text(checkpoint, "checkpoint_id")))
    }
    None => (None, None)
  }
  if @json.object_field(value, "terminal_error") is Some(error) {
    run_state_shape(error, ["code", "message"], [], "terminal_error.")
    let code = run_state_text(error, "code")
    if !code.has_prefix("ACTQL_E_") || code.length() == 8 {
      raise RunStateFailed(RunStateInvalidField("terminal_error.code"))
    }
    for index in 8..<code.length() {
      let character = code[index].to_int()
      if !((character >= 'A'.to_int() && character <= 'Z'.to_int()) ||
        (character >= '0'.to_int() && character <= '9'.to_int()) ||
        character == '_'.to_int()) {
        raise RunStateFailed(RunStateInvalidField("terminal_error.code"))
      }
    }
    ignore(run_state_text(error, "message"))
  }
  let next = match @json.object_field(value, "next_action") {
    Some(next) => next
    None => raise RunStateFailed(RunStateMissingField("next_action"))
  }
  let action : @publication.RunNextAction = match run_state_text(next, "kind") {
    "resolve_checkpoint" => {
      run_state_shape(next, ["kind", "checkpoint_id"], [], "next_action.")
      if Some(run_state_text(next, "checkpoint_id")) != checkpoint_id {
        raise RunStateFailed(RunStateRelation(CheckpointMismatch))
      }
      ResolveCheckpoint
    }
    "reconcile" => {
      run_state_shape(next, ["kind", "effects"], [], "next_action.")
      let effects = run_state_names(next, "effects")
      for index, effect in effects {
        if effect.is_empty() || effects[:index].contains(effect) {
          raise RunStateFailed(RunStateInvalidField("next_action.effects"))
        }
      }
      Reconcile
    }
    "read_result" => {
      run_state_shape(next, ["kind", "results"], [], "next_action.")
      ReadResult(run_state_names(next, "results"))
    }
    "refresh_availability" => {
      run_state_shape(next, ["kind", "results"], [], "next_action.")
      RefreshAvailability(run_state_names(next, "results"))
    }
    "none" => {
      run_state_shape(next, ["kind"], [], "next_action.")
      NoAction
    }
    _ => raise RunStateFailed(RunStateInvalidField("next_action.kind"))
  }
  let result_available = match @json.object_field(value, "result_available") {
    Some(Bool(flag)) => flag
    _ => raise RunStateFailed(RunStateInvalidField("result_available"))
  }
  let availability = match @json.object_field(value, "result_availability") {
    Some(item) =>
      match @json.object_fields(item) {
        Some(entries) => entries
        None =>
          raise RunStateFailed(RunStateInvalidField("result_availability"))
      }
    None => raise RunStateFailed(RunStateMissingField("result_availability"))
  }
  let declared : Array[String] = []
  let observations : Array[@publication.ResultAvailability] = []
  for entry in availability {
    let (name, item) = entry
    declared.push(name)
    observations.push(decode_availability(name, item))
  }
  match
    @publication.validate_run_state(
      status,
      declared,
      observations,
      result_available,
      action,
      checkpoint_cid is Some(_),
    ) {
    Ok(_) => ()
    Err(issue) => raise RunStateFailed(RunStateRelation(issue))
  }
  let wire = match wire_of(value, limits) {
    Some(wire) => wire
    None => raise RunStateFailed(RunStateEncoding)
  }
  { run_id, status, checkpoint_cid, wire, }
}

///|
/// Admit an `actql-run-state/0.1` projection supplied by the resumed
/// continuation (for example a succeeded state issued by Run publication).
pub fn admit_run_state_wire(
  wire : String,
  limits : WireLimits,
) -> Result[RunStateView, RunStateWireIssue] {
  let value = match parse_wire(wire, limits) {
    Some(value) => value
    None => return Err(RunStateInvalidWire)
  }
  Ok(decode_run_state(value, limits)) catch {
    RunStateFailed(issue) => Err(issue)
  }
}

///|
/// Run state of a Run-unit continuation that failed resume revalidation. The
/// status is `failed`, or `needs_reconciliation` with a `reconcile` action
/// over `unknown_effects` when earlier Effect outcomes remain unknown; either
/// carries `terminal_error.code` `ACTQL_E_RESUME_REVALIDATION_FAILED`.
pub fn issue_revalidation_failed_run_state(
  run_id : String,
  updated_at : String,
  declared_results : Array[String],
  unknown_effects : Array[String],
  limits : WireLimits,
) -> Result[String, RunStateWireIssue] {
  lifecycle_run_state_body(
    run_id,
    revalidation_failure_status(unknown_effects),
    updated_at,
    declared_results,
    None,
    limits,
    terminal_error=(
      RESUME_REVALIDATION_FAILED_CODE,
      "Resume revalidation failed; the continuation was not dispatched.",
    ),
    reconcile_effects=unknown_effects,
  )
}
