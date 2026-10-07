///|
/// The original checked sole-consumer graph admitted for cleanup only. This
/// is not ClientRunMaterials, an executable edge, a borrow or a start claim.
pub struct ClientRecordedSourceCleanup {
  prepared : PreparedClientProgram
  run_definition_cid : String
}

///|
/// Read the original bounded materials, check their Program, and match the
/// complete graph CID to the saved admitted Plan. Do not compile a new Plan
/// or Template, refresh authorization, or acquire Source data.
pub fn admit_recorded_client_source_cleanup_graph(
  materials : String,
  expected_run_definition_cid : String,
  recorded : @publication.RecordedRunPublication,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  limits : ClientValuesRunMaterialsLimits,
  source_ref : String,
  source_contract_cid : String,
) -> Result[ClientRecordedSourceCleanup, ClientRetainedTaskInputIssue] {
  if @publication.recorded_run_publication_run_cid(recorded) !=
    expected_run_definition_cid {
    return Err(InvalidBinding)
  }
  let input = match
    read_client_run_materials_input(materials, expressions, operations, limits) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  if !@publication.recorded_run_publication_has_original_evidence(
      recorded,
      input.prepared_wire,
      input.authorization_wire,
    ) ||
    !@publication.recorded_run_publication_has_original_context(
      recorded,
      input.scope_id,
      input.run_id,
      input.created_at,
      input.valid_until,
    ) {
    return Err(InvalidBinding)
  }
  let prepared = input.prepared
  let graph = prepared_client_graph(prepared)
  if @strategy.graph_task_count(graph) != 2 ||
    @strategy.graph_data_count(graph) != 1 ||
    @strategy.graph_program_has_effects(graph) ||
    prepared_client_acquisition_count(prepared) != 1 ||
    prepared_client_result_count(prepared) != 1 ||
    @strategy.graph_result_task(graph, 0) != Some(1) ||
    @strategy.graph_task_target(graph, 0) is Some(_) ||
    @strategy.graph_task_target(graph, 1) is None {
    return Err(InvalidBinding)
  }
  guard prepared_client_source_evidence_facts(prepared, 0, 0) is Some(facts) else {
    return Err(InvalidBinding)
  }
  let source = @planning.query_source_evidence_fact_values(facts)
  if source[0] != source_ref || source[1] != source_contract_cid {
    return Err(InvalidBinding)
  }
  let selected = match
    issue_prepared_client_task_plan_graph(
      prepared,
      limits.sequence,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  guard parse_plan_identity_value(
      selected.wire,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    )
    is Some(graph_value) else {
    return Err(InvalidBinding)
  }
  let graph_cid = @canonical.cid_value(
    graph_value,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ) catch {
    _ => return Err(InvalidBinding)
  }
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      prepared,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let identity = prepared_client_identity(prepared)
  if !@publication.recorded_run_publication_matches_cleanup_graph(
      recorded,
      identity.program_definition_cid,
      prepared_client_program_semantics_cid(prepared),
      prepared_client_check_environment_cid(prepared),
      identity.parameter_values_cid,
      @publication.run_evidence_value_identity(bindings),
      graph_cid,
    ) {
    return Err(InvalidBinding)
  }
  Ok({ prepared, run_definition_cid: expected_run_definition_cid, })
}

///|
/// Join the already matched original graph to the exact completed occurrences
/// and binding. Physical stop, receiver reclaim and formal release stay with
/// their existing owners; this value cannot issue input to an executor.
pub fn prepare_client_retained_source_cleanup_from_recorded(
  recorded : ClientRecordedSourceCleanup,
  binding : @remote.RemoteInputBinding,
  producer_record : @remote.DispatchRecord,
  producer_evidence : @remote.RemoteExecutionEvidence,
  producer_subject : @remote.RemoteManagedOutputSubject,
  producer_measurement : @remote.RemoteManagedOutputMeasurement,
  consumer_record : @remote.DispatchRecord,
  consumer_evidence : @remote.RemoteExecutionEvidence,
  consumer_subject : @remote.RemoteManagedOutputSubject,
  consumer_measurement : @remote.RemoteManagedOutputMeasurement,
  max_binding_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[ClientRetainedSourceCleanup, ClientRetainedTaskInputIssue] {
  let edge = match
    resolve_client_retained_input_edge(
      recorded.prepared,
      recorded.run_definition_cid,
      1,
      0,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  finish_client_retained_source_cleanup(
    edge, binding, producer_record, producer_evidence, producer_subject, producer_measurement,
    consumer_record, consumer_evidence, consumer_subject, consumer_measurement, max_binding_bytes,
    max_chunks, max_manifest_bytes, max_referenced_bytes,
  )
}
