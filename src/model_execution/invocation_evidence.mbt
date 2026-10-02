///|
priv enum ModelEvidencePhase {
  ResponseWire(@admitted.WireEmitCursor, @encode.Writer)
  OutputWire(@admitted.WireEmitCursor, @encode.Writer)
  Seal
}

///|
// Response custody stays with the existing execution until its checked
// observation has been sealed. This is not a durable slot/cost/authority record.
priv struct ModelEvidencePreparation {
  request : ModelRequest
  response : ModelResponse
  key_cid : String
  checked : @admitted.CheckedValue
  mut response_cid : String?
  mut output_cid : String?
  mut phase : ModelEvidencePhase
}

///|
fn start_model_evidence(
  state : ModelState,
  request : ModelRequest,
  response : ModelResponse,
  key_cid : String,
  checked : @admitted.CheckedValue,
) -> Result[ModelEvidencePreparation, ModelExecutionIssue] {
  try {
    let bytes = Int64::min(state.limits.max_response_bytes, 2147483647L).to_int()
    let writer = @encode.hashing_writer(
      bytes,
      state.limits.value_limits.max_nodes,
      state.limits.value_limits.max_depth,
    )
    Ok({
      request,
      response,
      key_cid,
      checked,
      response_cid: None,
      output_cid: None,
      phase: ResponseWire(
        @admitted.start_wire_emit(response.value, writer),
        writer,
      ),
    })
  } catch {
    _ => Err(OutputValue)
  }
}

///|
fn advance_model_evidence(
  state : ModelState,
  value : ModelEvidencePreparation,
) -> Result[@publication.RunEvidenceValue?, ModelExecutionIssue] {
  try {
    match value.phase {
      ResponseWire(cursor, writer) => {
        if @admitted.advance_wire_emit(cursor) {
          value.response_cid = Some("sha256:" + @encode.finish_hash(writer))
          let bytes = Int64::min(state.limits.max_response_bytes, 2147483647L).to_int()
          let writer = @encode.hashing_writer(
            bytes,
            state.limits.value_limits.max_nodes,
            state.limits.value_limits.max_depth,
          )
          value.phase = OutputWire(
            @admitted.start_wire_emit(value.checked.value, writer),
            writer,
          )
        }
        Ok(None)
      }
      OutputWire(cursor, writer) => {
        if @admitted.advance_wire_emit(cursor) {
          value.output_cid = Some("sha256:" + @encode.finish_hash(writer))
          value.phase = Seal
        }
        Ok(None)
      }
      Seal =>
        seal_model_invocation_evidence(state, value).map(result => Some(result))
    }
  } catch {
    _ => Err(OutputValue)
  }
}

///|
fn seal_model_invocation_evidence(
  state : ModelState,
  value : ModelEvidencePreparation,
) -> Result[@publication.RunEvidenceValue, ModelExecutionIssue] {
  guard state.call_scope is Some(scope) &&
    value.response_cid is Some(response_cid) &&
    value.output_cid is Some(output_cid) else {
    return Err(OutputIdentity)
  }
  let request = value.request
  try {
    let writer = @encode.writer(16384, 1024, 16)
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("version", "actql-model-invocation-evidence/0.1"),
        (
          "model_task_contract_cid",
          @environment.model_task_identity(state.task).2,
        ),
        ("semantic_request_cid", request.fixed_request_cid),
        ("model_call_slot_cid", request.slot_cid),
        (
          "input_result_artifact_cid",
          @publication.run_evidence_value_identity(
            @publication_host.client_infer_call_scope_artifact(scope),
          ),
        ),
        ("input_row_identity_cid", value.key_cid),
        (
          "authored_model_selector",
          @environment.model_task_model_selector(state.task),
        ),
        ("provider_reported_model_id", value.response.provider_model),
        ("provider_request_id", value.response.provider_request_id),
        ("structured_response_artifact_cid", response_cid),
        ("validated_structured_output_cid", output_cid),
        ("finish_reason", "stop"),
        ("observed_at", value.response.observed_at),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.key(writer, "attempt")
    @encode.number_value(writer, 1)
    @encode.key(writer, "input_row_identity")
    if request.key.length() != 1 {
      @encode.begin_array(writer)
    }
    // Request preparation already bounds the complete scalar key preimage.
    // Ref transport/scope metadata is not logical row identity.
    for key in request.key {
      match key.value {
        @admitted.Reference(reference) =>
          @encode.string_value(
            writer,
            @admitted.reference_identity_cid(reference),
          )
        _ => @admitted.emit_checked_wire_value(key, writer)
      }
    }
    if request.key.length() != 1 {
      @encode.end_array(writer)
    }
    @encode.key(writer, "input_tokens")
    @encode.decimal_number_value(
      writer,
      value.response.input_tokens.to_string(),
    )
    @encode.key(writer, "output_tokens")
    @encode.decimal_number_value(
      writer,
      value.response.output_tokens.to_string(),
    )
    @encode.end_object(writer)
    @publication.seal_run_evidence_value(
      "model_invocation_evidence",
      @encode.finish(writer),
      16384,
      1024,
      16,
    ).map_err(issue => InvocationEvidence(issue))
  } catch {
    _ => Err(OutputIdentity)
  }
}

///|
fn cancel_model_evidence(value : ModelEvidencePreparation) -> Unit {
  match value.phase {
    ResponseWire(cursor, _) | OutputWire(cursor, _) =>
      @admitted.cancel_wire_emit(cursor)
    Seal => ()
  }
}

///|
fn accept_model_slot(
  state : ModelState,
  request : ModelRequest,
  response : ModelResponse,
  input_key_cid : String,
  checked : @admitted.CheckedValue,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  state.outcomes.push(Success(state.captures.length()))
  if state.attempts.get(state.next_slot) is Some(trace) {
    trace.category = "ok"
    trace.failure = None
    trace.work = state.work
    // These references are assigned by the existing bounded response issuer.
    if state.invocation_evidence.last() is Some(evidence) {
      trace.response_issuer = Some(
        @publication.run_evidence_value_identity(evidence),
      )
    }
  }
  state.responses.push(response.value)
  state.captures.push({
    slot: request.slot,
    slot_cid: request.slot_cid,
    input_key_cid,
    fixed_request_cid: request.fixed_request_cid,
    provider_id: @environment.model_task_connector(state.task),
    provider_model: response.provider_model,
    provider_request_id: response.provider_request_id,
    value: checked,
    input_tokens: response.input_tokens,
    output_tokens: response.output_tokens,
    observed_at: response.observed_at,
  })
  state.next_slot += 1
  state.phase = DispatchSlot
  if state.next_slot == @relation.prepared_infer_rows_count(state.rows) {
    complete_model_slots(state)
  } else {
    @bounded.Continue(1, 1)
  }
}

///|
/// Issued only by this successful execution's response-checking owner. A
/// matching slot CID or caller-authored capture bundle cannot supply it.
/// Persisted custody and policy/usage admission are separate requirements.
pub fn model_execution_invocation_evidence(
  execution : ModelExecution,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  if !execution.state.accepted || execution.state.reclaimed {
    None
  } else {
    match execution.state.outcomes.get(slot) {
      Some(Success(index)) => execution.state.invocation_evidence.get(index)
      _ => None
    }
  }
}

///|
pub fn model_execution_sealing_observation(execution : ModelExecution) -> Bool {
  !execution.state.reclaimed &&
  !@bounded.session_stopped(execution.session) &&
  execution.state.phase is PrepareEvidence(_)
}
