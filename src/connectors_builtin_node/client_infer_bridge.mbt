///|
/// Start one owned physical operation only after the Host admits model access.
/// Preparation, dispatch and output share the original checked Program owner.
#export_name("clientProgramStartInferExecution")
pub fn client_program_start_infer_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  fixed_request_cid : String,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start(
    prepared,
    step,
    registry,
    values,
    provider,
    fixed_request_cid,
    @infer_host.standard_limits(),
  )
}

///|
#export_name("clientProgramAdvanceInferExecution")
pub fn client_program_advance_infer_execution(
  active : @infer_host.Execution,
  quantum : Int,
) -> Result[@infer_host.Poll, @infer_host.Issue] {
  @infer_host.advance(active, quantum)
}

///|
#export_name("clientProgramInferExecutionOutput")
pub fn client_program_infer_execution_output(
  value : @infer_host.Poll,
) -> @execution.CompletedOutput? {
  @infer_host.completed(value)
}

///|
#export_name("clientProgramInferExecutionHandoffPending")
pub fn client_program_infer_execution_handoff_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.handoff_pending(active)
}

///|
#export_name("clientProgramInferExecutionCapture")
pub fn client_program_infer_execution_capture(
  active : @infer_host.Execution,
) -> @model.ModelCaptureBundle? {
  @infer_host.capture(active)
}

///|
#export_name("clientProgramCancelInferExecution")
pub fn client_program_cancel_infer_execution(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.cancel(active)
}

///|
#export_name("clientProgramCleanupInferExecution")
pub fn client_program_cleanup_infer_execution(
  active : @infer_host.Execution,
) -> Result[Bool, @infer_host.Issue] {
  @infer_host.cleanup(active)
}

///|
#export_name("clientProgramAcquireInferOutput")
pub fn client_program_acquire_infer_output(
  active : @infer_host.Execution,
) -> @infer_host.OutputUse? {
  @infer_host.acquire_output(active)
}

///|
#export_name("clientProgramInferOutputUse")
pub fn client_program_infer_output_use(
  value : @infer_host.OutputUse,
) -> @execution.CompletedOutput? {
  @infer_host.output(value)
}

///|
#export_name("clientProgramReleaseInferOutput")
pub fn client_program_release_infer_output(
  value : @infer_host.OutputUse,
) -> Bool {
  @infer_host.release_output(value)
}

///|
/// Admit compiler dependency material under the normal prepared Program.
#export_name("clientProgramReadInferModelExecution")
pub fn client_program_read_infer_model_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  body : String,
  expected_cid : String,
) -> Result[
  @check_environment.ModelExecutionContract,
  @publication_host.ClientInferPlanGraphIssue,
] {
  @publication_host.read_prepared_client_infer_model_execution(
    prepared,
    step,
    @utf8.encode(body),
    expected_cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10000, },
    1000000,
  )
}

