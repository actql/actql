///|
/// Compile the retained checked barrier through the existing task Run owner.
/// Compilation does not grant model egress or attest to captured execution.
#export_name("clientProgramCompileLocalInfer")
pub fn client_program_compile_local_infer(
  prepared : @publication_host.PreparedClientProgram,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientProgramTaskCompilationBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_infer_compilation(
    prepared, graph, manifests, 1000, 10000, 1000000, 100000, 100,
  ).map_err(issue => Compilation(issue))
}

///|
/// The installed Host retains the checked barrier and derives call identity
/// from the exact completed input before the first physical model dispatch.
#export_name("clientProgramStartScopedInferExecution")
pub fn client_program_start_scoped_infer_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start(
    prepared,
    step,
    registry,
    values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(graph),
    @infer_host.standard_limits(),
    plan=Some(graph),
  )
}

///|
/// Replay has no physical provider and prepares the normal input again.
#export_name("clientProgramStartInferReplay")
pub fn client_program_start_infer_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  capture : @model.VerifiedModelCapture,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_replay(
    prepared,
    step,
    registry,
    values,
    capture,
    @infer_host.standard_limits(),
    graph,
  )
}

///|
#export_name("clientProgramAcquireInferCapture")
pub fn client_program_acquire_infer_capture(
  active : @infer_host.Execution,
) -> @model.VerifiedModelCapture? {
  @infer_host.acquire_capture(active)
}

///|
/// Existing bounded all-slot verification. External evidence and Store
/// confirmation remain the installing capture owner's responsibilities.
#export_name("clientProgramStartInferObservationVerification")
pub fn client_program_start_infer_observation_verification(
  capture : @model.VerifiedModelCapture,
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
  max_slots : Int,
  max_slot_wire_units : Int,
  max_work : Int,
) -> Result[@model.ModelObservationVerification, @model.ModelExecutionIssue] {
  @model.start_model_observation_verification(capture, observation, records, {
    max_slots,
    max_slot_wire_units,
    max_work,
  })
}

///|
#export_name("clientProgramAdvanceInferObservationVerification")
pub fn client_program_advance_infer_observation_verification(
  active : @model.ModelObservationVerification,
  quantum : Int,
) -> Result[(Bool, Int64), @model.ModelExecutionIssue] {
  @model.advance_model_observation_verification(active, quantum)
}

///|
#export_name("clientProgramCancelInferObservationVerification")
pub fn client_program_cancel_infer_observation_verification(
  active : @model.ModelObservationVerification,
) -> Bool {
  @model.cancel_model_observation_verification(active)
}

///|
#export_name("clientProgramCleanupInferObservationVerification")
pub fn client_program_cleanup_infer_observation_verification(
  active : @model.ModelObservationVerification,
) -> Result[Bool, @model.ModelExecutionIssue] {
  @model.cleanup_model_observation_verification(active)
}

///|
/// Bind to the admitted compiled owner without preparing or compiling again.
/// This retains output custody, not authority to commit a public Result.
#export_name("clientProgramBindInferRun")
pub fn client_program_bind_infer_run(
  active : @infer_host.Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, @infer_host.InvocationBindingIssue] {
  @infer_host.bind_run(active, compiled, definition)
}

///|
#export_name("clientProgramBindInferInvocation")
pub fn client_program_bind_infer_invocation(
  active : @infer_host.Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  verified : @model.ModelObservationVerification,
  invocation : @publication.PublicationContract,
  data_policy_cid : String,
) -> Result[@infer_host.InvocationBinding, @infer_host.InvocationBindingIssue] {
  @infer_host.bind_invocation(
    active, compiled, definition, verified, invocation, data_policy_cid,
  )
}

///|
#export_name("clientProgramInferInvocationBindingOutput")
pub fn client_program_infer_invocation_binding_output(
  binding : @infer_host.InvocationBinding,
) -> @execution.CompletedOutput? {
  @infer_host.invocation_binding_output(binding)
}

///|
#export_name("clientProgramInferInvocationBindingObservation")
pub fn client_program_infer_invocation_binding_observation(
  binding : @infer_host.InvocationBinding,
) -> @publication.RunEvidenceValue? {
  @infer_host.invocation_binding_observation(binding)
}

///|
#export_name("clientProgramInferInvocationBindingInvocation")
pub fn client_program_infer_invocation_binding_invocation(
  binding : @infer_host.InvocationBinding,
) -> @publication.PublicationContract? {
  @infer_host.invocation_binding_invocation(binding)
}

///|
#export_name("clientProgramReleaseInferInvocationBinding")
pub fn client_program_release_infer_invocation_binding(
  binding : @infer_host.InvocationBinding,
) -> Bool {
  @infer_host.release_invocation_binding(binding)
}

