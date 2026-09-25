///|
pub struct ClientTaskRunBinding {
  run_definition_cid : String
  result_names : Array[String]
}

///|
pub(all) enum ClientTaskRunBindingIssue {
  ForeignRun
  UnsupportedProgram
}

///|
/// Bind the admitted Definition to the exact checked task compilation. The
/// empty initial Artifact set covers caller-supplied Run-start captures only;
/// a later provider acquisition must still produce its own Observation Set.
pub fn bind_client_task_run(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
) -> Result[ClientTaskRunBinding, ClientTaskRunBindingIssue] {
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
      client_task_compilation_compiled_plan(compilation),
    ) ||
    @publication.run_publication_template_cid(admission) !=
    @publication.run_evidence_value_identity(
      client_task_compilation_template(compilation),
    ) ||
    !@publication.run_definition_has_empty_initial_input_artifact_set(
      run_definition,
    ) {
    return Err(ForeignRun)
  }
  let graph = prepared_client_graph(prepared)
  if @strategy.graph_task_count(graph) == 0 ||
    @strategy.graph_program_has_effects(graph) ||
    @strategy.graph_result_count(graph) == 0 ||
    !@strategy.graph_ordered_inputs_complete(graph) {
    return Err(UnsupportedProgram)
  }
  let names = client_task_compilation_result_names(compilation)
  if names.length() != @strategy.graph_result_count(graph) {
    return Err(UnsupportedProgram)
  }
  for index in 0..<names.length() {
    if @strategy.graph_result_name(graph, index) != Some(names[index]) {
      return Err(UnsupportedProgram)
    }
  }
  Ok({
    run_definition_cid: @publication.publication_contract_identity(
      run_definition,
    ),
    result_names: names,
  })
}

///|
pub fn client_task_run_binding_definition_cid(
  binding : ClientTaskRunBinding,
) -> String {
  binding.run_definition_cid
}

///|
pub fn client_task_run_binding_result_names(
  binding : ClientTaskRunBinding,
) -> Array[String] {
  binding.result_names.copy()
}
