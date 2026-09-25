///|
/// One checked source-free Values task bound to an admitted Run Definition.
/// This is compilation provenance, not Site selection or execution authority.
struct ClientValuesRunBinding {
  run_definition_cid : String
  task_key : String
  result_name : String
  program_definition_cid : String
  parameter_values_cid : String
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
    ) ||
    !@publication.run_definition_has_empty_initial_input_artifact_set(
      run_definition,
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
    program_definition_cid: identity.program_definition_cid,
    parameter_values_cid: identity.parameter_values_cid,
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

///|
/// Host-selected physical Site coordinates. Selection does not grant Site
/// access; current authority, grant, budget and movement checks remain with
/// the installing Host and the common Remote runtime.
pub(all) struct ClientValuesSiteSelection {
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  obligations_cid : String
  budget_cid : String
  evidence_issuer_capability_cid : String
  grant_cid : String
}

///|
pub(all) enum ClientValuesDispatchIssue {
  ForeignRequest
  UnsupportedSite
  Protocol(@remote.DispatchIssue)
}

///|
/// Derive the exact task and source-free input from a checked Run. The caller
/// provides only physical Site selection and one dispatch occurrence. This
/// operation does not reserve the Run or perform I/O; the durable Coordinator
/// owner must atomically admit the returned request before transmission.
pub fn prepare_source_free_client_values_dispatch(
  binding : ClientValuesRunBinding,
  request : ClientRequestIdentity,
  task_attempt : Int,
  dispatch_id : String,
  selected : ClientValuesSiteSelection,
) -> Result[@remote.DispatchRequest, ClientValuesDispatchIssue] {
  if client_request_program_cid(request) != binding.program_definition_cid ||
    client_request_parameters_cid(request) != binding.parameter_values_cid ||
    client_request_input_cid(request) != source_free_caller_input_intent_cid() {
    return Err(ForeignRequest)
  }
  if selected.connector_registration != "local" {
    return Err(UnsupportedSite)
  }
  let input = match @remote.prepare_remote_input_binding("{}", 2) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match
    @remote.prepare_dispatch_request(
      client_request_authority_scope_cid(request),
      binding.run_definition_cid,
      binding.task_key,
      task_attempt,
      dispatch_id,
      selected.site_key,
      selected.site_generation,
      selected.runtime_bundle_cid,
      selected.connector_registration,
      selected.connector_revision,
      selected.strategy_revision,
      @remote.remote_input_binding_cid(input),
      selected.obligations_cid,
      selected.budget_cid,
      selected.evidence_issuer_capability_cid,
      selected.grant_cid,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Protocol(issue))
  }
}
