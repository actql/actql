///|
pub(all) enum ClientBoundTemplateIssue {
  ValuesGraph(ClientValuesPlanGraphIssue)
  OpaqueBindings(ClientEmptyInvocationBindingsIssue)
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Issue the source-free Bound Invocation Template from one checked Program.
/// This only covers Programs without opaque bindings or required profiles.
/// Plan issuance still needs physical contract and complete fact admission.
pub fn issue_prepared_source_free_client_bound_template(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientBoundTemplateIssue] {
  match
    issue_prepared_client_values_plan_graph(
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(ValuesGraph(issue))
  }
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      value, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(bindings) => bindings
    Err(issue) => return Err(OpaqueBindings(issue))
  }
  let identity = prepared_client_identity(value)
  let body = "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    identity.program_definition_cid +
    "\",\"parameter_values_cid\":\"" +
    identity.parameter_values_cid +
    "\",\"invocation_bindings_cid\":\"" +
    @publication.run_evidence_value_identity(bindings) +
    "\",\"check_environment_cid\":\"" +
    prepared_client_check_environment_cid(value) +
    "\",\"grammar_manifest_cid\":\"" +
    manifests.grammar_manifest_cid +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    manifests.barrier_contract_manifest_cid +
    "\",\"source_evidence\":\"unbound\"}"
  match
    @publication.seal_run_evidence_value(
      "bound_invocation_template", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(template) => Ok(template)
    Err(issue) => Err(Evidence(issue))
  }
}
