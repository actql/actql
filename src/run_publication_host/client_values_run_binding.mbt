///|
/// One checked source-free Values task bound to an admitted Run Definition.
/// This is compilation provenance, not Site selection or execution authority.
struct ClientValuesRunBinding {
  run_definition_cid : String
  task_key : String
  result_name : String
}

///|
pub(all) enum ClientValuesRunBindingIssue {
  ForeignRun
  UnsupportedProgram
}

///|
pub fn bind_source_free_client_values_run(
  prepared : PreparedClientProgram,
  compilation : ClientValuesCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
) -> Result[ClientValuesRunBinding, ClientValuesRunBindingIssue] {
  let identity = prepared_client_identity(prepared)
  if @publication.check_run_publication_program_binding(
      admission,
      run_definition,
      identity.program_definition_cid,
      prepared_client_program_semantics_cid(prepared),
      prepared_client_check_environment_cid(prepared),
    )
    is Err(_) ||
    @publication.run_publication_compiled_plan_cid(admission) !=
    @publication.publication_contract_identity(
      client_values_compilation_compiled_plan(compilation),
    ) ||
    @publication.run_publication_template_cid(admission) !=
    @publication.run_evidence_value_identity(
      client_values_compilation_template(compilation),
    ) {
    return Err(ForeignRun)
  }
  let graph = prepared_client_graph(prepared)
  if @strategy.graph_task_count(graph) != 1 ||
    @strategy.graph_task_input_count(graph, 0) != Some(0) ||
    prepared_client_result_count(prepared) != 1 {
    return Err(UnsupportedProgram)
  }
  guard prepared_client_result_name(prepared, 0) is Some(result_name) else {
    return Err(UnsupportedProgram)
  }
  if client_values_compilation_result_names(compilation) != [result_name] {
    return Err(UnsupportedProgram)
  }
  Ok({
    run_definition_cid: @publication.publication_contract_identity(
      run_definition,
    ),
    task_key: client_values_compilation_plan_node_id(compilation),
    result_name,
  })
}

///|
pub fn client_values_run_binding_definition_cid(
  binding : ClientValuesRunBinding,
) -> String {
  binding.run_definition_cid
}

///|
pub fn client_values_run_binding_task_key(
  binding : ClientValuesRunBinding,
) -> String {
  binding.task_key
}

///|
pub fn client_values_run_binding_result_name(
  binding : ClientValuesRunBinding,
) -> String {
  binding.result_name
}
