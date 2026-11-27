///|
/// The original settled slot and its closed evidence inventory. The caller
/// borrows these originals for persistence; this record does not acknowledge it.
pub struct ModelCallSettlementOriginal {
  settlement : @model.ModelCallSettlement
  slot : Int
  count : Int
  scope_cid : String
  slot_cid : String
  attempt_cid : String
  call : @publication.RunEvidenceValue
  leaves : Array[@publication.RunEvidenceValue]
}

///|
pub(all) enum ModelCallSettlementOriginalIssue {
  ForeignOriginal
  Capture(@model.ModelExecutionIssue)
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Derive the slot, attempt and evidence from the same retained INFER.
/// Caller-side storage capacity must already cover the evidence writers.
/// The capture bundle is exported separately by the existing bounded cursor.
pub fn prepare_call_settlement_original(
  active : Execution,
  prepared : @model.ModelPreparedCallSet,
  scope : @publication.BoundModelInvocationScope,
) -> Result[ModelCallSettlementOriginal, ModelCallSettlementOriginalIssue] {
  guard active.run_binding is Some(run) &&
    active.model is Some(model) &&
    @model.prepared_model_matches(prepared, model) &&
    @model.prepared_model_scope(prepared) is Some(bound) &&
    physical_equal(bound, scope) &&
    call_settlement(active) is Some(settlement) &&
    @model.model_call_settlement_slot(settlement) is Some(slot) &&
    @model.prepared_model_call_count(prepared) is Some(count) &&
    @publication.model_invocation_scope_slot(scope, slot)
    is Some((slot_cid, _, _)) &&
    @model.prepared_model_call_at(prepared, slot) is Some(call) &&
    @publication.run_evidence_value_identity(call) == slot_cid else {
    return Err(ForeignOriginal)
  }
  let proof = match attempt_evidence(active, slot) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let attempt = @model.model_attempt_identity(proof)
  let accounting = @model.model_attempt_accounting(proof)
  let outcome = @model.model_attempt_outcome(proof)
  let authority = @model.model_attempt_authority(proof)
  match
    @publication.check_model_invocation_attempt(
      scope, slot, attempt, authority, 1L,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Evidence(issue))
  }
  let capture = match issued_slot_capture(active, slot) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let binding = match @publication.bind_model_slot_capture(call, capture) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  match
    @publication.bind_model_slot_attempt_evidence(
      binding,
      attempt,
      accounting,
      outcome,
      authority,
      run.compiled.admission,
      run.definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Evidence(issue))
  }
  let leaves = [attempt, accounting, outcome, authority, capture]
  guard @publication.bound_model_slot_capture_outcome(binding) is Some(result) else {
    return Err(ForeignOriginal)
  }
  if result == "ok" {
    guard invocation_evidence(active, slot) is Some(observation) else {
      return Err(ForeignOriginal)
    }
    match
      @publication.verify_model_slot_success_observation(binding, observation) {
      Ok(_) => leaves.push(observation)
      Err(issue) => return Err(Evidence(issue))
    }
  } else {
    match @publication.verify_model_slot_no_response_failure(binding, result) {
      Ok(_) => ()
      Err(issue) => return Err(Evidence(issue))
    }
  }
  match issued_attachment_admission(active, slot) {
    Ok(Some(value)) => leaves.push(value)
    Ok(None) => ()
    Err(issue) => return Err(Capture(issue))
  }
  Ok({
    settlement,
    slot,
    count,
    scope_cid: @publication.model_invocation_scope_cid(scope),
    slot_cid,
    attempt_cid: @publication.run_evidence_value_identity(attempt),
    call,
    leaves,
  })
}
