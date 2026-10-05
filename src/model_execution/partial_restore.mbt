///|
/// Verified individual original, not a synthesized complete ObservationSet.
/// The Store owner authenticates custody before supplying its admitted leaves.
priv struct RestoredModelCall {
  record : @publication.RunEvidenceValue
  binding : @publication.BoundModelSlotCapture
  proof : ModelAttemptEvidence
  bundle : @publication.ModelCaptureBundleRead?
  outcome : String
}

///|
pub fn restore_prepared_model_call(
  prepared : ModelPreparedCallSet,
  slot : Int,
  record : @publication.RunEvidenceValue,
  records : ModelAttemptRecords,
  bundle : @publication.ModelCaptureBundleRead?,
) -> Result[Unit, ModelExecutionIssue] {
  let state = prepared.owner.state
  guard prepared_model_current(prepared) &&
    state.phase is DispatchSlot &&
    state.next_slot == 0 &&
    state.enter_call is None &&
    prepared.scope is Some(scope) &&
    !state.restored_calls.contains(slot) &&
    !state.unknown_calls.contains(slot) else {
    return Err(RequestIdentity)
  }
  let binding = match
    @publication.bind_model_invocation_saved_call(
      scope,
      slot,
      record,
      records.attempt,
      records.accounting,
      records.outcome,
      records.authority,
    ) {
    Ok(value) => value
    Err(issue) => return Err(InvocationEvidence(issue))
  }
  if @publication.check_model_slot_capture_policy(
      binding,
      @environment.model_task_data_handling_cid(state.task),
    )
    is Err(_) {
    return Err(RequestIdentity)
  }
  guard @publication.bound_model_slot_capture_outcome(binding) is Some(outcome) else {
    return Err(OutputIdentity)
  }
  if outcome == "ok" {
    guard bundle is Some(value) &&
      @publication.model_capture_bundle_count(value) == 1 else {
      return Err(OutputIdentity)
    }
    let response = match @publication.model_capture_bundle_record(value, 0) {
      Ok(value) => value
      Err(issue) => return Err(InvocationEvidence(issue))
    }
    if @publication.verify_model_slot_success_observation(
        binding,
        @publication.model_capture_record_evidence(response),
      )
      is Err(_) {
      return Err(OutputIdentity)
    }
  } else if saved_model_failure(outcome) is None ||
    @publication.verify_model_slot_no_response_failure(binding, outcome)
    is Err(_) {
    return Err(OutputIdentity)
  }
  let retained = match bundle {
    None => None
    Some(value) =>
      match @publication.retain_model_capture_bundle_read(value) {
        None => return Err(OutputIdentity)
        Some(value) => Some(value)
      }
  }
  state.restored_calls[slot] = {
    record,
    binding,
    bundle: retained,
    outcome,
    proof: {
      attempt: records.attempt,
      accounting: records.accounting,
      outcome: records.outcome,
      authority: records.authority,
    },
  }
  Ok(())
}

///|
/// An entered attempt without a proved response remains unknown. It can never
/// be converted to an unsent slot or an ordinary provider-failure row.
pub fn restore_prepared_model_unknown(
  prepared : ModelPreparedCallSet,
  slot : Int,
  attempt : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
) -> Result[Unit, ModelExecutionIssue] {
  let state = prepared.owner.state
  guard prepared_model_current(prepared) &&
    state.phase is DispatchSlot &&
    state.next_slot == 0 &&
    state.enter_call is None &&
    prepared.scope is Some(scope) &&
    !state.restored_calls.contains(slot) &&
    !state.unknown_calls.contains(slot) else {
    return Err(RequestIdentity)
  }
  match
    @publication.check_model_invocation_attempt(
      scope, slot, attempt, authority, 1L,
    ) {
    Err(issue) => return Err(InvocationEvidence(issue))
    Ok(_) => ()
  }
  state.unknown_calls[slot] = true
  Ok(())
}

///|
fn advance_partial_model_restore(
  state : ModelState,
  saved : RestoredModelCall,
  prepared : PreparedModelRequest,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  // Preserve the historical proofs exactly. New execution work cannot alter
  // the old accounting, timestamp, provider facts or adopted attempt identity.
  state.attempts[state.next_slot] = {
    attempt: saved.proof.attempt,
    call: prepared.call.unwrap(),
    authority: saved.proof.authority,
    reservation: None,
    input_tokens: None,
    output_tokens: None,
    category: if saved.outcome == "ok" {
      "ok"
    } else {
      "provider_failure"
    },
    failure: None,
    work: 0,
    response_cid: None,
    output_cid: None,
    response_issuer: None,
    evidence: Some(saved.proof),
  }
  state.attempt_slots.push(state.next_slot)
  if saved.outcome != "ok" {
    return accept_failed_model_slot(
      state,
      saved_model_failure(saved.outcome).unwrap(),
    )
  }
  state.restored_binding = Some(saved.binding)
  begin_restored_model_response(
    state,
    saved.bundle.unwrap(),
    prepared,
    record_index=0,
  )
}

///|
pub fn model_execution_unknown_calls(execution : ModelExecution) -> Bool {
  !execution.state.unknown_calls.is_empty() ||
  execution.state.attempt_slots.any(slot => {
    execution.state.outcomes.get(slot) is None
  })
}
