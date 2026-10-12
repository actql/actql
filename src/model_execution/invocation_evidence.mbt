///|
priv enum ModelEvidencePhase {
  ResponseWire(@admitted.WireEmitCursor, @encode.Writer)
  OutputWire(@admitted.WireEmitCursor, @encode.Writer)
  Metadata(@canonical.CanonicalEmit, @encode.Writer)
  Seal
}

///|
// Response custody stays with the existing execution until its checked
// observation has been sealed. This is not a durable slot/cost/authority record.
priv struct ModelEvidencePreparation {
  request : ModelRequest
  response : ModelObservedResponse
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
  response : ModelObservedResponse,
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
          @admitted.cancel_wire_emit(cursor)
          @encode.cancel_writer(writer)
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
          @admitted.cancel_wire_emit(cursor)
          @encode.cancel_writer(writer)
          value.phase = Seal
        }
        Ok(None)
      }
      Metadata(cursor, writer) => {
        if !@canonical.advance_emit(cursor) {
          return Ok(None)
        }
        @canonical.cancel_emit(cursor)
        @encode.end_object(writer)
        let wire = finish_model_invocation_wire(writer)
        value.phase = Seal
        finish_model_invocation_evidence(state, wire).map(result => Some(result))
      }
      Seal => seal_model_invocation_evidence(state, value)
    }
  } catch {
    _ => Err(OutputValue)
  }
}

///|
fn seal_model_invocation_evidence(
  state : ModelState,
  value : ModelEvidencePreparation,
) -> Result[@publication.RunEvidenceValue?, ModelExecutionIssue] {
  guard state.call_scope is Some(scope) &&
    value.response_cid is Some(response_cid) &&
    value.output_cid is Some(output_cid) else {
    return Err(OutputIdentity)
  }
  let request = value.request
  let observation = value.response.observation
  let historical = observation.origin == @publication.HistoricalAdmitted
  // Reported observations come from an admitted original saved record or this
  // execution's retained physical response. Store custody remains separate;
  // a provider-supplied profile CID cannot issue a response here.
  if !historical {
    let saved = state.restored_evidence is Some(original) &&
      @publication.model_invocation_evidence_version(original) ==
      Some("actql-model-invocation-evidence/0.2") &&
      observation.response_profile_cid is Some(_) &&
      observation.response_complete == Some(true)
    if !saved && !model_reported_response_owned(state, request, value.response) {
      return Err(OutputIdentity)
    }
  }
  try {
    let writer = @encode.writer(16384, 1024, 16)
    errdefer @encode.cancel_writer(writer)
    @encode.begin_object(writer)
    for
      (name, text) in [
        (
          "version",
          if historical {
            "actql-model-invocation-evidence/0.1"
          } else {
            "actql-model-invocation-evidence/0.2"
          },
        ),
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
        ("structured_response_artifact_cid", response_cid),
        ("validated_structured_output_cid", output_cid),
        ("observed_at", observation.observed_at),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    for
      (name, text) in [
        ("provider_reported_model_id", observation.provider_model),
        ("provider_request_id", observation.provider_request_id),
        (
          "finish_reason",
          if historical {
            observation.historical_finish_reason
          } else {
            observation.provider_finish_reason
          },
        ),
      ] {
      if historical && text is None {
        return Err(OutputIdentity)
      }
      @encode.key(writer, name)
      emit_model_optional_text(writer, text)
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
    emit_model_optional_tokens(writer, observation.input_tokens)
    @encode.key(writer, "output_tokens")
    emit_model_optional_tokens(writer, observation.output_tokens)
    if !historical {
      for
        (name, text) in [
          ("provider_reported_revision", observation.provider_revision),
          ("gateway_request_id", observation.gateway_request_id),
          ("response_profile_cid", observation.response_profile_cid),
          ("raw_response_artifact_cid", observation.raw_response_artifact_cid),
        ] {
        @encode.key(writer, name)
        emit_model_optional_text(writer, text)
      }
      @encode.key(writer, "response_complete")
      @encode.bool_value(writer, true)
      @encode.key(writer, "provider_metadata")
      match observation.provider_metadata {
        Some(metadata) => {
          value.phase = Metadata(
            @canonical.start_emit(metadata, writer),
            writer,
          )
          return Ok(None)
        }
        None => @encode.null_value(writer)
      }
    }
    @encode.end_object(writer)
    let wire = finish_model_invocation_wire(writer)
    finish_model_invocation_evidence(state, wire).map(result => Some(result))
  } catch {
    _ => Err(OutputIdentity)
  }
}

///|
fn finish_model_invocation_evidence(
  state : ModelState,
  wire : String,
) -> Result[@publication.RunEvidenceValue, ModelExecutionIssue] {
  let reconstructed = match
    @publication.seal_run_evidence_value(
      "model_invocation_evidence", wire, 16384, 1024, 16,
    ) {
    Err(issue) => return Err(InvocationEvidence(issue))
    Ok(value) => value
  }
  if state.restored_evidence is Some(original) {
    match
      @publication.check_model_replayed_observation(original, reconstructed) {
      Err(issue) => return Err(InvocationEvidence(issue))
      Ok(_) => return Ok(original)
    }
  }
  Ok(reconstructed)
}

///|
// The completed wire remains available, but the text builder and its frames
// must not remain live while the strict source and canonical token are built.
fn finish_model_invocation_wire(
  writer : @encode.Writer,
) -> String raise @encode.EncodeFailure {
  errdefer @encode.cancel_writer(writer)
  let wire = @encode.finish(writer)
  @encode.cancel_writer(writer)
  wire
}

///|
fn cancel_model_evidence(value : ModelEvidencePreparation) -> Unit {
  match value.phase {
    ResponseWire(cursor, writer) | OutputWire(cursor, writer) => {
      @admitted.cancel_wire_emit(cursor)
      @encode.cancel_writer(writer)
    }
    Metadata(cursor, writer) => {
      @canonical.cancel_emit(cursor)
      @encode.cancel_writer(writer)
    }
    Seal => ()
  }
}

///|
fn accept_model_slot(
  state : ModelState,
  request : ModelRequest,
  response : ModelObservedResponse,
  input_key_cid : String,
  checked : @admitted.CheckedValue,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  state.observing_response = false
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
  let observation = response.observation
  state.captures.push({
    slot: request.slot,
    slot_cid: request.slot_cid,
    input_key_cid,
    fixed_request_cid: request.fixed_request_cid,
    provider_id: @environment.model_task_connector(state.task),
    provider_model: observation.provider_model,
    provider_request_id: observation.provider_request_id,
    value: checked,
    input_tokens: observation.input_tokens,
    output_tokens: observation.output_tokens,
    observed_at: observation.observed_at,
  })
  if state.durable_calls {
    state.settlement_pending = Some(state.next_slot)
  }
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
  if (
      !execution.state.accepted &&
      !(execution.state.durable_calls && slot < execution.state.next_slot)
    ) ||
    execution.state.reclaimed {
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
