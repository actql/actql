///|
/// Restore a saved observation, never a model request. The authenticated Store
/// read establishes private physical custody; this owner separately checks
/// the records against fresh input, request, task, key and typed result.
pub fn start_restored_model_capture_replay(
  rows : @relation.PreparedInferRows,
  scope : @publication_host.ClientInferCallScope,
  capture : @publication.ModelCaptureBundleRead,
  fixed_request_cid : String,
  limits : ModelExecutionLimits,
) -> Result[ModelExecution, ModelExecutionIssue] {
  if @publication.model_capture_bundle_count(capture) !=
    @relation.prepared_infer_rows_count(rows) {
    return Err(OutputIdentity)
  }
  guard @publication.retain_model_capture_bundle_read(capture) is Some(retained) else {
    return Err(OutputIdentity)
  }
  let started = start_model_owned(
    rows,
    Restored(retained),
    fixed_request_cid,
    limits,
    Some(scope),
  )
  if started is Err(_) {
    @publication.release_model_capture_bundle_read(retained) |> ignore
  }
  started
}

///|
fn begin_restored_model_response(
  state : ModelState,
  capture : @publication.ModelCaptureBundleRead,
  prepared : PreparedModelRequest,
  record_index? : Int = state.next_slot,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  let record = match
    @publication.model_capture_bundle_record(capture, record_index) {
    Ok(value) => value
    Err(issue) => return @bounded.Failed(InvocationEvidence(issue), 1, 1)
  }
  guard state.call_scope is Some(scope) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let request = prepared.request
  for
    (name, expected) in [
      (
        "model_task_contract_cid",
        @environment.model_task_identity(state.task).2,
      ),
      ("model_call_slot_cid", request.slot_cid),
      ("semantic_request_cid", request.fixed_request_cid),
      ("input_row_identity_cid", prepared.key_cid),
      (
        "input_result_artifact_cid",
        @publication.run_evidence_value_identity(
          @publication_host.client_infer_call_scope_artifact(scope),
        ),
      ),
      (
        "authored_model_selector",
        @environment.model_task_model_selector(state.task),
      ),
    ] {
    if @publication.model_capture_record_text(record, name) != Some(expected) {
      return @bounded.Failed(OutputIdentity, 1, 1)
    }
  }
  guard @admitted.start_canonical_conversion(
      @publication.model_capture_record_response(record),
      state.limits.value_limits,
      contract=Some(@environment.model_task_output(state.task)),
      wire=true,
    )
    is Some(cursor) else {
    return @bounded.Failed(OutputValue, 1, 1)
  }
  state.restored_evidence = Some(
    @publication.model_capture_record_evidence(record),
  )
  state.phase = RestoreResponse(prepared, record, cursor)
  @bounded.Continue(1, 1)
}

///|
fn advance_restored_model_response(
  state : ModelState,
  prepared : PreparedModelRequest,
  record : @publication.ModelCaptureRecordRead,
  cursor : @admitted.CanonicalConversion,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  match @admitted.advance_canonical_conversion(cursor) {
    CanonicalConversionContinue => @bounded.Continue(1, 1)
    CanonicalConversionFailed => @bounded.Failed(OutputValue, 1, 1)
    CanonicalConversionComplete(value) => {
      guard @publication.model_capture_record_text(
          record, "provider_reported_model_id",
        )
        is Some(provider_model) &&
        @publication.model_capture_record_text(record, "provider_request_id")
        is Some(provider_request_id) &&
        @publication.model_capture_record_text(record, "observed_at")
        is Some(observed_at) &&
        @publication.model_capture_record_tokens(record)
        is Some((input_tokens, output_tokens)) else {
        return @bounded.Failed(OutputIdentity, 1, 1)
      }
      guard @admitted.start_recheck_runtime_value(
          value,
          @environment.model_task_output(state.task),
          state.limits.value_limits,
        )
        is Some(checked) else {
        return @bounded.Failed(OutputValue, 1, 1)
      }
      let response : ModelResponse = {
        value,
        provider_model,
        provider_request_id,
        observed_at,
        input_tokens,
        output_tokens,
      }
      state.phase = CheckResponse(
        prepared.request,
        response,
        prepared.key_cid,
        checked,
      )
      // The immutable completed value is now the shared response phase's;
      // release the conversion's private construction references.
      @admitted.cancel_canonical_conversion(cursor)
      @bounded.Continue(1, 1)
    }
  }
}

///|
/// Diagnostic progress only. It cannot certify accepted replay or custody.
pub fn model_execution_restoring(execution : ModelExecution) -> Bool {
  !execution.state.reclaimed &&
  !@bounded.session_stopped(execution.session) &&
  execution.state.phase is RestoreResponse(_, _, _)
}
