///|
/// Begin normal checked input execution, not a capture assembled by a caller.
#export_name("clientProgramStartInferInput")
pub fn client_program_start_infer_input(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  step : Int,
) -> @client_local_host.ClientInferInputExecution? {
  let values : @execution.ValueLimits = {
    max_nodes: 20000,
    max_depth: 100,
    max_text_bytes: 500000,
    max_work: 20000000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: values.max_work,
    max_frames: 100,
  }
  match
    @client_local_host.start_client_infer_input(
      prepared,
      0,
      step,
      registry_body,
      values_body,
      execution,
      {
        max_work: values.max_work,
        max_bytes: values.max_text_bytes,
        max_nodes: values.max_nodes,
        max_depth: values.max_depth,
      },
      {
        max_items: 100,
        max_work: values.max_work,
        max_frames: 100,
        max_workspace_slots: 10000,
        values: {
          max_nodes: values.max_nodes,
          max_depth: values.max_depth,
          max_text_bytes: values.max_text_bytes,
        },
        logical: {
          max_input_rows: 100L,
          max_value_bytes: 10000L,
          max_live_value_bytes: 100000L,
          max_work: values.max_work.to_int64(),
        },
      },
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientProgramAdvanceInferInput")
pub fn client_program_advance_infer_input(
  active : @client_local_host.ClientInferInputExecution,
  quantum : Int,
) -> Result[
  @client_local_host.ClientInferInputPoll,
  @client_local_host.ClientInferInputIssue,
] {
  @client_local_host.advance_client_infer_input(active, quantum)
}

///|
#export_name("clientProgramInferInputRows")
pub fn client_program_infer_input_rows(
  poll : @client_local_host.ClientInferInputPoll,
) -> @execution.PreparedInferRows? {
  match poll {
    @client_local_host.Complete(rows, ..) => Some(rows)
    _ => None
  }
}

///|
#export_name("clientProgramCancelInferInput")
pub fn client_program_cancel_infer_input(
  active : @client_local_host.ClientInferInputExecution,
) -> Bool {
  @client_local_host.cancel_client_infer_input(active)
}

///|
#export_name("clientProgramCleanupInferInput")
pub fn client_program_cleanup_infer_input(
  active : @client_local_host.ClientInferInputExecution,
) -> Result[Bool, @client_local_host.ClientInferInputIssue] {
  @client_local_host.cleanup_client_infer_input(active)
}

///|
/// Trusted Host registration. A returned response is admitted again against
/// the installed ModelTask; the Program cannot choose the callback.
#export_name("clientProgramInstallModelProvider")
pub fn client_program_install_model_provider(
  provider_id : String,
  invoke : (@model.ModelRequest) -> @model.ModelResponse?,
) -> @model.ModelProvider? {
  match
    @model.install_model_provider(provider_id, request => {
      match invoke(request) {
        Some(response) => Ok(response)
        None => Err(@model.ProviderError)
      }
    }) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientProgramModelRequestInput")
pub fn client_program_model_request_input(
  request : @model.ModelRequest,
  role : String,
) -> String? {
  for (name, value) in request.inputs {
    if role != name {
      continue
    }
    let writer = @encode.writer(65536, 10000, 64) catch { _ => return None }
    @admitted.emit_checked_wire_value(value, writer) catch {
      _ => return None
    }
    return Some(@encode.finish(writer)) catch { _ => None }
  }
  None
}

///|
/// Physical response decoding is bounded and task-typed. Provider metadata
/// is observation, not a contract or execution permit supplied by a Program.
#export_name("clientProgramModelResponse")
pub fn client_program_model_response(
  request : @model.ModelRequest,
  value_body : String,
  provider_model : String,
  provider_request_id : String,
  input_tokens : Int64,
  output_tokens : Int64,
  observed_at : String,
) -> @model.ModelResponse? {
  let source = match
    @source.parse_json(value_body, {
      max_input_bytes: 65536,
      max_nodes: 10000,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 10000,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let checked = match
    @admitted.admit(
      @check_environment.model_task_output(request.task),
      cursor,
      { max_nodes: 10000, max_depth: 64, max_text_bytes: 65536, },
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  Some({
    value: checked.value,
    provider_model,
    provider_request_id,
    input_tokens,
    output_tokens,
    observed_at,
  })
}

///|
#export_name("clientProgramStartModelExecution")
pub fn client_program_start_model_execution(
  rows : @execution.PreparedInferRows,
  provider : @model.ModelProvider,
  fixed_request_cid : String,
) -> Result[@model.ModelExecution, @model.ModelExecutionIssue] {
  @model.start_model_execution(rows, provider, fixed_request_cid, {
    max_items: 100,
    max_work: 10000,
    max_request_bytes: 65536L,
    max_response_bytes: 65536L,
    value_limits: { max_nodes: 10000, max_depth: 64, max_text_bytes: 65536, },
    ledger: {
      planning_work: 10000,
      attempts: 100,
      holdings: 100,
      transfer_bytes: 13107200L,
      retained_bytes: 6553600L,
      execution_bytes: 6553600L,
    },
  })
}

///|
#export_name("clientProgramAdvanceModelExecution")
pub fn client_program_advance_model_execution(
  active : @model.ModelExecution,
  quantum : Int,
) -> Result[@model.ModelObservation, @model.ModelExecutionIssue] {
  @model.advance_model_execution(active, quantum)
}

///|
#export_name("clientProgramModelCapture")
pub fn client_program_model_capture(
  poll : @model.ModelObservation,
) -> @model.ModelCaptureBundle? {
  match poll {
    @model.Completed(bundle, _, _) => Some(bundle)
    _ => None
  }
}

///|
#export_name("clientProgramModelCaptureJson")
pub fn client_program_model_capture_json(
  bundle : @model.ModelCaptureBundle,
) -> String? {
  @model.model_capture_bundle_json(bundle, 100000, 10000, 64)
}

///|
#export_name("clientProgramCleanupModelExecution")
pub fn client_program_cleanup_model_execution(
  active : @model.ModelExecution,
) -> Result[Bool, @model.ModelExecutionIssue] {
  @model.cleanup_model_execution(active)
}

///|
#export_name("clientProgramReplayModelCapture")
pub fn client_program_replay_model_capture(
  rows : @execution.PreparedInferRows,
  fixed_request_cid : String,
  bundle : @model.ModelCaptureBundle,
) -> Bool {
  @model.replay_model_capture_rows(rows, fixed_request_cid, bundle) is Ok(_)
}