///|
#export_name("clientProgramAcquireInferOutcomes")
pub fn client_program_acquire_infer_outcomes(
  active : @infer_host.Execution,
) -> @model.ModelOutcomeRead? {
  @infer_host.acquire_outcomes(active)
}

///|
#export_name("clientProgramInferOutcomesAccepted")
pub fn client_program_infer_outcomes_accepted(
  read : @model.ModelOutcomeRead,
) -> Bool {
  @model.model_outcomes_accepted(read)
}

///|
#export_name("clientProgramInferOutcomesCount")
pub fn client_program_infer_outcomes_count(
  read : @model.ModelOutcomeRead,
) -> Int? {
  @model.model_outcomes_count(read)
}

///|
#export_name("clientProgramInferOutcomesCall")
pub fn client_program_infer_outcomes_call(
  read : @model.ModelOutcomeRead,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  @model.model_outcomes_call_at(read, slot)
}

///|
#export_name("clientProgramInferOutcomesOutcome")
pub fn client_program_infer_outcomes_outcome(
  read : @model.ModelOutcomeRead,
  slot : Int,
) -> String? {
  @model.model_outcomes_outcome(read, slot)
}

///|
#export_name("clientProgramReleaseInferOutcomes")
pub fn client_program_release_infer_outcomes(
  read : @model.ModelOutcomeRead,
) -> Bool {
  @model.release_model_outcomes(read)
}

///|
/// The installed capture owner reads the actual accepted call inventory;
/// successful bundle records are not a substitute for this inventory.
#export_name("clientProgramInferCaptureCallCount")
pub fn client_program_infer_capture_call_count(
  capture : @model.VerifiedModelCapture,
) -> Int? {
  @model.verified_model_capture_call_count(capture)
}

///|
#export_name("clientProgramInferCaptureOutcome")
pub fn client_program_infer_capture_outcome(
  capture : @model.VerifiedModelCapture,
  slot : Int,
) -> String? {
  @model.verified_model_capture_outcome(capture, slot)
}

///|
#export_name("clientProgramInferCaptureCall")
pub fn client_program_infer_capture_call(
  capture : @model.VerifiedModelCapture,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  @model.verified_model_capture_call_at(capture, slot)
}

///|
/// This checks exact execution references, not external attempt, authority or
/// accounting evidence. Those remain the installing capture owner's duties.
#export_name("clientProgramBindInferSlotCapture")
pub fn client_program_bind_infer_slot_capture(
  capture : @model.VerifiedModelCapture,
  slot : Int,
  record : @publication.RunEvidenceValue,
) -> Result[@publication.BoundModelSlotCapture, @model.ModelExecutionIssue] {
  @model.bind_verified_model_slot_capture(capture, slot, record)
}

///|
/// The existing Store must authenticate and confirm the expected holding
/// before these bytes are offered to the common record reader. This bridge
/// performs protocol admission, not execution or publication authorization.
#export_name("clientProgramReadInferCaptureBundle")
pub fn client_program_read_infer_capture_bundle(
  wire : String,
  expected_cid : String,
) -> Result[
  @publication.ModelCaptureBundleRead,
  @publication.RunEvidenceValueIssue,
] {
  @publication.read_model_capture_bundle(wire, expected_cid, 100000, 20000, 100)
}

///|
#export_name("clientProgramStartRestoredInferReplay")
pub fn client_program_start_restored_infer_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  capture : @publication.ModelCaptureBundleRead,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_restored_replay(
    prepared,
    step,
    registry,
    values,
    capture,
    @infer_host.standard_limits(),
    graph,
  )
}

///|
#export_name("clientProgramReleaseInferCaptureBundle")
pub fn client_program_release_infer_capture_bundle(
  capture : @publication.ModelCaptureBundleRead,
) -> Bool {
  @publication.release_model_capture_bundle_read(capture)
}

///|
/// The capture owner authenticates and confirms each private holding first.
/// This is structural admission, not permission to publish or dispatch.
#export_name("clientProgramReadInferSlotReplay")
pub fn client_program_read_infer_slot_replay(
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
  bundle : @publication.ModelCaptureBundleRead,
  max_slots : Int,
  max_slot_wire_units : Int,
) -> Result[@model.ModelSlotReplayRead, @model.ModelExecutionIssue] {
  @model.read_model_slot_replay(
    observation, records, bundle, max_slots, max_slot_wire_units,
  )
}

///|
#export_name("clientProgramStartRestoredInferSlotReplay")
pub fn client_program_start_restored_infer_slot_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  read : @model.ModelSlotReplayRead,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_restored_slot_replay(
    prepared,
    step,
    registry,
    values,
    read,
    @infer_host.standard_limits(),
    graph,
  )
}

