///|
pub(all) enum ClientBoundTemplateIssue {
  ValuesGraph(ClientValuesPlanGraphIssue)
  UnsupportedPipeline
  OpaqueBindings(ClientEmptyInvocationBindingsIssue)
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
pub(all) enum ClientTaskBoundTemplateIssue {
  Graph(ClientTaskPlanGraphIssue)
  OpaqueBindings(ClientEmptyInvocationBindingsIssue)
  Evidence(@publication.RunEvidenceValueIssue)
  Encoding
}

///|
pub(all) enum ClientInferBoundTemplateIssue {
  InvalidLimits
  ForeignGraph
  Template(ClientTaskBoundTemplateIssue)
}

///|
/// Bind the existing Infer profile to the actual prepared Program. This is
/// compilation material, not executable admission or model-egress authority.
/// The graph's unresolved physical dependencies remain explicit.
pub fn issue_prepared_client_infer_bound_template(
  value : PreparedClientProgram,
  graph : ClientInferPlanGraph,
  manifests : ClientCompilationManifests,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientInferBoundTemplateIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(value, graph.owner) {
    return Err(ForeignGraph)
  }
  issue_client_task_bound_template(
    value,
    manifests,
    max_wire_bytes,
    max_nodes,
    max_depth,
    required_profiles=[
      (
        "actql-infer/0.1",
        @environment.compiler_inference_barrier_contract_cid(),
      ),
    ],
  ).map_err(issue => Template(issue))
}

///|
/// Bind an arbitrary checked Effect-free task graph with no opaque
/// declarations. Physical source evidence is supplied by the Observation Set
/// after capture; this template does not authorize a provider read.
pub fn issue_prepared_client_task_bound_template(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientTaskBoundTemplateIssue] {
  match
    issue_prepared_client_task_plan_graph(
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Graph(issue))
  }
  issue_client_task_bound_template(
    value, manifests, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn issue_client_task_bound_template(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  required_profiles? : Array[(String, String)] = [],
) -> Result[@publication.RunEvidenceValue, ClientTaskBoundTemplateIssue] {
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      value, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(bindings) => bindings
    Err(issue) => return Err(OpaqueBindings(issue))
  }
  let profiles = try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_array(writer)
    for (profile_id, contract_cid) in required_profiles {
      @encode.begin_object(writer)
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, contract_cid)
      @encode.key(writer, "profile_id")
      @encode.string_value(writer, profile_id)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
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
    "\",\"required_profile_contracts\":" +
    profiles +
    "," +
    "\"barrier_contract_manifest_cid\":\"" +
    manifests.barrier_contract_manifest_cid +
    "\",\"source_evidence\":\"unbound\"}"
  @publication.seal_run_evidence_value(
    "bound_invocation_template", body, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Evidence(issue))
}

///|
/// Issue the source-free Bound Invocation Template from one checked Program.
/// This covers one Values-rooted task without opaque bindings or required
/// profiles.
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
  let aoa = match
    issue_prepared_client_values_aoa_identity(
      value, 0, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(aoa) => aoa
    Err(_) => return Err(UnsupportedPipeline)
  }
  guard parse_plan_identity_value(
      client_values_aoa_identity_wire(aoa),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(pipeline) &&
    @canonical.object_field(pipeline, "steps") is Some(@canonical.Array(steps)) else {
    return Err(UnsupportedPipeline)
  }
  let steps = @canonical.array_values(steps)
  if steps.is_empty() {
    return Err(UnsupportedPipeline)
  }
  guard @canonical.object_field(steps[0], "op")
    is Some(@canonical.String("REL.values")) else {
    return Err(UnsupportedPipeline)
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
