///|
/// Node transports bounded common-generation pieces to the existing Store.
/// It does not implement a second encoder or create authority from JSON.

///|
#export_name("clientProgramSerializationOccurrences")
pub fn client_program_serialization_occurrences(
  owner : @publication_host.PreparedClientProgram,
) -> Array[(Int, Int)] {
  @publication_host.prepared_client_serialization_occurrences(owner)
}

///|
#export_name("clientProgramEffectSerializationOccurrences")
pub fn client_program_effect_serialization_occurrences(
  owner : @publication_host.PreparedClientEffectComputation,
) -> Array[(Int, Int)] {
  @publication_host.prepared_client_effect_serialization_occurrences(owner)
}

///|
#export_name("clientProgramSerializationCapture")
pub fn client_program_serialization_capture(
  generation : @publication_host.ClientSerializationGeneration,
) -> Result[@publication.BoundContentGeneration, String] {
  match @publication_host.client_serialization_generation_capture(generation) {
    Some(value) => Ok(value)
    None => Err("Client Content capture unavailable")
  }
}

///|
#export_name("clientProgramSerializationByteHoldingCid")
pub fn client_program_serialization_byte_holding_cid(
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  store : String,
) -> Result[String, String] {
  match
    @publication_host.client_serialization_byte_holding_cid(
      run, definition, store,
    ) {
    Some(value) => Ok(value)
    None => Err("Client Content byte binding unavailable")
  }
}

///|
#export_name("clientCapturedContentGenerationCount")
pub fn client_captured_content_generation_count(
  captured : @publication.PublicationContract,
) -> Result[Int, String] {
  match @publication.captured_content_generation_count(captured) {
    Some(value) => Ok(value)
    None => Err("Captured Content inventory unavailable")
  }
}

///|
#export_name("clientCapturedContentGenerationStorage")
pub fn client_captured_content_generation_storage(
  captured : @publication.PublicationContract,
  definition : @publication.PublicationContract,
  store : String,
  index : Int,
) -> Result[
  (String, String, String, Int64, Array[(String, String, String, String)]),
  String,
] {
  match
    @publication.captured_content_generation_storage(
      captured, definition, store, index,
    ) {
    Some(value) => Ok(value)
    None => Err("Captured Content storage binding unavailable")
  }
}

///|
/// The installed Host supplies finite ceilings and the actual policy original.
/// This selects compilation material, not permission to publish future bytes.
#export_name("clientProgramSerializationPlanGraph")
pub fn client_program_serialization_plan_graph(
  owner : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  policy_cid : String,
  policy_wire : String,
  max_rows : Int,
  max_bytes : Int,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  @publication_host.ClientSerializationPlanGraphIssue,
] {
  let original = match
    @publication_host.admit_source_free_result_policy_body(
      policy_cid, policy_wire, 1000000, 100000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Policy(issue))
  }
  @publication_host.issue_prepared_client_serialization_plan_graph(
    owner,
    task,
    step,
    original,
    max_rows,
    max_bytes,
    10000,
    @publication_host.prepared_client_values_sequence_limits(owner),
    1000000,
    100000,
    100,
  )
}

///|
#export_name("clientProgramSerializationPlanGraphWire")
pub fn client_program_serialization_plan_graph_wire(
  graph : @publication_host.ClientSerializationPlanGraph,
) -> String {
  @publication_host.client_serialization_plan_graph_wire(graph)
}

///|
/// Intermediate generation has no public roots. The enclosing checked Model
/// graph retains its exact component, policy and real producer port.
#export_name("clientProgramSerializationPlanComponent")
pub fn client_program_serialization_plan_component(
  owner : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  policy_cid : String,
  policy_wire : String,
  max_rows : Int,
  max_bytes : Int,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  @publication_host.ClientSerializationPlanGraphIssue,
] {
  let original = match
    @publication_host.admit_source_free_result_policy_body(
      policy_cid, policy_wire, 1000000, 100000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Policy(issue))
  }
  @publication_host.issue_prepared_client_serialization_plan_component(
    owner,
    task,
    step,
    original,
    max_rows,
    max_bytes,
    10000,
    @publication_host.prepared_client_values_sequence_limits(owner),
    1000000,
    100000,
    100,
  )
}

///|
#export_name("clientProgramCompiledRunSerializationGraph")
pub fn client_program_compiled_run_serialization_graph(
  run : @publication_host.ClientCompiledRun,
) -> @publication_host.ClientSerializationPlanGraph? {
  @publication_host.client_compiled_run_serialization(run)
}

///|
#export_name("clientProgramInferPlanSerializationGraph")
pub fn client_program_infer_plan_serialization_graph(
  graph : @publication_host.ClientInferPlanGraph,
) -> @publication_host.ClientSerializationPlanGraph? {
  @publication_host.client_infer_plan_graph_serialization(graph)
}

///|
#export_name("clientProgramCompiledRunHasSerialization")
pub fn client_program_compiled_run_has_serialization(
  run : @publication_host.ClientCompiledRun,
) -> Bool {
  @publication_host.client_compiled_run_serialization(run) is Some(_)
}

///|
#export_name("clientProgramSerializationPlanGraphCoordinates")
pub fn client_program_serialization_plan_graph_coordinates(
  component : @publication_host.ClientSerializationPlanGraph,
) -> (Int, Int) {
  @publication_host.client_serialization_plan_graph_coordinates(component)
}

///|
#export_name("clientProgramSerializationJsonLeafFieldCount")
pub fn client_program_serialization_json_leaf_field_count(
  component : @publication_host.ClientSerializationPlanGraph,
) -> Int {
  @client_local_host.client_serialization_json_leaf_field_count(component)
}

///|
#export_name("clientProgramAcquiredSerializationPlanGraph")
pub fn client_program_acquired_serialization_plan_graph(
  owner : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  @publication_host.ClientSerializationPlanGraphIssue,
] {
  @publication_host.issue_prepared_client_acquired_serialization_plan_graph(
    owner,
    task,
    step,
    max_rows,
    max_bytes,
    10000,
    @publication_host.prepared_client_values_sequence_limits(owner),
    1000000,
    100000,
    100,
  )
}