///|
#export_name("clientProgramReleaseInferSlotReplay")
pub fn client_program_release_infer_slot_replay(
  read : @model.ModelSlotReplayRead,
) -> Bool {
  @model.release_model_slot_replay(read)
}

///|
#export_name("clientProgramInferExecutionRestoring")
pub fn client_program_infer_execution_restoring(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.restoring(active)
}

///|
#export_name("clientProgramReleaseInferCapture")
pub fn client_program_release_infer_capture(
  capture : @model.VerifiedModelCapture,
) -> Bool {
  @model.release_verified_model_capture(capture)
}

///|
#export_name("clientProgramStartInferCaptureExport")
pub fn client_program_start_infer_capture_export(
  capture : @model.VerifiedModelCapture,
  max_bytes : Int,
  max_work : Int,
) -> Result[@model.ModelCaptureExport, @model.ModelExecutionIssue] {
  @model.start_model_capture_export(capture, {
    max_bytes,
    max_nodes: 20000,
    max_depth: 100,
    max_chunk_bytes: 65536,
    max_work,
  })
}

///|
#export_name("clientProgramAdvanceInferCaptureExport")
pub fn client_program_advance_infer_capture_export(
  active : @model.ModelCaptureExport,
  quantum : Int,
) -> Result[(Bool, String, Int64), @model.ModelExecutionIssue] {
  @model.advance_model_capture_export(active, quantum)
}

///|
#export_name("clientProgramInferCaptureExportIdentity")
pub fn client_program_infer_capture_export_identity(
  active : @model.ModelCaptureExport,
) -> String? {
  @model.model_capture_export_identity(active)
}

///|
#export_name("clientProgramCancelInferCaptureExport")
pub fn client_program_cancel_infer_capture_export(
  active : @model.ModelCaptureExport,
) -> Bool {
  @model.cancel_model_capture_export(active)
}

///|
#export_name("clientProgramInferCaptureExportResponsePending")
pub fn client_program_infer_capture_export_response_pending(
  active : @model.ModelCaptureExport,
) -> Bool {
  @model.model_capture_export_response_pending(active)
}

///|
#export_name("clientProgramCleanupInferCaptureExport")
pub fn client_program_cleanup_infer_capture_export(
  active : @model.ModelCaptureExport,
) -> Result[Bool, @model.ModelExecutionIssue] {
  @model.cleanup_model_capture_export(active)
}

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
#export_name("clientProgramInferExecutionStopped")
pub fn client_program_infer_execution_stopped(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.execution_stopped(active)
}

///|
#export_name("clientProgramInferExecutionPollKind")
pub fn client_program_infer_execution_poll_kind(
  value : @infer_host.Poll,
) -> String {
  @infer_host.poll_kind(value)
}

///|
#export_name("clientProgramInferExecutionPollIssue")
pub fn client_program_infer_execution_poll_issue(
  value : @infer_host.Poll,
) -> @infer_host.Issue? {
  @infer_host.poll_issue(value)
}

///|
#export_name("clientProgramInferExecutionHandoffPending")
pub fn client_program_infer_execution_handoff_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.handoff_pending(active)
}

///|
#export_name("clientProgramInferRequestPreflightPending")
pub fn client_program_infer_request_preflight_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.request_preflight_pending(active)
}

///|
#export_name("clientProgramInferIdentityPending")
pub fn client_program_infer_identity_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.identity_pending(active)
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
pub(all) enum ClientProgramInferMaterialBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Material(@publication_host.ClientExecutionMaterialIssue)
}

///|
/// Compile profile/template and Result material under the original owner.
/// This does not issue a runnable Plan or authorize a provider dispatch.
#export_name("clientProgramInferExecutionMaterial")
pub fn client_program_infer_execution_material(
  prepared : @publication_host.PreparedClientProgram,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[
  @publication_host.ClientExecutionMaterial,
  ClientProgramInferMaterialBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_infer_execution_material(
    prepared, graph, manifests, 100000, 10000, 100,
  ).map_err(issue => Material(issue))
}

///|
#export_name("clientProgramInferExecutionMaterialWire")
pub fn client_program_infer_execution_material_wire(
  value : @publication_host.ClientExecutionMaterial,
) -> String {
  @publication_host.client_execution_material_wire(value)
}

///|
#export_name("clientProgramInferExecutionMaterialTemplateWire")
pub fn client_program_infer_execution_material_template_wire(
  value : @publication_host.ClientExecutionMaterial,
) -> String {
  @publication_host.client_execution_material_template_wire(value)
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
#export_name("clientProgramInferInvocationEvidence")
pub fn client_program_infer_invocation_evidence(
  active : @infer_host.Execution,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  @infer_host.invocation_evidence(active, slot)
}

///|
#export_name("clientProgramInferObservationPending")
pub fn client_program_infer_observation_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.sealing_observation(active)
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
