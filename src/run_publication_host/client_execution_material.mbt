///|
pub(all) enum ClientExecutionMaterialIssue {
  InvalidLimits
  Template(ClientBoundTemplateIssue)
  TaskTemplate(ClientTaskBoundTemplateIssue)
  Bindings(ClientEmptyInvocationBindingsIssue)
  Program(ClientIdentityMaterialIssue)
  ResultPlan(ClientResultPlanIssue)
  DuplicateResultName
  Encoding
  InferTemplate(ClientInferBoundTemplateIssue)
}

///|
/// Retain an Infer-aware template and the existing checked Result/material
/// identities. Physical limits, egress, call slots and captured observations
/// still have to be admitted before the Host may issue an executable Run.
pub fn issue_prepared_client_infer_execution_material(
  value : PreparedClientProgram,
  graph : ClientInferPlanGraph,
  manifests : ClientCompilationManifests,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExecutionMaterial, ClientExecutionMaterialIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let template = match
    issue_prepared_client_infer_bound_template(
      value, graph, manifests, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(InferTemplate(issue))
  }
  issue_prepared_client_execution_material_with_template(
    value, manifests, template, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
pub(all) enum ClientExecutionMaterialAdmissionIssue {
  Issue(ClientExecutionMaterialIssue)
  MismatchedMaterial
}

///|
/// Private compilation material for a checked Program. This is only one
/// required member of an Executable Plan, never execution authority itself.
pub struct ClientExecutionMaterial {
  wire : String
  invocation_template_cid : String
  invocation_template_wire : String
}

///|
pub fn client_execution_material_wire(
  value : ClientExecutionMaterial,
) -> String {
  value.wire
}

///|
pub fn client_execution_material_template_cid(
  value : ClientExecutionMaterial,
) -> String {
  value.invocation_template_cid
}

///|
pub fn client_execution_material_template_wire(
  value : ClientExecutionMaterial,
) -> String {
  value.invocation_template_wire
}

///|
/// Bind source, parameter and Result identities to the exact compiler
/// manifests, AoA contract and checked template. The Result map is issued
/// from checked declarations, rather than accepted as caller-supplied CIDs.
pub fn issue_prepared_client_values_execution_material(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExecutionMaterial, ClientExecutionMaterialIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let template = match
    issue_prepared_source_free_client_bound_template(
      value, manifests, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(template) => template
    Err(issue) => return Err(Template(issue))
  }
  issue_prepared_client_execution_material_with_template(
    value, manifests, template, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
pub fn issue_prepared_client_task_execution_material(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExecutionMaterial, ClientExecutionMaterialIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let template = match
    issue_prepared_client_task_bound_template(
      value, manifests, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(template) => template
    Err(issue) => return Err(TaskTemplate(issue))
  }
  issue_prepared_client_execution_material_with_template(
    value, manifests, template, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn issue_prepared_client_execution_material_with_template(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  template : @publication.RunEvidenceValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  effect_plan_cids? : Array[(String, String)] = [],
) -> Result[ClientExecutionMaterial, ClientExecutionMaterialIssue] {
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      value, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(bindings) => bindings
    Err(issue) => return Err(Bindings(issue))
  }
  let program_wire = match
    emit_prepared_client_semantic_program(
      value, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(Program(issue))
  }
  guard parse_plan_identity_value(
      program_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(program) else {
    return Err(Encoding)
  }
  let identity = prepared_client_identity(value)
  let names : Array[String] = []
  let result_cids : Array[String] = []
  for index in 0..<prepared_client_result_count(value) {
    let result = match
      issue_prepared_client_result_plan(
        value, index, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(result) => result
      Err(issue) => return Err(ResultPlan(issue))
    }
    let name = client_result_plan_name(result)
    if names.contains(name) {
      return Err(DuplicateResultName)
    }
    names.push(name)
    result_cids.push(client_result_plan_cid(result))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "aoa_contract_cid")
    @encode.string_value(writer, @environment.compiler_aoa_contract_cid())
    @encode.key(writer, "barrier_contract_manifest_cid")
    @encode.string_value(writer, manifests.barrier_contract_manifest_cid)
    @encode.key(writer, "check_environment_cid")
    @encode.string_value(writer, prepared_client_check_environment_cid(value))
    @encode.key(writer, "effect_plan_logical_cids")
    @encode.begin_object(writer)
    for (name, cid) in effect_plan_cids {
      @encode.key(writer, name)
      @encode.string_value(writer, cid)
    }
    @encode.end_object(writer)
    @encode.key(writer, "grammar_manifest_cid")
    @encode.string_value(writer, manifests.grammar_manifest_cid)
    @encode.key(writer, "invocation_binding_names")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "invocation_bindings_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(bindings),
    )
    @encode.key(writer, "invocation_template_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(template),
    )
    @encode.key(writer, "parameter_names")
    @encode.begin_array(writer)
    for name in @syntax.program_parameter_names(value.source) {
      @encode.string_value(writer, name)
    }
    @encode.end_array(writer)
    @encode.key(writer, "parameter_values_cid")
    @encode.string_value(writer, identity.parameter_values_cid)
    @encode.key(writer, "program")
    @canonical.emit_value(program, writer)
    @encode.key(writer, "program_definition_cid")
    @encode.string_value(writer, identity.program_definition_cid)
    @encode.key(writer, "result_plan_logical_cids")
    @encode.begin_object(writer)
    for index in 0..<names.length() {
      @encode.key(writer, names[index])
      @encode.string_value(writer, result_cids[index])
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    let raw = @encode.finish(writer)
    guard parse_plan_identity_value(raw, max_wire_bytes, max_nodes, max_depth)
      is Some(body) else {
      return Err(Encoding)
    }
    let wire = @canonical.stringify_value(
      body, max_wire_bytes, max_nodes, max_depth,
    )
    Ok({
      wire,
      invocation_template_cid: @publication.run_evidence_value_identity(
        template,
      ),
      invocation_template_wire: @publication.run_evidence_value_json(template),
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Replan saved material with the checked Program and current compiler pins.
/// A complete Executable Plan admission must additionally recheck graph,
/// facts, limits and Host authority before provider access or Run creation.
pub fn admit_prepared_client_values_execution_material(
  value : PreparedClientProgram,
  saved_wire : String,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExecutionMaterial, ClientExecutionMaterialAdmissionIssue] {
  let issued = match
    issue_prepared_client_values_execution_material(
      value, manifests, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(material) => material
    Err(issue) => return Err(Issue(issue))
  }
  if saved_wire != issued.wire {
    return Err(MismatchedMaterial)
  }
  Ok(issued)
}

///|
/// Rebuild the Infer-aware material under the same prepared Program and
/// current compiler manifests; saved profile or Result maps are not trusted.
/// This does not admit the graph's unresolved execution dependencies.
pub fn admit_prepared_client_infer_execution_material(
  value : PreparedClientProgram,
  graph : ClientInferPlanGraph,
  saved_wire : String,
  manifests : ClientCompilationManifests,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExecutionMaterial, ClientExecutionMaterialAdmissionIssue] {
  let issued = match
    issue_prepared_client_infer_execution_material(
      value, graph, manifests, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Issue(issue))
  }
  if saved_wire != issued.wire {
    return Err(MismatchedMaterial)
  }
  Ok(issued)
}