///|
#export_name("clientProgramAcquiredSerializationPlanComponent")
pub fn client_program_acquired_serialization_plan_component(
  owner : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  @publication_host.ClientSerializationPlanGraphIssue,
] {
  @publication_host.issue_prepared_client_acquired_serialization_plan_component(
    owner,
    task,
    step,
    max_rows,
    max_bytes,
    10000,
    @publication_host.prepared_client_values_sequence_limits(owner),
    1000000,
    100000,
    100,
  )
}

///|
#export_name("clientProgramSerializationPolicyBody")
pub fn client_program_serialization_policy_body(
  run : @publication_host.ClientCompiledRun,
) -> (String, String, String)? {
  @publication_host.client_compiled_run_serialization_policy_body(run).map(body => {
    (
      @publication.captured_effect_dependency_body_kind(body),
      @publication.captured_effect_dependency_body_cid(body),
      @publication.captured_effect_dependency_body_json(body),
    )
  })
}

///|
#export_name("clientProgramAdmitSerializationCapturedInput")
pub fn client_program_admit_serialization_captured_input(
  owner : @publication_host.PreparedClientProgram,
  graph : @publication_host.ClientSerializationPlanGraph,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  logical : @publication.RunEvidenceValue,
  source_wire : String,
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
  keyed : @publication_host.ClientKeyedLookupObservation?,
) -> Result[
  @publication_host.ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  let evidence = match
    @publication.admit_run_evidence_value(
      "source_evidence", source_wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match keyed {
    None =>
      @publication_host.admit_client_serialization_captured_input(
        owner, graph, source, identity, requirement, logical, evidence, authority_scope_cid,
        started_at, completed_at,
      )
    Some(keyed) =>
      @publication_host.admit_client_keyed_serialization_captured_input(
        owner, graph, source, identity, requirement, logical, evidence, keyed, authority_scope_cid,
        started_at, completed_at,
      )
  }
}

///|
#export_name("clientProgramCompileLocalSerialization")
pub fn client_program_compile_local_serialization(
  owner : @publication_host.PreparedClientProgram,
  graph : @publication_host.ClientSerializationPlanGraph,
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
  @publication_host.issue_prepared_client_serialization_compilation(
    owner, graph, manifests, 1000, 10000, 1000000, 100000, 100,
  ).map_err(issue => Compilation(issue))
}

///|
fn serialization_prefix_limits(
  max_rows : Int,
  max_work : Int,
  max_entries : Int,
  max_value_bytes : Int,
  max_value_nodes : Int,
  max_value_depth : Int,
  max_frames : Int,
) -> (
  @execution.SequenceExecutionLimits,
  @execution.FixedInputGuardMeasureLimits,
) {
  let value_limits : @execution.ValueLimits = {
    max_nodes: max_value_nodes,
    max_text_bytes: max_value_bytes,
    max_depth: max_value_depth,
    max_work,
  }
  (
    {
      rows: {
        max_rows,
        metadata_entries: max_entries,
        retained_entries: max_entries,
        operation_entries: max_entries,
        input_values: value_limits,
        output_values: value_limits,
      },
      max_work,
      max_frames,
    },
    {
      max_work,
      max_bytes: max_value_bytes,
      max_nodes: max_value_nodes,
      max_depth: max_value_depth,
    },
  )
}

///|
/// Same Request compiler and Content constructor; the seven existing prefix
/// configuration fields keep their original conversion. No bare Ledger or
/// reconstructed graph crosses this entry.
#export_name("clientProgramPrepareRequestSerializationPlan")
pub fn client_program_prepare_request_serialization_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  max_rows : Int,
  max_work : Int,
  max_entries : Int,
  max_value_bytes : Int,
  max_value_nodes : Int,
  max_value_depth : Int,
  max_frames : Int,
  workspace : @execution.ExecutionCapacity?,
) -> Result[
  @client_local_host.ClientInstalledManagedSerializationPreparation,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let (execution, measurement) = serialization_prefix_limits(
    max_rows, max_work, max_entries, max_value_bytes, max_value_nodes, max_value_depth,
    max_frames,
  )
  @client_local_host.prepare_request_serialization_plan(
    parent, input, request, compiled, definition, execution, measurement, workspace,
  )
}

///|
/// Same Request compiler and Content input constructor; the seven existing prefix
/// configuration fields keep their original conversion. No bare Ledger or
/// reconstructed graph crosses this entry.
#export_name("clientProgramPrepareRequestWholeSerializationPlan")
pub fn client_program_prepare_request_whole_serialization_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  max_rows : Int,
  max_work : Int,
  max_entries : Int,
  max_value_bytes : Int,
  max_value_nodes : Int,
  max_value_depth : Int,
  max_frames : Int,
  workspace : @execution.ExecutionCapacity?,
  whole_plan : @client_local_host.ClientInstalledManagedCapturePlan,
) -> Result[
  @client_local_host.ClientInstalledManagedSerializationPreparation,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let (execution, measurement) = serialization_prefix_limits(
    max_rows, max_work, max_entries, max_value_bytes, max_value_nodes, max_value_depth,
    max_frames,
  )
  @client_local_host.prepare_request_serialization_plan(
    parent,
    input,
    request,
    compiled,
    definition,
    execution,
    measurement,
    workspace,
    whole_plan=Some(whole_plan),
  )
}

///|
#export_name("clientProgramPrepareRequestModelSerializationPlan")
pub fn client_program_prepare_request_model_serialization_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  max_rows : Int,
  max_work : Int,
  max_entries : Int,
  max_value_bytes : Int,
  max_value_nodes : Int,
  max_value_depth : Int,
  max_frames : Int,
  workspace : @execution.ExecutionCapacity?,
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  @client_local_host.ClientInstalledManagedSerializationPreparation,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let (execution, measurement) = serialization_prefix_limits(
    max_rows, max_work, max_entries, max_value_bytes, max_value_nodes, max_value_depth,
    max_frames,
  )
  @client_local_host.prepare_request_model_serialization_plan(
    parent, input, request, compiled, definition, execution, measurement, workspace,
    query_time,
  )
}