///|
/// The graph binds references but does not authorize a Run or a model call.
#export_name("clientProgramInferPlanGraph")
pub fn client_program_infer_plan_graph(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  execution : @check_environment.ModelExecutionContract,
  limits_cid : String,
  egress_cid : String,
) -> Result[
  @publication_host.ClientInferPlanGraph,
  @publication_host.ClientInferPlanGraphIssue,
] {
  @publication_host.issue_prepared_client_infer_plan_graph(
    prepared,
    step,
    execution,
    limits_cid,
    egress_cid,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramInferPlanGraphWire")
pub fn client_program_infer_plan_graph_wire(
  value : @publication_host.ClientInferPlanGraph,
) -> String {
  @publication_host.client_infer_plan_graph_wire(value)
}

///|
#export_name("clientProgramInferPlanRequestWire")
pub fn client_program_infer_plan_request_wire(
  value : @publication_host.ClientInferPlanGraph,
) -> String {
  @publication_host.client_infer_plan_graph_request_wire(value)
}

///|
/// The acquisition compiler uses the same checked pure prefix as execution.
/// This fragment alone is not a runnable Infer Plan.
#export_name("clientProgramInferPrefixFragment")
pub fn client_program_infer_prefix_fragment(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
) -> Result[
  @publication_host.ClientTaskFragmentNode,
  @publication_host.ClientTaskFragmentIssue,
] {
  @publication_host.issue_prepared_client_infer_prefix_fragment(
    prepared,
    task,
    step,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  )
}

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
#export_name("clientProgramCancelModelExecution")
pub fn client_program_cancel_model_execution(
  active : @model.ModelExecution,
) -> Bool {
  @model.request_model_cancel(active)
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

///|
#export_name("clientProgramStartModelOutput")
pub fn client_program_start_model_output(
  input : @client_local_host.ClientInferInputExecution,
  rows : @execution.PreparedInferRows,
  model : @model.ModelExecution,
) -> Result[@model.ModelOutputPreparation, @model.ModelExecutionIssue] {
  guard @client_local_host.client_infer_completion_preparation(input, rows)
    is Some(completion) else {
    return Err(@model.OutputIdentity)
  }
  @model.start_model_output_preparation(
    model,
    completion,
    100,
    {
      max_nodes: 20000,
      max_text_bytes: 500000,
      max_depth: 100,
      max_work: 20000000,
    },
    20000000,
    10000,
  )
}

///|
#export_name("clientProgramAdvanceModelOutput")
pub fn client_program_advance_model_output(
  value : @model.ModelOutputPreparation,
  quantum : Int,
) -> Result[@execution.AdmittedOutputPoll, @model.ModelExecutionIssue] {
  @model.advance_model_output_preparation(value, quantum)
}

///|
#export_name("clientProgramCompleteModelOutput")
pub fn client_program_complete_model_output(
  value : @model.ModelOutputPreparation,
) -> Result[@execution.CompletedOutput, @model.ModelExecutionIssue] {
  @model.complete_model_output(value)
}

///|
#export_name("clientProgramCancelModelOutput")
pub fn client_program_cancel_model_output(
  value : @model.ModelOutputPreparation,
) -> Bool {
  @model.cancel_model_output_preparation(value)
}

///|
#export_name("clientProgramCleanupModelOutput")
pub fn client_program_cleanup_model_output(
  value : @model.ModelOutputPreparation,
) -> Result[Bool, @model.ModelExecutionIssue] {
  @model.cleanup_model_output_preparation(value)
}

///|
/// Select the existing Result transform under the original Program owner.
/// This is an export, not Run acceptance or a committed Named Result index.
#export_name("clientProgramInferResultExportBegin")
pub fn client_program_infer_result_export_begin(
  prepared : @publication_host.PreparedClientProgram,
  result : Int,
  output : @execution.CompletedOutput,
) -> Result[
  @publication_host.ClientResultTransformationPreparation,
  @publication_host.ClientResultTransformationIssue,
] {
  let selection = match
    @publication_host.prepare_client_result_transformation(
      prepared, result, 500000, 20000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire : @execution.RowWireLimits = {
    max_columns: 256,
    max_order_work: 20000000,
    max_bytes: 500000,
    max_nodes: 20000,
    max_depth: 100,
  }
  @publication_host.start_client_result_transformation(selection, output, {
    max_result_fields: 256,
    max_result_mapping_work: 20000000,
    max_result_order_work: 20000000,
    max_result_workspace_entries: 10000,
    max_rows: 100,
    values: {
      max_nodes: 20000,
      max_text_bytes: 500000,
      max_depth: 100,
      max_work: 20000000,
    },
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: 256,
      max_bytes: 500000,
      max_nodes: 20000,
      max_depth: 100,
    },
    max_batch_bytes: 500000,
  })
}

///|
#export_name("clientProgramInferResultExportAdvance")
pub fn client_program_infer_result_export_advance(
  value : @publication_host.ClientResultTransformationPreparation,
  quantum : Int,
) -> Result[(Bool, Int), @publication_host.ClientResultTransformationIssue] {
  value.advance(quantum)
}

///|
#export_name("clientProgramInferResultExportFinish")
pub fn client_program_infer_result_export_finish(
  value : @publication_host.ClientResultTransformationPreparation,
) -> Result[
  @publication_host.PublicationOutputExport,
  @publication_host.ClientResultTransformationIssue,
] {
  value.finish()
}

///|
#export_name("clientProgramInferResultExportNext")
pub fn client_program_infer_result_export_next(
  value : @publication_host.PublicationOutputExport,
) -> Result[String?, @publication_host.PublicationOutputExportIssue] {
  value.next()
}

///|
#export_name("clientProgramInferResultExportSeal")
pub fn client_program_infer_result_export_seal(
  value : @publication_host.PublicationOutputExport,
) -> Result[String, @publication_host.PublicationOutputExportIssue] {
  value.finish()
}

///|
#export_name("clientProgramInferResultExportClose")
pub fn client_program_infer_result_export_close(
  value : @publication_host.PublicationOutputExport,
) -> Unit {
  value.cancel()
}
