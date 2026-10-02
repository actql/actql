///|
priv struct ModelAttemptTrace {
  attempt : @publication.RunEvidenceValue
  call : @publication.RunEvidenceValue
  authority : @publication.RunEvidenceValue
  mut input_tokens : Int64?
  mut output_tokens : Int64?
  mut category : String
  mut failure : String?
  mut work : Int
  mut response_cid : String?
  mut output_cid : String?
  mut response_issuer : String?
  mut evidence : ModelAttemptEvidence?
}

///|
/// Issued from the physical owner's trace. Schema admission of a body alone
/// cannot construct this handle or supply proof of a dispatched attempt.
pub struct ModelAttemptEvidence {
  attempt : @publication.RunEvidenceValue
  accounting : @publication.RunEvidenceValue
  outcome : @publication.RunEvidenceValue
  authority : @publication.RunEvidenceValue
}

///|
fn start_model_attempt(
  state : ModelState,
  admission : @publication_host.ClientInferDispatchAdmission,
  call : @publication.RunEvidenceValue,
  request : ModelRequest,
) -> Result[ModelAttemptTrace, ModelExecutionIssue] {
  if @publication_host.check_client_infer_dispatch_current(admission)
    is Err(issue) {
    return Err(Authorization(issue))
  }
  let authority = @publication_host.client_infer_dispatch_authority(admission)
  try {
    let writer = @encode.writer(16384, 256, 8)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-model-call-attempt/0.1"),
        ("slot_cid", request.slot_cid),
        (
          "run_definition_cid",
          @publication_host.client_infer_dispatch_run_cid(admission),
        ),
        ("model_task_cid", @environment.model_task_identity(state.task).2),
        ("fixed_request_cid", request.fixed_request_cid),
        (
          "authority_evidence_cid",
          @publication.run_evidence_value_identity(authority),
        ),
        ("provider_id", @environment.model_task_connector(state.task)),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "attempt")
    // This provider has no retry path; another Run has a distinct definition.
    @encode.number_value(writer, 1)
    @encode.end_object(writer)
    let attempt = match
      @publication.seal_run_evidence_value(
        "model_call_attempt",
        @encode.finish(writer),
        16384,
        256,
        8,
      ) {
      Ok(value) => value
      Err(issue) => return Err(InvocationEvidence(issue))
    }
    Ok({
      attempt,
      call,
      authority,
      input_tokens: None,
      output_tokens: None,
      category: "result_unknown",
      failure: Some("result_unknown"),
      work: 0,
      response_cid: None,
      output_cid: None,
      response_issuer: None,
      evidence: None,
    })
  } catch {
    _ => Err(OutputIdentity)
  }
}

///|
fn finish_model_attempt_failure(
  state : ModelState,
  issue : ModelExecutionIssue,
) -> Unit {
  guard state.attempts.get(state.next_slot) is Some(trace) else { return }
  trace.work = state.work
  match issue {
    OutputIdentity => {
      trace.category = "contract_violation"
      trace.failure = Some("output_identity")
    }
    OutputValue => {
      trace.category = "contract_violation"
      trace.failure = Some("output_value")
    }
    _ => ()
  }
}

///|
fn finish_model_attempt_stop(
  state : ModelState,
  reason : @bounded.StopReason,
) -> Unit {
  guard state.attempts.get(state.next_slot) is Some(trace) else { return }
  trace.work = state.work
  trace.category = "cancelled"
  trace.failure = Some(
    match reason {
      @bounded.Cancelled => "cancelled"
      @bounded.Deadline => "deadline"
    },
  )
}

///|
fn emit_optional_usage(
  writer : @encode.Writer,
  value : Int64?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(value) => @encode.decimal_number_value(writer, value.to_string())
    None => @encode.null_value(writer)
  }
}

///|
/// A fixed-size proof per physically entered attempt. Unknown token, cost and
/// duration observations remain NULL, never fictitious zero measurements.
pub fn model_execution_attempt_evidence(
  execution : ModelExecution,
  slot : Int,
) -> Result[ModelAttemptEvidence, ModelExecutionIssue] {
  guard @bounded.session_stopped(execution.session) &&
    execution.state.attempts.get(slot) is Some(trace) else {
    return Err(OutputIdentity)
  }
  if trace.evidence is Some(evidence) {
    return Ok(evidence)
  }
  // Detached immutable proof metadata may be read after cleanup, but new
  // proof encoding cannot consume a reservation already returned to capacity.
  if execution.state.reclaimed {
    return Err(OutputIdentity)
  }
  try {
    let attempt_cid = @publication.run_evidence_value_identity(trace.attempt)
    let slot_cid = @publication.run_evidence_value_identity(trace.call)
    let writer = @encode.writer(16384, 256, 8)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-model-attempt-accounting/0.1"),
        ("attempt_cid", attempt_cid),
        ("slot_cid", slot_cid),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "cumulative_work")
    @encode.number_value(writer, trace.work.to_double())
    @encode.key(writer, "uncertain_wire_bytes")
    @encode.decimal_number_value(
      writer,
      (execution.state.limits.max_request_bytes +
      execution.state.limits.max_response_bytes).to_string(),
    )
    for
      (name, value) in [
        ("input_tokens", trace.input_tokens),
        ("output_tokens", trace.output_tokens),
        ("cost_units", None),
        ("duration_ms", None),
      ] {
      @encode.key(writer, name)
      emit_optional_usage(writer, value)
    }
    @encode.end_object(writer)
    let accounting = match
      @publication.seal_run_evidence_value(
        "model_attempt_accounting",
        @encode.finish(writer),
        16384,
        256,
        8,
      ) {
      Ok(value) => value
      Err(issue) => return Err(InvocationEvidence(issue))
    }
    let writer = @encode.writer(16384, 256, 8)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-model-attempt-outcome/0.1"),
        ("attempt_cid", attempt_cid),
        ("slot_cid", slot_cid),
        ("category", trace.category),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "failure")
    match trace.failure {
      Some(value) => @encode.string_value(writer, value)
      None => @encode.null_value(writer)
    }
    @encode.end_object(writer)
    let outcome = match
      @publication.seal_run_evidence_value(
        "model_attempt_outcome",
        @encode.finish(writer),
        16384,
        256,
        8,
      ) {
      Ok(value) => value
      Err(issue) => return Err(InvocationEvidence(issue))
    }
    let evidence : ModelAttemptEvidence = {
      attempt: trace.attempt,
      accounting,
      outcome,
      authority: trace.authority,
    }
    trace.evidence = Some(evidence)
    Ok(evidence)
  } catch {
    _ => Err(OutputIdentity)
  }
}

///|
pub fn model_attempt_identity(
  value : ModelAttemptEvidence,
) -> @publication.RunEvidenceValue {
  value.attempt
}

///|
pub fn model_attempt_accounting(
  value : ModelAttemptEvidence,
) -> @publication.RunEvidenceValue {
  value.accounting
}

///|
pub fn model_attempt_outcome(
  value : ModelAttemptEvidence,
) -> @publication.RunEvidenceValue {
  value.outcome
}

///|
pub fn model_attempt_authority(
  value : ModelAttemptEvidence,
) -> @publication.RunEvidenceValue {
  value.authority
}
