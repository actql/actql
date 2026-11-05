///|
/// Verified individual original, not a synthesized complete ObservationSet.
/// The Store owner authenticates custody before supplying its admitted leaves.
priv struct RestoredModelCall {
  record : @publication.RunEvidenceValue
  binding : @publication.BoundModelSlotCapture
  proof : ModelAttemptEvidence
  bundle : @publication.ModelCaptureBundleRead?
  attachment_admission : @publication.RunEvidenceValue?
  outcome : String
}

///|
priv struct UnknownModelAttempt {
  attempt : @publication.RunEvidenceValue
  authority : @publication.RunEvidenceValue
}

///|
pub fn restore_prepared_model_call(
  prepared : ModelPreparedCallSet,
  slot : Int,
  record : @publication.RunEvidenceValue,
  records : ModelAttemptRecords,
  bundle : @publication.ModelCaptureBundleRead?,
  attachment_admission : @publication.RunEvidenceValue?,
) -> Result[Unit, ModelExecutionIssue] {
  let state = prepared.owner.state
  guard prepared_model_current(prepared) &&
    state.progress.phase is DispatchSlot &&
    state.progress.slot == 0 &&
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
  let attachment_admission = match
    restore_model_attachment_admission(
      record,
      records.authority,
      attachment_admission,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
  match check_original_mock_saved_attempt(state, slot) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
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
    attachment_admission,
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
    state.progress.phase is DispatchSlot &&
    state.progress.slot == 0 &&
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
  match check_original_mock_saved_attempt(state, slot) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  state.unknown_calls[slot] = { attempt, authority, }
  Ok(())
}

///|
/// Read custody for one already-entered attempt, never permission to send.
/// The common owner reserves its finite envelope before provider retrieval.
pub struct ModelResponseReconciliation {
  prepared : ModelPreparedCallSet
  slot : Int
  attempt : @publication.RunEvidenceValue
  authority : @publication.RunEvidenceValue
  mut adopted : Bool
}

///|
pub fn prepare_model_response_reconciliation(
  prepared : ModelPreparedCallSet,
  slot : Int,
  attempt : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
) -> Result[ModelResponseReconciliation, ModelExecutionIssue] {
  let state = prepared.owner.state
  guard prepared_model_current(prepared) &&
    state.progress.phase is DispatchSlot &&
    state.progress.slot == 0 &&
    state.enter_call is Some(_) &&
    prepared.scope is Some(scope) &&
    state.dispatch_admission is Some(admission) &&
    state.unknown_calls.get(slot) is Some(unknown) &&
    @publication.run_evidence_value_json(unknown.attempt) ==
    @publication.run_evidence_value_json(attempt) &&
    @publication.run_evidence_value_json(unknown.authority) ==
    @publication.run_evidence_value_json(authority) &&
    !state.reservations.contains(slot) &&
    !state.response_reconciliations.contains(slot) else {
    return Err(RequestIdentity)
  }
  match @publication_host.check_client_infer_dispatch_current(admission) {
    Err(issue) => return Err(Authorization(issue))
    Ok(_) => ()
  }
  if state.egress_admission is Some(egress) {
    match @publication_host.check_client_infer_egress_current(egress) {
      Err(issue) => return Err(Egress(issue))
      Ok(_) => ()
    }
  }
  match
    @publication.check_model_invocation_attempt(
      scope, slot, attempt, authority, 1L,
    ) {
    Err(issue) => return Err(InvocationEvidence(issue))
    Ok(_) => ()
  }
  // This lookup observes the SAME already-entered Unknown attempt. Its
  // actual read/quantity custody is funded below on the same Run, but it
  // cannot require or grant another Model dispatch/retry attempt.
  match
    check_original_mock_capacity(
      state,
      state.limits.max_request_bytes + state.limits.max_response_bytes + 81920L,
      0L,
      reserve_quantities=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let reservation = match
    @resources.reserve_attempt(
      state.ledger,
      state.limits.max_request_bytes + state.limits.max_response_bytes,
      state.limits.max_request_bytes + state.limits.max_response_bytes + 81920L,
      0L,
      quantities=state.quantity_capacity.map(value => value.per_attempt),
    ) {
    Err(issue) => return Err(Ledger(issue))
    Ok(value) => value
  }
  // Even missing or invalid original responses leave their sent usage unknown.
  // Cleanup owns this reservation, including any failed retrieval/adoption.
  state.reservations[slot] = reservation
  match mark_model_attempt_entered(state, reservation) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  if state.quantity_capacity is Some(_) {
    match @resources.mark_quantities_uncertain(state.ledger, reservation) {
      Err(issue) => return Err(Ledger(issue))
      Ok(_) => ()
    }
  }
  let token = { prepared, slot, attempt, authority, adopted: false, }
  state.response_reconciliations[slot] = token
  Ok(token)
}

///|
pub fn adopt_reconciled_model_response(
  token : ModelResponseReconciliation,
  response : ModelResponse,
) -> Result[Unit, ModelExecutionIssue] {
  let prepared = token.prepared
  let state = prepared.owner.state
  guard !token.adopted &&
    prepared_model_current(prepared) &&
    state.progress.phase is DispatchSlot &&
    state.progress.slot == 0 &&
    state.dispatch_admission is Some(admission) &&
    state.response_reconciliations.get(token.slot) is Some(original) &&
    physical_equal(original, token) &&
    state.unknown_calls.contains(token.slot) &&
    prepared_model_call_at(prepared, token.slot) is Some(call) else {
    return Err(RequestIdentity)
  }
  match @publication_host.check_client_infer_dispatch_current(admission) {
    Err(issue) => return Err(Authorization(issue))
    Ok(_) => ()
  }
  if state.egress_admission is Some(egress) {
    match @publication_host.check_client_infer_egress_current(egress) {
      Err(issue) => return Err(Egress(issue))
      Ok(_) => ()
    }
  }
  state.attempts[token.slot] = {
    attempt: token.attempt,
    call,
    authority: token.authority,
    reservation: state.quantity_capacity.map(value => value.per_attempt),
    input_tokens: None,
    output_tokens: None,
    category: "result_unknown",
    failure: Some("result_unknown"),
    work: 0,
    response_cid: None,
    output_cid: None,
    response_issuer: None,
    evidence: None,
  }
  state.attempt_slots.push(token.slot)
  state.reconciled_responses[token.slot] = response
  state.unknown_calls.remove(token.slot)
  token.adopted = true
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
  state.attempts[state.progress.slot] = {
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
  state.attempt_slots.push(state.progress.slot)
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
    match model_outcome_at(execution.state, slot) {
      None | Some(UnresolvedUnknown) => true
      _ => false
    }
  })
}
