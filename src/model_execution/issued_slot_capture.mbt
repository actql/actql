///|
/// Issue only from this accepted physical execution. The adapter supplies no
/// attempt, accounting, classification or authority JSON and cannot substitute
/// another call's evidence roots. Store confirmation is a separate obligation.
pub fn model_execution_issued_slot_capture(
  execution : ModelExecution,
  slot : Int,
) -> Result[@publication.RunEvidenceValue, ModelExecutionIssue] {
  let state = execution.state
  guard state.accepted &&
    !state.reclaimed &&
    state.call_scope is Some(scope) &&
    state.requests.get(slot) is Some(prepared) &&
    state.outcomes.get(slot) is Some(adopted) &&
    state.attempts.get(slot) is Some(trace) else {
    return Err(OutputIdentity)
  }
  let proof = match model_execution_attempt_evidence(execution, slot) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let outcome = adopted_model_slot_outcome(adopted)
  if (outcome == "ok") != (trace.category == "ok") ||
    (outcome != "ok" && trace.category != "provider_failure") {
    return Err(OutputIdentity)
  }
  try {
    let writer = @encode.writer(16384, 256, 8)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-model-slot-capture/0.1"),
        ("slot_cid", prepared.request.slot_cid),
        ("model_task_cid", @environment.model_task_identity(state.task).2),
        ("fixed_request_cid", state.fixed_request_cid),
        (
          "input_artifact_cid",
          @publication.run_evidence_value_identity(
            @publication_host.client_infer_call_scope_artifact(scope),
          ),
        ),
        ("input_key_cid", prepared.key_cid),
        ("outcome", outcome),
        (
          "accounting_evidence_cid",
          @publication.run_evidence_value_identity(proof.accounting),
        ),
        (
          "authority_evidence_cid",
          @publication.run_evidence_value_identity(proof.authority),
        ),
        ("policy_cid", @environment.model_task_data_handling_cid(state.task)),
        (
          "outcome_evidence_cid",
          @publication.run_evidence_value_identity(proof.outcome),
        ),
        (
          "adopted_attempt_cid",
          @publication.run_evidence_value_identity(proof.attempt),
        ),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "ordered_attempt_cids")
    @encode.begin_array(writer)
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(proof.attempt),
    )
    @encode.end_array(writer)
    for
      (name, value) in [
        ("typed_value_artifact_cid", trace.output_cid),
        ("response_artifact_cid", trace.response_cid),
        ("response_issuer_evidence_cid", trace.response_issuer),
      ] {
      @encode.key(writer, name)
      match value {
        Some(value) => @encode.string_value(writer, value)
        None => @encode.null_value(writer)
      }
    }
    @encode.key(writer, "attachment_admission_cids")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.end_object(writer)
    @publication.seal_run_evidence_value(
      "model_slot_capture",
      @encode.finish(writer),
      16384,
      256,
      8,
    ).map_err(issue => InvocationEvidence(issue))
  } catch {
    _ => Err(OutputIdentity)
  }
}

///|
/// Verify imported leaves against the actual physical owner's issued bodies,
/// not just their schema, matching slot text or a caller-selected profile.
pub fn verify_model_execution_attempt_evidence(
  execution : ModelExecution,
  slot : Int,
  attempt : @publication.RunEvidenceValue,
  accounting : @publication.RunEvidenceValue,
  outcome : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
) -> Result[Unit, ModelExecutionIssue] {
  let expected = match model_execution_attempt_evidence(execution, slot) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for
    (received, owned) in [
      (attempt, expected.attempt),
      (accounting, expected.accounting),
      (outcome, expected.outcome),
      (authority, expected.authority),
    ] {
    if @publication.run_evidence_value_name(received) !=
      @publication.run_evidence_value_name(owned) ||
      @publication.run_evidence_value_identity(received) !=
      @publication.run_evidence_value_identity(owned) {
      return Err(OutputIdentity)
    }
  }
  Ok(())
}
