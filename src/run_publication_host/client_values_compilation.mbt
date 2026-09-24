///|
pub(all) enum ClientValuesCompilationIssue {
  Plan(ClientValuesExecutablePlanIssue)
  Material(ClientExecutionMaterialIssue)
  AoA(ClientValuesAoAIdentityIssue)
  Fragment(ClientValuesFragmentIssue)
  Template(@publication.RunEvidenceValueIssue)
  CompiledPlan(@publication.PublicationContractIssue)
}

///|
pub(all) enum ClientValuesCompilationAdmissionIssue {
  Issue(ClientValuesCompilationIssue)
  MismatchedCompilation
}

///|
/// Owner-issued private compilation evidence for one direct Values Program.
/// Host policy and request authorization are separate from this compilation.
pub struct ClientValuesCompilation {
  plan : ClientValuesExecutablePlan
  template : @publication.RunEvidenceValue
  compiled_plan : @publication.PublicationContract
  fragment : ClientValuesFragmentNode
  result_names : Array[String]
}

///|
pub fn client_values_compilation_plan(
  value : ClientValuesCompilation,
) -> ClientValuesExecutablePlan {
  value.plan
}

///|
pub fn client_values_compilation_template(
  value : ClientValuesCompilation,
) -> @publication.RunEvidenceValue {
  value.template
}

///|
pub fn client_values_compilation_compiled_plan(
  value : ClientValuesCompilation,
) -> @publication.PublicationContract {
  value.compiled_plan
}

///|
/// The one checked Plan node and declared Result inventory. These are
/// compilation coordinates, not dispatch authority or Site selection.
pub fn client_values_compilation_plan_node_id(
  value : ClientValuesCompilation,
) -> String {
  client_values_fragment_node_id(value.fragment)
}

///|
pub fn client_values_compilation_output_contract_cid(
  value : ClientValuesCompilation,
) -> String {
  client_values_fragment_output_contract_cid(value.fragment)
}

///|
pub fn client_values_compilation_result_names(
  value : ClientValuesCompilation,
) -> Array[String] {
  value.result_names.copy()
}

///|
/// Bind the complete Executable Plan CID, checked Program semantics and AoA
/// pipeline to compiler provenance. The admitted envelope is then the source
/// of receipt version fields; publication cannot substitute current versions.
pub fn issue_prepared_client_values_compilation(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesCompilation, ClientValuesCompilationIssue] {
  let plan = match
    issue_prepared_client_values_executable_plan(
      value, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(plan) => plan
    Err(issue) => return Err(Plan(issue))
  }
  let material = match
    issue_prepared_client_values_execution_material(
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
  let aoa = match
    issue_prepared_client_values_aoa_identity(
      value, 0, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(aoa) => aoa
    Err(issue) => return Err(AoA(issue))
  }
  let identity = prepared_client_identity(value)
  let body = "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"" +
    @environment.compiler_version_token() +
    "\",\"aoa_ir_version\":\"" +
    @environment.compiler_aoa_ir_version_token() +
    "\",\"executable_plan_cid\":\"" +
    plan.cid +
    "\",\"program_definition_cid\":\"" +
    identity.program_definition_cid +
    "\",\"program_semantics_cid\":\"" +
    prepared_client_program_semantics_cid(value) +
    "\",\"aoa_contract_cid\":\"" +
    @environment.compiler_aoa_contract_cid() +
    "\",\"aoa_logical_cid\":\"" +
    client_values_aoa_identity_cid(aoa) +
    "\"}"
  let compiled_plan = match
    @publication.seal_publication_contract(
      "compiled_plan", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(compiled) => compiled
    Err(issue) => return Err(CompiledPlan(issue))
  }
  let fragment = match
    issue_prepared_client_values_fragment(
      value, 0, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(fragment) => fragment
    Err(issue) => return Err(Fragment(issue))
  }
  let result_names : Array[String] = []
  for index in 0..<prepared_client_result_count(value) {
    guard prepared_client_result_name(value, index) is Some(name) else {
      return Err(Plan(Encoding))
    }
    result_names.push(name)
  }
  Ok({ plan, template, compiled_plan, fragment, result_names, })
}

///|
/// Recompile and compare all three retained identities before admitting a
/// saved Values compilation. This does not authorize a Run or provider I/O.
pub fn admit_prepared_client_values_compilation(
  value : PreparedClientProgram,
  saved_plan_wire : String,
  saved_fact_manifest_wire : String,
  saved_template_wire : String,
  saved_compiled_plan_wire : String,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesCompilation, ClientValuesCompilationAdmissionIssue] {
  let issued = match
    issue_prepared_client_values_compilation(
      value, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(compiled) => compiled
    Err(issue) => return Err(Issue(issue))
  }
  if saved_plan_wire != issued.plan.wire ||
    saved_fact_manifest_wire != issued.plan.fact_manifest_wire ||
    saved_template_wire != @publication.run_evidence_value_json(issued.template) ||
    saved_compiled_plan_wire !=
    @publication.publication_contract_json(issued.compiled_plan) {
    return Err(MismatchedCompilation)
  }
  Ok(issued)
}
