///|
/// Restore all adopted slots, including failures, under fresh ordinary input.
/// No provider is available to retry an absent, foreign or corrupt record.
pub fn start_restored_model_slot_replay(
  rows : @relation.PreparedInferRows,
  scope : @publication_host.ClientInferCallScope,
  read : ModelSlotReplayRead,
  fixed_request_cid : String,
  limits : ModelExecutionLimits,
) -> Result[ModelExecution, ModelExecutionIssue] {
  if model_slot_replay_count(read) !=
    Some(@relation.prepared_infer_rows_count(rows)) {
    return Err(OutputIdentity)
  }
  if read.storage.proofs is Some(_) {
    guard read.storage.observation is Some(observation) &&
      read.storage.saved_admission is Some(admission) &&
      read.storage.saved_definition is Some(definition) else {
      return Err(OutputIdentity)
    }
    match
      @publication_host.check_client_infer_saved_observation_scope(
        scope, admission, definition, observation,
      ) {
      Err(issue) => return Err(InvocationEvidence(issue))
      Ok(_) => ()
    }
  }
  guard retain_model_slot_replay(read) is Some(retained) else {
    return Err(OutputIdentity)
  }
  let started = start_model_owned(
    rows,
    RestoredSlots(retained),
    fixed_request_cid,
    limits,
    Some(scope),
  )
  if started is Err(_) {
    release_model_slot_replay(retained) |> ignore
  }
  started
}

///|
fn saved_model_failure(outcome : String) -> ModelProviderFailure? {
  match outcome {
    "failed:rate_limit" => Some(RateLimit)
    "failed:timeout" => Some(Timeout)
    "failed:provider_error" => Some(ProviderError)
    "failed:refusal" => Some(Refusal)
    "failed:schema_invalid" => Some(SchemaInvalid)
    "failed:safety_rejected" => Some(SafetyRejected)
    "failed:truncated" => Some(Truncated)
    _ => None
  }
}

///|
fn begin_restored_model_slot(
  state : ModelState,
  read : ModelSlotReplayRead,
  prepared : PreparedModelRequest,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  guard prepared.call is Some(call) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let binding = match
    restored_slot_binding(
      read,
      state.next_slot,
      call,
      @environment.model_task_data_handling_cid(state.task),
    ) {
    Err(issue) => return @bounded.Failed(issue, 1, 1)
    Ok(value) => value
  }
  guard @publication.bound_model_slot_capture_outcome(binding) is Some(outcome) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  if outcome != "ok" {
    guard saved_model_failure(outcome) is Some(failure) else {
      return @bounded.Failed(OutputIdentity, 1, 1)
    }
    match @publication.verify_model_slot_no_response_failure(binding, outcome) {
      Err(issue) => return @bounded.Failed(InvocationEvidence(issue), 1, 1)
      Ok(_) => ()
    }
    return accept_failed_model_slot(state, failure)
  }
  guard read.storage.bundle is Some(bundle) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  // Logical slot positions include failures; response positions do not.
  let index = state.captures.length()
  let record = match @publication.model_capture_bundle_record(bundle, index) {
    Err(issue) => return @bounded.Failed(InvocationEvidence(issue), 1, 1)
    Ok(value) => value
  }
  match
    @publication.verify_model_slot_success_observation(
      binding,
      @publication.model_capture_record_evidence(record),
    ) {
    Err(issue) => return @bounded.Failed(InvocationEvidence(issue), 1, 1)
    Ok(_) => ()
  }
  state.restored_binding = Some(binding)
  begin_restored_model_response(state, bundle, prepared, record_index=index)
}