///|
#export_name("clientProgramPrepareRequestKeyedContentPlan")
pub fn client_program_prepare_request_keyed_content_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  keyed : @publication_host.ClientKeyedAcquisition,
  direct_declaration : @client_row_source_host.RowDeclaration,
  content_declaration : @client_row_source_host.RowDeclaration,
  max_page_bytes : Int,
  max_text_bytes : Int,
  row_work : Int,
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  task : Int,
  step : Int,
  prefix_max_rows : Int,
  prefix_max_work : Int,
  max_entries : Int,
  max_value_bytes : Int,
  max_value_nodes : Int,
  max_value_depth : Int,
  max_frames : Int,
  workspace : @execution.ExecutionCapacity?,
) -> Result[
  @client_local_host.ClientInstalledManagedKeyedPreparation,
  ClientRequestProgramModuleBridgeIssue,
] {
  let (execution, measurement) = serialization_prefix_limits(
    prefix_max_rows, prefix_max_work, max_entries, max_value_bytes, max_value_nodes,
    max_value_depth, max_frames,
  )
  @client_local_host.prepare_request_keyed_content_plan(
    parent,
    input,
    request,
    keyed,
    direct_declaration,
    content_declaration,
    @client_local_host.installed_keyed_row_limits(
      max_page_bytes, max_text_bytes, row_work,
    ),
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    max_bytes,
    max_work,
    contracts,
    task,
    step,
    execution,
    measurement,
    workspace,
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPreparedInstalledSerializationPrefixRequirements")
pub fn client_program_prepared_installed_serialization_prefix_requirements(
  selected : @client_local_host.ClientInstalledManagedSerializationPreparation,
) -> Array[Int64] {
  @client_local_host.prepared_installed_managed_serialization_prefix_requirements(
    selected,
  )
}

///|
#export_name("clientProgramPreparedInstalledKeyedPrefixRequirements")
pub fn client_program_prepared_installed_keyed_prefix_requirements(
  selected : @client_local_host.ClientInstalledManagedKeyedPreparation,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.prepared_installed_managed_keyed_prefix_requirements(
    selected,
  )
}

///|
#export_name("clientProgramInstalledManagedKeyedSerializationPrefixStart")
pub fn client_program_installed_managed_keyed_serialization_prefix_start(
  run : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : @client_local_host.ClientInstalledManagedKeyedPreparation,
  source : @query.CapturedInputSource,
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[
  @client_local_host.ClientSerializationPrefix,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.start_installed_managed_keyed_serialization_prefix(
    run, prepared, selected, source, lookup,
  )
}

///|
#export_name("clientProgramInstalledManagedKeyedSerializationPrefixCleanup")
pub fn client_program_installed_managed_keyed_serialization_prefix_cleanup(
  run : @client_local_host.ClientInstalledManagedRun,
  selected : @client_local_host.ClientInstalledManagedKeyedPreparation,
) -> Result[Bool, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.cleanup_installed_managed_keyed_serialization_prefix(
    run, selected,
  )
}

///|
#export_name("clientProgramInstalledManagedSerializationPrefixStart")
pub fn client_program_installed_managed_serialization_prefix_start(
  run : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : @client_local_host.ClientInstalledManagedSerializationPreparation,
) -> Result[
  @client_local_host.ClientSerializationPrefix,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.start_installed_managed_serialization_prefix(
    run, prepared, selected,
  )
}

///|
#export_name("clientProgramInstalledManagedSerializationPrefixCleanup")
pub fn client_program_installed_managed_serialization_prefix_cleanup(
  run : @client_local_host.ClientInstalledManagedRun,
  selected : @client_local_host.ClientInstalledManagedSerializationPreparation,
) -> Result[Bool, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.cleanup_installed_managed_serialization_prefix(
    run, selected,
  )
}

///|
#export_name("clientProgramInstalledManagedAcquiredSerializationPrefixStart")
pub fn client_program_installed_managed_acquired_serialization_prefix_start(
  run : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : @client_local_host.ClientInstalledManagedSerializationPreparation,
  capture : @client_row_source_host.RowSourceCapture,
) -> Result[
  @client_local_host.ClientSerializationPrefix,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.start_installed_managed_acquired_serialization_prefix(
    run, prepared, selected, capture,
  )
}

///|
#export_name("clientProgramInstalledManagedWholeSerializationPrefixStart")
pub fn client_program_installed_managed_whole_serialization_prefix_start(
  run : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : @client_local_host.ClientInstalledManagedSerializationPreparation,
  captures : Array[@client_row_source_host.RowSourceCapture],
) -> Result[
  @client_local_host.ClientSerializationPrefix,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.start_installed_managed_whole_serialization_prefix(
    run, prepared, selected, captures,
  )
}

///|
#export_name("clientProgramSerializationPrefixCapacity")
pub fn client_program_serialization_prefix_capacity(
  program : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  max_rows : Int,
  max_work : Int,
  max_entries : Int,
  max_value_bytes : Int,
  max_value_nodes : Int,
  max_value_depth : Int,
  max_frames : Int,
  acquired : Bool,
) -> (Int64, Int64)? {
  let (execution, measurement) = serialization_prefix_limits(
    max_rows, max_work, max_entries, max_value_bytes, max_value_nodes, max_value_depth,
    max_frames,
  )
  let capacity = if acquired {
    @client_local_host.client_acquired_serialization_prefix_capacity(
      program, task, step, sequence_contracts, values, fragment, ordered, execution,
      measurement,
    )
  } else {
    @client_local_host.client_serialization_prefix_capacity(
      program, task, step, sequence_contracts, values, fragment, ordered, execution,
      measurement,
    )
  }
  capacity.map(capacity => {
    (
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    )
  })
}

///|
#export_name("clientProgramStartSerializationPrefix")
pub fn client_program_start_serialization_prefix(
  program : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  max_rows : Int,
  max_work : Int,
  max_entries : Int,
  max_value_bytes : Int,
  max_value_nodes : Int,
  max_value_depth : Int,
  max_frames : Int,
  ledger : @resources.Ledger,
  workspace : @execution.ExecutionCapacity?,
  source : @query.CapturedInputSource?,
  keyed : @publication_host.ClientKeyedLookupInput?,
) -> Result[
  @client_local_host.ClientSerializationPrefix,
  @client_local_host.ClientSerializationPrefixIssue,
] {
  let (execution, measurement) = serialization_prefix_limits(
    max_rows, max_work, max_entries, max_value_bytes, max_value_nodes, max_value_depth,
    max_frames,
  )
  if source is Some(source) {
    return @client_local_host.start_client_acquired_serialization_prefix(
      program,
      task,
      step,
      source,
      sequence_contracts,
      values,
      fragment,
      ordered,
      execution,
      measurement,
      ledger,
      workspace~,
      keyed~,
    )
  }
  @client_local_host.start_client_serialization_prefix(
    program,
    task,
    step,
    sequence_contracts,
    values,
    fragment,
    ordered,
    execution,
    measurement,
    ledger,
    workspace~,
  )
}

///|
#export_name("clientProgramSerializationWorkspaceCapacity")
pub fn client_program_serialization_workspace_capacity(
  generation_bytes : Int,
  generation_nodes : Int,
  generation_depth : Int,
  generation_frames : Int,
  identity_slots : Int,
  reference_bytes : Int,
  reference_nodes : Int,
  reference_depth : Int,
  contract_bytes : Int,
  contract_nodes : Int,
  contract_depth : Int,
  export_limits : @publication_host.PublicationOutputExportLimits,
) -> @execution.ExecutionCapacity? {
  @client_local_host.client_serialization_workspace_capacity({
    generation_bytes,
    generation_nodes,
    generation_depth,
    generation_frames,
    identity_slots,
    reference_bytes,
    reference_nodes,
    reference_depth,
    contract_bytes,
    contract_nodes,
    contract_depth,
    export_limits,
  })
}

///|
#export_name("clientProgramSerializationCapacityBytes")
pub fn client_program_serialization_capacity_bytes(
  capacity : @execution.ExecutionCapacity,
) -> (Int64, Int64) {
  (
    @execution.execution_capacity_retained_bytes(capacity),
    @execution.execution_capacity_execution_bytes(capacity),
  )
}

///|
#export_name("clientProgramSerializationPrefixAdvance")
pub fn client_program_serialization_prefix_advance(
  prefix : @client_local_host.ClientSerializationPrefix,
  quantum : Int,
) -> Result[
  (
    @execution.CompletedOutput?,
    Int64,
    Int64,
    Bool,
    @connector.FixedComputeIssue?,
  ),
  @connector.FixedComputeIssue,
] {
  @client_local_host.advance_client_serialization_prefix(prefix, quantum).map(poll => {
    match poll {
      Complete(output, progress~, work~) =>
        (Some(output), progress, work, true, None)
      Continue(progress~, work~)
      | Waiting(progress~, work~)
      | Settling(_, progress~, work~) => (None, progress, work, false, None)
      AwaitIo(progress~, work~) =>
        (None, progress, work, true, Some(@connector.ComputeUnsupported))
      Failed(issue, progress~, work~) =>
        (None, progress, work, true, Some(issue))
      Stopped(progress~, work~) => (None, progress, work, true, None)
      CarrierComplete(_, progress~, work~) =>
        (
          None,
          progress,
          work,
          true,
          Some(@connector.Execution(@execution.InputSet)),
        )
    }
  })
}

///|
#export_name("clientProgramSerializationPrefixWork")
pub fn client_program_serialization_prefix_work(
  prefix : @client_local_host.ClientSerializationPrefix,
) -> Result[Int64, @local.ManagedProviderWorkIssue] {
  @client_local_host.client_serialization_prefix_work(prefix)
}

///|
#export_name("clientProgramSerializationPrefixCancel")
pub fn client_program_serialization_prefix_cancel(
  prefix : @client_local_host.ClientSerializationPrefix,
) -> Bool {
  @client_local_host.cancel_client_serialization_prefix(prefix)
}

///|
#export_name("clientProgramSerializationPrefixCleanup")
pub fn client_program_serialization_prefix_cleanup(
  prefix : @client_local_host.ClientSerializationPrefix,
) -> Result[Bool, @client_local_host.ClientSerializationPrefixIssue] {
  @client_local_host.cleanup_client_serialization_prefix(prefix)
}

///|
#export_name("clientProgramPrepareSerialization")
pub fn client_program_prepare_serialization(
  owner : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  max_work : Int,
) -> Result[
  @lower.PreparedSerialization,
  @publication_host.ClientSerializationPreparationIssue,
] {
  @publication_host.prepare_client_serialization(owner, task, step, max_work~)
}

///|
#export_name("clientProgramSerializationEncoder")
pub fn client_program_serialization_encoder(
  barrier : @lower.PreparedSerialization,
  max_rows : Int,
  max_bytes : Int,
  max_value_nodes : Int,
  max_value_depth : Int,
  max_frames : Int,
) -> Result[
  @publication.ContentByteEncoder,
  @publication.ContentSerializationIssue,
] {
  @publication_host.start_client_serialization_encoder(
    barrier,
    max_rows~,
    max_bytes~,
    max_value_nodes~,
    max_value_depth~,
    max_frames~,
  )
}

///|
#export_name("clientProgramSerializationBindInput")
pub fn client_program_serialization_bind_input(
  barrier : @lower.PreparedSerialization,
  input : @execution.CompletedOutput,
  encoder : @publication.ContentByteEncoder,
) -> Result[
  @publication_host.ClientSerializationInput,
  @publication_host.ClientSerializationInputIssue,
] {
  @publication_host.bind_client_serialization_completed_input(
    barrier, input, encoder,
  )
}

///|
#export_name("clientProgramSerializationInputIsRowLimit")
pub fn client_program_serialization_input_is_row_limit(
  issue : @publication_host.ClientSerializationInputIssue,
) -> Bool {
  match issue {
    RowLimit | Encoding(@publication.ContentRowLimit) => true
    _ => false
  }
}

///|
#export_name("clientProgramSerializationInputRows")
pub fn client_program_serialization_input_rows(
  input : @publication_host.ClientSerializationInput,
) -> Int {
  @publication_host.client_serialization_input_rows(input)
}

///|
#export_name("clientProgramSerializationInputIdentityStart")
pub fn client_program_serialization_input_identity_start(
  input : @publication_host.ClientSerializationInput,
  limits : @publication_host.PublicationOutputExportLimits,
  max_work : Int,
  max_workspace_slots : Int,
) -> Result[
  @execution.CompletedRelationIdentityScan,
  @execution.CompletedExportIssue,
] {
  if @publication_host.client_serialization_input_rows(input) > limits.max_rows {
    return Err(@execution.Admission(@execution.CaptureLimit))
  }
  @publication_host.start_client_serialization_input_identity(
    input,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    max_work,
    max_workspace_slots,
  )
}

///|
/// Failed polls retain actual consumed work before the Node transport handles
/// the issue. This borrows the original bounded export, not another scan owner.
#export_name("clientProgramSerializationInputIdentityAdvance")
pub fn client_program_serialization_input_identity_advance(
  scan : @execution.CompletedRelationIdentityScan,
  quantum : Int,
) -> (Bool, Int64, @execution.CompletedExportIssue?) {
  let before = @execution.completed_relation_identity_scan_work(scan)
  let outcome = @execution.advance_completed_relation_identity_scan(
    scan, quantum,
  )
  let delta = @execution.completed_relation_identity_scan_work(scan) - before
  match outcome {
    Ok((ready, _)) => (ready, delta, None)
    Err(issue) => (false, delta, Some(issue))
  }
}

///|
#export_name("clientProgramSerializationInputIdentityFinish")
pub fn client_program_serialization_input_identity_finish(
  scan : @execution.CompletedRelationIdentityScan,
) -> Result[
  @execution.CompletedRelationExportReceipt,
  @execution.CompletedExportIssue,
] {
  @execution.finish_completed_relation_identity_scan(scan)
}

///|
#export_name("clientProgramSerializationInputIdentityCancel")
pub fn client_program_serialization_input_identity_cancel(
  scan : @execution.CompletedRelationIdentityScan,
) -> Bool {
  @execution.cancel_completed_relation_identity_scan(scan)
}

///|
#export_name("clientProgramSerializationInputIdentityReceiptCancel")
pub fn client_program_serialization_input_identity_receipt_cancel(
  receipt : @execution.CompletedRelationExportReceipt,
) -> Unit {
  @execution.cancel_completed_relation_export_receipt(receipt)
}

///|
#export_name("clientProgramSerializationInputIdentityBind")
pub fn client_program_serialization_input_identity_bind(
  run : @publication_host.ClientCompiledRun,
  input : @publication_host.ClientSerializationInput,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  captured : @publication_host.ClientSerializationCapturedInput?,
) -> Result[
  @publication_host.ClientSerializationInputEvidence,
  @publication.RunEvidenceValueIssue,
] {
  let result = match captured {
    Some(value) =>
      @publication_host.bind_client_acquired_serialization_input_identity(
        run, input, receipt, value, max_wire_bytes, max_nodes, max_depth,
      )
    None =>
      @publication_host.bind_client_serialization_input_identity(
        run, input, receipt, max_wire_bytes, max_nodes, max_depth,
      )
  }
  // The sealed identity no longer borrows export reference callbacks. The
  // original input and its physical cleanup remain the producer's property.
  @execution.cancel_completed_relation_export_receipt(receipt)
  result
}

///|
#export_name("clientProgramSerializationInputArtifact")
pub fn client_program_serialization_input_artifact(
  input : @publication_host.ClientSerializationInputEvidence,
) -> @publication.RunEvidenceValue {
  @publication_host.client_serialization_input_artifact(input)
}

///|
#export_name("clientProgramSerializationOutput")
pub fn client_program_serialization_output(
  input : @publication_host.ClientSerializationInput,
  candidate : @publication.GeneratedContentReference,
  content : @admitted.CheckedValue,
  available : () -> Bool,
  max_nodes : Int,
  max_text_bytes : Int,
  max_depth : Int,
  max_work : Int,
  max_name_bytes : Int,
) -> Result[
  @execution.CompletedOutput,
  @publication_host.ClientSerializationOutputIssue,
] {
  @publication_host.complete_client_serialization_output(
    input,
    candidate,
    content,
    available,
    { max_nodes, max_text_bytes, max_depth, max_work, },
    max_name_bytes,
  )
}

///|
#export_name("clientProgramSerializationGeneration")
pub fn client_program_serialization_generation(
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  input : @publication_host.ClientSerializationInput,
  input_evidence : @publication_host.ClientSerializationInputEvidence,
  candidate : @publication.GeneratedContentReference,
  content : @admitted.CheckedValue,
  available : () -> Bool,
  max_nodes : Int,
  max_text_bytes : Int,
  max_depth : Int,
  max_work : Int,
  max_name_bytes : Int,
) -> Result[
  @publication_host.ClientSerializationGeneration,
  @publication_host.ClientSerializationGenerationIssue,
] {
  @publication_host.complete_client_serialization_generation(
    run,
    definition,
    input,
    input_evidence,
    candidate,
    content,
    available,
    { max_nodes, max_text_bytes, max_depth, max_work, },
    max_name_bytes,
  )
}

///|
#export_name("clientProgramSerializationGenerationEvidence")
pub fn client_program_serialization_generation_evidence(
  generation : @publication_host.ClientSerializationGeneration,
  run : @publication_host.ClientCompiledRun,
) -> @publication.RunEvidenceValue? {
  @publication_host.client_serialization_generation_evidence_for(
    generation, run,
  )
}

///|
#export_name("clientProgramReadmitSerializationGeneration")
pub fn client_program_readmit_serialization_generation(
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  scope : @publication_host.ClientInferSavedCallScope,
  expected_generation_cid : String,
  input : @publication.RunEvidenceValue,
  derivation : @publication.RunEvidenceValue,
  generation : @publication.RunEvidenceValue,
  candidate : @publication.StoredGeneratedContentReference,
  content : @admitted.CheckedValue,
) -> Result[
  @publication_host.ClientSerializationGeneration,
  @publication_host.ClientSerializationGenerationIssue,
] {
  let evidence = match
    @publication_host.readmit_client_serialization_generation_evidence(
      run, definition, expected_generation_cid, input, derivation, generation, candidate,
      content,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication_host.readmit_client_serialization_generation(
    run, definition, plan, scope, evidence,
  )
}

///|
#export_name("clientProgramSerializationRecoveryBindings")
pub fn client_program_serialization_recovery_bindings(
  generation : @publication_host.ClientSerializationGeneration,
  run : @publication_host.ClientCompiledRun,
  store_authority_cid : String,
) -> Result[Array[(String, String, String, String)], String] {
  match
    @publication_host.client_serialization_generation_recovery_bindings(
      generation, run, store_authority_cid,
    ) {
    Some(bindings) => Ok(bindings)
    None => Err("Client Content recovery binding unavailable")
  }
}

///|
#export_name("clientProgramIssueSerializationInvocation")
pub fn client_program_issue_serialization_invocation(
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  generation : @publication_host.ClientSerializationGeneration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_serialization_invocation(
    run, definition, generation, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramSerializationGenerationDerivation")
pub fn client_program_serialization_generation_derivation(
  generation : @publication_host.ClientSerializationGeneration,
  run : @publication_host.ClientCompiledRun,
) -> @publication.RunEvidenceValue? {
  @publication_host.client_serialization_generation_derivation_for(
    generation, run,
  )
}

///|
#export_name("clientProgramSerializationGenerationOutput")
pub fn client_program_serialization_generation_output(
  generation : @publication_host.ClientSerializationGeneration,
  run : @publication_host.ClientCompiledRun,
) -> @execution.CompletedOutput? {
  @publication_host.client_serialization_generation_output_for(generation, run)
}

///|
#export_name("clientProgramSerializationOutputRowWire")
pub fn client_program_serialization_output_row_wire(
  output : @execution.CompletedOutput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @execution.CompletedExportIssue] {
  @execution.completed_output_row_wire(
    output, 0, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramSerializationOutputIssueCode")
pub fn client_program_serialization_output_issue_code(
  issue : @publication_host.ClientSerializationOutputIssue,
) -> String {
  match issue {
    GenerationIncomplete => "GenerationIncomplete"
    ForeignReference => "ForeignReference"
    InputUnavailable => "InputUnavailable"
    OutputUnavailable => "OutputUnavailable"
    InvalidLimits => "InvalidLimits"
    InvalidSchema => "InvalidSchema"
    Admission(@execution.CaptureLimit) => "OutputCaptureLimit"
    Admission(@execution.ForeignCheckedValue(_, _)) => "ForeignOutputContract"
    Admission(_) => "Admission"
    Completion(_) => "Completion"
  }
}

///|
#export_name("clientProgramSerializationOutputAvailable")
pub fn client_program_serialization_output_available(
  output : @execution.CompletedOutput,
) -> Bool {
  @execution.completed_output_available(output)
}

///|
/// Use the original checked Result occurrence and its existing bounded view
/// exporter. The generated producer's canonical schema order is not the
/// author's publication projection order, and neither may replace the other.
#export_name("clientProgramSerializationResultOccurrence")
pub fn client_program_serialization_result_occurrence(
  program : @publication_host.PreparedClientProgram,
  result : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (String, Int, @publication.PublicationContract),
  @publication_host.ClientResultTransformationIssue,
] {
  @publication_host.prepare_client_result_transformation(
    program, result, max_wire_bytes, max_nodes, max_depth,
  ).map(selection => {
    (
      @publication_host.client_result_transformation_name(selection),
      @publication_host.client_result_transformation_task(selection),
      @publication_host.client_result_transformation_definition(selection),
    )
  })
}

///|
#export_name("clientProgramSerializationResultStart")
pub fn client_program_serialization_result_start(
  program : @publication_host.PreparedClientProgram,
  result : Int,
  output : @execution.CompletedOutput,
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[
  @publication_host.ClientResultTransformationPreparation,
  @publication_host.ClientResultTransformationIssue,
] {
  @publication_host.prepare_client_result_transformation(
    program,
    result,
    limits.schema.max_bytes,
    limits.schema.max_nodes,
    limits.schema.max_depth,
  ).bind(selection => {
    @publication_host.start_client_result_transformation(
      selection, output, limits,
    )
  })
}

///|
#export_name("clientProgramSerializationResultAdvance")
pub fn client_program_serialization_result_advance(
  value : @publication_host.ClientResultTransformationPreparation,
  quantum : Int,
) -> Result[(Bool, Int), @publication_host.ClientResultTransformationIssue] {
  value.advance(quantum)
}

///|
#export_name("clientProgramSerializationResultProgress")
pub fn client_program_serialization_result_progress(
  value : @publication_host.ClientResultTransformationPreparation,
  quantum : Int,
) -> (Bool, Int, @publication_host.ClientResultTransformationIssue?) {
  value.advance_progress(quantum)
}

///|
#export_name("clientProgramSerializationResultFinish")
pub fn client_program_serialization_result_finish(
  value : @publication_host.ClientResultTransformationPreparation,
) -> Result[
  StrategyHostOutputExport,
  @publication_host.ClientResultTransformationIssue,
] {
  value.finish().map(core => { core, managed_import: None, })
}

///|
#export_name("clientProgramSerializationResultCancel")
pub fn client_program_serialization_result_cancel(
  value : @publication_host.ClientResultTransformationPreparation,
) -> Bool {
  value.cancel()
}

///|
#export_name("clientProgramSerializationInputRow")
pub fn client_program_serialization_input_row(
  input : @publication_host.ClientSerializationInput,
  row : Int,
) -> Result[Unit, @publication_host.ClientSerializationInputIssue] {
  @publication_host.start_client_serialization_input_row(input, row)
}

///|
#export_name("clientProgramSerializationCancel")
pub fn client_program_serialization_cancel(
  encoder : @publication.ContentByteEncoder,
) -> Unit {
  @publication.cancel_content_byte_encoder(encoder)
}

///|
#export_name("clientProgramSerializationRow")
pub fn client_program_serialization_row(
  barrier : @lower.PreparedSerialization,
  input : @execution.CompletedOutput,
  row : Int,
  encoder : @publication.ContentByteEncoder,
) -> Result[Unit, @publication_host.ClientSerializationInputIssue] {
  @publication_host.start_client_serialization_completed_row(
    barrier, input, row, encoder,
  )
}

///|
#export_name("clientProgramSerializationAdvance")
pub fn client_program_serialization_advance(
  encoder : @publication.ContentByteEncoder,
  quantum : Int,
) -> (Bool, String, Int, @publication.ContentSerializationIssue?) {
  match @publication.advance_content_bytes(encoder, quantum) {
    ContentBytesContinue(piece, work~) => (false, piece, work, None)
    ContentBytesReady(piece, work~) => (true, piece, work, None)
    ContentBytesFailed(issue, work~) => (false, "", work, Some(issue))
  }
}

///|
#export_name("clientProgramSerializationFinish")
pub fn client_program_serialization_finish(
  encoder : @publication.ContentByteEncoder,
) -> Result[
  (String, String, String, Int, Int),
  @publication.ContentSerializationIssue,
] {
  @publication.finish_content_bytes(encoder).map(value => {
    (
      value.name,
      value.media_type,
      value.content_cid,
      value.size_bytes,
      value.row_count,
    )
  })
}

///|
#export_name("clientProgramGeneratedContentCandidate")
pub fn client_program_generated_content_candidate(
  encoder : @publication.ContentByteEncoder,
  binding_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[
  @publication.GeneratedContentReference,
  @publication.GeneratedContentReferenceIssue,
] {
  @publication.prepare_generated_content_reference_from_binding(
    encoder,
    binding_wire,
    { max_bytes, max_nodes, max_depth, max_text_units, },
  )
}

///|
#export_name("clientProgramGeneratedContentCandidateWire")
pub fn client_program_generated_content_candidate_wire(
  candidate : @publication.GeneratedContentReference,
) -> String {
  @publication.generated_content_reference_wire(candidate)
}

///|
#export_name("clientProgramStoredGeneratedContentCandidate")
pub fn client_program_stored_generated_content_candidate(
  original_wire : String,
  binding_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[
  @publication.StoredGeneratedContentReference,
  @publication.GeneratedContentReferenceIssue,
] {
  let limits : @admitted.ReferenceLimits = {
    max_bytes,
    max_nodes,
    max_depth,
    max_text_units,
  }
  let binding = match
    @publication.parse_content_reference_binding(binding_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication.prepare_stored_generated_content_reference(
    original_wire, binding, limits,
  )
}

///|
#export_name("clientProgramStoredGeneratedContentCandidateWire")
pub fn client_program_stored_generated_content_candidate_wire(
  candidate : @publication.StoredGeneratedContentReference,
) -> String {
  @publication.stored_generated_content_reference_wire(candidate)
}

///|
#export_name("clientProgramStoredGeneratedContentStorage")
pub fn client_program_stored_generated_content_storage(
  candidate : @publication.StoredGeneratedContentReference,
) -> (String, String, String, String, Int) {
  @publication.stored_generated_content_reference_storage(candidate)
}

///|
#export_name("clientProgramIssueStoredGeneratedContent")
pub fn client_program_issue_stored_generated_content(
  candidate : @publication.StoredGeneratedContentReference,
  issuer : @admitted.ReferenceIssuer,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[@admitted.CheckedValue, @publication.GeneratedContentReferenceIssue] {
  @publication.issue_stored_generated_content_reference(candidate, issuer, {
    max_bytes,
    max_nodes,
    max_depth,
    max_text_units,
  })
}

///|
#export_name("clientProgramGeneratedContentCandidateCid")
pub fn client_program_generated_content_candidate_cid(
  candidate : @publication.GeneratedContentReference,
) -> String {
  @publication.generated_content_reference_identity(candidate)
}

///|
#export_name("clientProgramGeneratedContentStorage")
pub fn client_program_generated_content_storage(
  candidate : @publication.GeneratedContentReference,
) -> (String, String, String, Int) {
  @publication.generated_content_reference_storage(candidate)
}

///|
#export_name("clientProgramIssueGeneratedContent")
pub fn client_program_issue_generated_content(
  candidate : @publication.GeneratedContentReference,
  issuer : @admitted.ReferenceIssuer,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[@admitted.CheckedValue, @publication.GeneratedContentReferenceIssue] {
  @publication.issue_generated_content_reference(candidate, issuer, {
    max_bytes,
    max_nodes,
    max_depth,
    max_text_units,
  })
}

///|
#export_name("clientProgramSerializationInputRowBound")
pub fn client_program_serialization_input_row_bound(
  graph : @publication_host.ClientSerializationPlanGraph,
) -> Int {
  @client_local_host.client_serialization_input_row_bound(graph).unwrap_or(-1)
}

///|
/// Keep the actual installed Whole acquisition distinct from a Query requirement.
#export_name("clientProgramAdmitSerializationWholeCapturedInput")
pub fn client_program_admit_serialization_whole_captured_input(
  owner : @publication_host.PreparedClientProgram,
  graph : @publication_host.ClientSerializationPlanGraph,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  capacity : @client_local_host.ClientInstalledWholeSourceCapacity,
  logical : @publication.RunEvidenceValue,
  source_wire : String,
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  @publication_host.ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  let evidence = match
    @publication.admit_run_evidence_value(
      "source_evidence", source_wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication_host.admit_client_serialization_whole_captured_input(
    owner,
    graph,
    source,
    identity,
    @client_local_host.installed_whole_source_original(capacity),
    logical,
    evidence,
    authority_scope_cid,
    started_at,
    completed_at,
  )
}

///|
#export_name("clientProgramAdmitManagedSerializationQueryCapturedInput")
pub fn client_program_admit_managed_serialization_query_captured_input(
  run : @client_local_host.ClientInstalledManagedRun,
  owner : @publication_host.PreparedClientProgram,
  selected : @client_local_host.ClientInstalledManagedSerializationPreparation,
  graph : @publication_host.ClientSerializationPlanGraph,
  capture : @client_row_source_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  source_wire : String,
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  @publication_host.ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  guard @client_local_host.installed_managed_query_serialization_capture_ledger(
      run, owner, selected, capture,
    )
    is Ok(ledger) &&
    @client_row_source_host.row_capture_original_borrowed_requirement(
      capture, ledger,
    )
    is Some(requirement) &&
    @client_row_source_host.row_capture_source(capture) is Ok(source) else {
    return Err(
      @publication.RunEvidenceReferenceMismatch("content_query_source_owner"),
    )
  }
  client_program_admit_serialization_captured_input(
    owner,
    graph,
    source,
    identity,
    requirement,
    logical,
    source_wire,
    authority_scope_cid,
    started_at,
    completed_at,
    None,
  )
}

///|
/// Bind all physically admitted Whole reads to this Run, in checked input
/// order. Neither an equal data packet nor a caller-supplied Ledger is enough.
#export_name("clientProgramAdmitManagedSerializationWholeCapturedInputs")
pub fn client_program_admit_managed_serialization_whole_captured_inputs(
  run : @client_local_host.ClientInstalledManagedRun,
  owner : @publication_host.PreparedClientProgram,
  selected : @client_local_host.ClientInstalledManagedSerializationPreparation,
  graph : @publication_host.ClientSerializationPlanGraph,
  captures : Array[@client_row_source_host.RowSourceCapture],
  identities : Array[@query.CapturedSourceRelationIdentity],
  logical : Array[@publication.RunEvidenceValue],
  source_wires : Array[String],
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  @publication_host.ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  let mismatch = @publication.RunEvidenceReferenceMismatch(
    "content_whole_source_owner",
  )
  guard captures.length() == identities.length() &&
    captures.length() == logical.length() &&
    captures.length() == source_wires.length() &&
    @client_local_host.installed_managed_whole_serialization_capture_ledger(
      run, owner, selected, captures,
    )
    is Ok(ledger) else {
    return Err(mismatch)
  }
  let admitted : Array[@publication_host.ClientSerializationWholeCapture] = []
  for index, wire in source_wires {
    let evidence = match
      @publication.admit_run_evidence_value(
        "source_evidence", wire, 100000, 10000, 100,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    admitted.push({
      capture: captures[index],
      identity: identities[index],
      logical: logical[index],
      source_evidence: evidence,
      started_at,
      completed_at,
    })
  }
  @publication_host.admit_client_serialization_whole_captured_inputs(
    owner, graph, ledger, admitted, authority_scope_cid, 1000000,
  )
}

///|
/// Fixed template DATA enters the SAME Request before its checked demand read.
/// No JSON body, execution authority or independent Resource crosses this port.
#export_name("clientProgramPrepareRequestSerializationOutputDemand")
pub fn client_program_prepare_request_serialization_output_demand(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  compiled : @publication_host.ClientCompiledRun,
  component : @publication_host.ClientSerializationPlanGraph,
  generation_rows : Int,
  generation_bytes : Int,
  generation_nodes : Int,
  generation_depth : Int,
  generation_frames : Int,
  identity_slots : Int,
  reference_bytes : Int,
  reference_nodes : Int,
  reference_depth : Int,
  contract_bytes : Int,
  contract_nodes : Int,
  contract_depth : Int,
  max_result_fields : Int,
  max_result_mapping_work : Int,
  max_result_order_work : Int,
  max_result_workspace_entries : Int,
  max_rows : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_value_depth : Int,
  max_value_work : Int,
  max_wire_bytes : Int,
  max_wire_nodes : Int,
  max_wire_depth : Int,
  max_columns : Int,
  max_order_work : Int,
  max_logical_wire_bytes : Int,
  max_logical_wire_nodes : Int,
  max_logical_wire_depth : Int,
  max_schema_fields : Int,
  max_schema_bytes : Int,
  max_schema_nodes : Int,
  max_schema_depth : Int,
  max_batch_bytes : Int,
) -> Result[
  (@execution.ExecutionCapacity, Int, Int, Int, Int, Int, Int, Int, Int),
  @client_local_host.ClientRequestPreparationIssue,
] {
  let demand = match
    @client_local_host.prepare_request_serialization_output_limits(
      parent,
      input,
      compiled,
      component,
      generation_rows,
      () => {
        guard client_program_effect_input_export_limits(
            max_result_fields, max_result_mapping_work, max_result_order_work, max_result_workspace_entries,
            max_rows, max_value_nodes, max_value_text_bytes, max_value_depth, max_value_work,
            max_wire_bytes, max_wire_nodes, max_wire_depth, max_columns, max_order_work,
            max_logical_wire_bytes, max_logical_wire_nodes, max_logical_wire_depth,
            max_schema_fields, max_schema_bytes, max_schema_nodes, max_schema_depth,
            max_batch_bytes,
          )
          is Some(export_limits) else {
          return None
        }
        Some({
          generation_bytes,
          generation_nodes,
          generation_depth,
          generation_frames,
          identity_slots,
          reference_bytes,
          reference_nodes,
          reference_depth,
          contract_bytes,
          contract_nodes,
          contract_depth,
          export_limits,
        })
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let selected = demand.limits
  let capacity = demand.capacity
  let output = selected.export_limits
  Ok(
    (
      capacity,
      demand.generation_rows,
      selected.generation_bytes,
      output.max_rows,
      output.values.max_nodes,
      output.payload_wire.max_nodes,
      output.logical_wire.max_nodes,
      output.payload_wire.max_columns,
      selected.identity_slots,
    ),
  )
}

///|
#export_name("clientProgramPrepareWholeSerializationSourceCapacity")
pub fn client_program_prepare_whole_serialization_source_capacity(
  prepared : @publication_host.PreparedClientProgram,
  selection : @acquisition.SourceAcquisitionRoute,
  declaration : @client_row_source_host.RowDeclaration,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  provider : @execution.ExecutionCapacity?,
  max_rows : Int,
  max_page_bytes : Int,
  max_page_nodes : Int,
  max_page_depth : Int,
  max_page_rows : Int,
  max_pages : Int,
  serialization : @publication_host.ClientSerializationPlanGraph,
) -> Result[
  @client_local_host.ClientInstalledWholeSourceCapacity,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard selection is @acquisition.WholeInputRoute(original) else {
    return Err(@client_local_host.Unsupported)
  }
  let limits = match
    @client_local_host.installed_source_row_input_policy(
      max_pages, max_rows, max_page_bytes, max_page_nodes, max_page_depth, max_page_rows,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @client_local_host.prepare_installed_whole_source_capacity(
    prepared,
    original,
    declaration,
    contracts,
    limits,
    provider,
    serialization=Some(serialization),
  )
}

///|
/// The caller forwards the SAME opaque Option from the existing pre-module
/// invocation getter. Core checks all originals; no JS tuple is constructed.
#export_name("clientProgramPrepareInstalledManagedWholeSerializationSourcesPlan")
pub fn client_program_prepare_installed_managed_whole_serialization_sources_plan(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  component : @publication_host.ClientSerializationPlanGraph,
  sources : Array[@client_local_host.ClientInstalledWholeSourceCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @client_local_host.ClientInstalledManagedCapturePlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_managed_whole_serialization_sources_plan(
    prepared, request, component, sources, transport_bytes, transport_execution_bytes,
    installed_contracts,
  )
}

///|
#export_name("clientProgramPrepareInstalledManagedQuerySerializationSourcePlan")
pub fn client_program_prepare_installed_managed_query_serialization_source_plan(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  graph : @publication_host.ClientSerializationPlanGraph,
  capacity : @client_local_host.ClientInstalledCaptureCapacity,
  transfer : Int64,
  scratch : Int64,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @client_local_host.ClientInstalledManagedCapturePlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_managed_query_serialization_source_plan(
    prepared, request, graph, capacity, transfer, scratch, contracts,
  )
}
