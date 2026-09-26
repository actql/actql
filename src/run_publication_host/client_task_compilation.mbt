///|
pub struct ClientTaskCompilation {
  plan : ClientTaskExecutablePlan
  template : @publication.RunEvidenceValue
  compiled_plan : @publication.PublicationContract
  result_names : Array[String]
}

///|
pub(all) enum ClientTaskCompilationIssue {
  Plan(ClientValuesExecutablePlanIssue)
  Material(ClientExecutionMaterialIssue)
  Graph(ClientTaskPlanGraphIssue)
  Template(@publication.RunEvidenceValueIssue)
  CompiledPlan(@publication.PublicationContractIssue)
  Encoding
}

///|
pub fn client_task_compilation_plan(
  value : ClientTaskCompilation,
) -> ClientTaskExecutablePlan {
  value.plan
}

///|
pub fn client_task_compilation_template(
  value : ClientTaskCompilation,
) -> @publication.RunEvidenceValue {
  value.template
}

///|
pub fn client_task_compilation_compiled_plan(
  value : ClientTaskCompilation,
) -> @publication.PublicationContract {
  value.compiled_plan
}

///|
pub fn client_task_compilation_result_names(
  value : ClientTaskCompilation,
) -> Array[String] {
  value.result_names.copy()
}

///|
/// Compile the checked task graph and all named Result occurrences. The
/// AoA logical identity is the canonical graph of its typed task fragments,
/// edges and roots; the Executable Plan additionally binds material and
/// enforcement facts. Site selection and captured values remain outside it.
pub fn issue_prepared_client_task_compilation(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  let plan = match
    issue_prepared_client_task_executable_plan(
      value, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(plan) => plan
    Err(issue) => return Err(Plan(issue))
  }
  let material = match
    issue_prepared_client_task_execution_material(
      value, manifests, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  let template = match
    @publication.admit_run_evidence_value(
      "bound_invocation_template",
      material.invocation_template_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(template) => template
    Err(issue) => return Err(Template(issue))
  }
  let graph = match
    issue_prepared_client_task_plan_graph(
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(graph) => graph
    Err(issue) => return Err(Graph(issue))
  }
  finish_client_task_compilation(
    value, plan, template, graph, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn finish_client_task_compilation(
  value : PreparedClientProgram,
  plan : ClientTaskExecutablePlan,
  template : @publication.RunEvidenceValue,
  graph : ClientTaskPlanGraph,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  guard parse_plan_identity_value(
      graph.wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(graph_value) else {
    return Err(Encoding)
  }
  let aoa_logical_cid = @canonical.cid_value(
    graph_value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let identity = prepared_client_identity(value)
  let body = "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"" +
    @environment.compiler_version_token() +
    "\",\"aoa_ir_version\":\"" +
    @environment.compiler_aoa_ir_version_token() +
    "\",\"executable_plan_cid\":\"" +
    client_task_executable_plan_cid(plan) +
    "\",\"program_definition_cid\":\"" +
    identity.program_definition_cid +
    "\",\"program_semantics_cid\":\"" +
    prepared_client_program_semantics_cid(value) +
    "\",\"aoa_contract_cid\":\"" +
    @environment.compiler_aoa_contract_cid() +
    "\",\"aoa_logical_cid\":\"" +
    aoa_logical_cid +
    "\"}"
  let compiled_plan = match
    @publication.seal_publication_contract(
      "compiled_plan", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(compiled) => compiled
    Err(issue) => return Err(CompiledPlan(issue))
  }
  let result_names : Array[String] = []
  for index in 0..<prepared_client_result_count(value) {
    guard prepared_client_result_name(value, index) is Some(name) else {
      return Err(Encoding)
    }
    result_names.push(name)
  }
  Ok({ plan, template, compiled_plan, result_names, })
}
