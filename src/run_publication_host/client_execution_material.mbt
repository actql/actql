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
    value,
    manifests,
    template,
    max_wire_bytes,
    max_nodes,
    max_depth,
    result_plans=graph.graph.result_plans,
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
  owner : PreparedClientProgram
  body : @canonical.CanonicalValue
  wire_bytes : Int
  wire_nodes : Int
  wire_depth : Int
  wire : String
  invocation_template_cid : String
  invocation_template_wire : String
}

///|
// The tree and extent come from this exact material's completed canonical
// writer. Reuse never grants authority or accepts caller-provided JSON.
fn client_execution_material_body(
  value : ClientExecutionMaterial,
  owner : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @canonical.CanonicalValue? {
  if !physical_equal(value.owner, owner) ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 ||
    value.wire_bytes > max_wire_bytes ||
    value.wire_nodes > max_nodes ||
    value.wire_depth > max_depth {
    return None
  }
  Some(value.body)
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
  let (graph, _, aoa) = match
    issue_prepared_client_values_plan_graph_parts(
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(parts) => parts
    Err(issue) => return Err(Template(ValuesGraph(issue)))
  }
  let template = match
    issue_source_free_client_bound_template_from_aoa(
      value, manifests, aoa, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(template) => template
    Err(issue) => return Err(Template(issue))
  }
  issue_prepared_client_execution_material_with_template(
    value,
    manifests,
    template,
    max_wire_bytes,
    max_nodes,
    max_depth,
    result_plans=graph.result_plans,
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
  // The public template entry validates this same graph and discards it.
  // Keep its Result originals here; do not construct them again in material.
  let result_plans = match
    issue_prepared_client_task_plan_graph(
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(graph) => graph.result_plans
    Err(issue) => return Err(TaskTemplate(Graph(issue)))
  }
  let template = match
    issue_client_task_bound_template(
      value, manifests, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(template) => template
    Err(issue) => return Err(TaskTemplate(issue))
  }
  issue_prepared_client_execution_material_with_template(
    value,
    manifests,
    template,
    max_wire_bytes,
    max_nodes,
    max_depth,
    result_plans~,
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
  result_plans~ : Array[ClientResultPlanIdentity],
  effect_plan_cids? : Array[(String, String)] = [],
  effect_target_selections? : ClientEffectUpdateTargetSelections? = None,
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
  let mut program = parse_plan_identity_value(
    program_wire, max_wire_bytes, max_nodes, max_depth,
  )
  if program is None {
    return Err(Encoding)
  }
  let names : Array[String] = []
  let result_cids : Array[String] = []
  for index in 0..<prepared_client_result_count(value) {
    let result = match
      client_material_result_plan(
        value, index, result_plans, max_wire_bytes, max_nodes, max_depth, issue_prepared_client_result_plan,
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
  let mut selection_value = match effect_target_selections {
    None => None
    Some(selections) => {
      guard parse_plan_identity_value(
          selections.wire,
          max_wire_bytes,
          max_nodes,
          max_depth,
        )
        is Some(body) else {
        return Err(Encoding)
      }
      Some(body)
    }
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    emit_client_execution_material_body(
      writer,
      value,
      manifests,
      program.unwrap(),
      @publication.run_evidence_value_identity(bindings),
      @publication.run_evidence_value_identity(template),
      names,
      result_cids,
      effect_plan_cids,
      selection_value,
      @canonical.emit_value,
      (value, out) => @encode.string_value(out, value),
    )
    // The synchronous writer has finished borrowing the local parsed Program.
    // Cut that original alias before the new material parser constructs its
    // independent retained tree; neither wire nor Prepared is reconstructed.
    program = None
    // The body writer has finished using this temporary parsed selection.
    selection_value = None
    let raw = @encode.finish(writer)
    guard parse_plan_identity_value(raw, max_wire_bytes, max_nodes, max_depth)
      is Some(body) else {
      return Err(Encoding)
    }
    let canonical = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @canonical.emit_value(body, canonical)
    let (wire, wire_bytes, wire_nodes, wire_depth) = @encode.finish_text_usage(
      canonical,
    )
    Ok({
      owner: value,
      body,
      wire_bytes,
      wire_nodes,
      wire_depth,
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

///|
// This is the actual material reconstruction boundary. The original issuer
// is supplied as a static pure function, not an external Host callback.
fn client_material_result_plan(
  value : PreparedClientProgram,
  result : Int,
  original_plans : Array[ClientResultPlanIdentity],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  issue : (PreparedClientProgram, Int, Int, Int, Int) -> Result[
    ClientResultPlanIdentity,
    ClientResultPlanIssue,
  ],
) -> Result[ClientResultPlanIdentity, ClientResultPlanIssue] {
  for original in original_plans {
    if physical_equal(original.owner, value) &&
      original.result == result &&
      original.codec_limits == (max_wire_bytes, max_nodes, max_depth) {
      return Ok(original)
    }
  }
  issue(value, result, max_wire_bytes, max_nodes, max_depth)
}

///|
// The real material and the text-free construction quote share this exact
// protocol body. Typed identities are emitted only by the actual issuer;
// the measurement interpretation cannot produce a representative identity.
fn[P, C] emit_client_execution_material_body(
  writer : @encode.Writer,
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  program : P,
  invocation_bindings_cid : C,
  invocation_template_cid : C,
  names : Array[String],
  result_cids : Array[C],
  effect_plan_cids : Array[(String, String)],
  effect_target_selections : @canonical.CanonicalValue?,
  emit_program : (P, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  let identity = prepared_client_identity(value)
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
  if effect_target_selections is Some(body) {
    @encode.key(writer, "effect_target_selections")
    @canonical.emit_value(body, writer)
  }
  @encode.key(writer, "grammar_manifest_cid")
  @encode.string_value(writer, manifests.grammar_manifest_cid)
  @encode.key(writer, "invocation_binding_names")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.key(writer, "invocation_bindings_cid")
  emit_cid(invocation_bindings_cid, writer)
  @encode.key(writer, "invocation_template_cid")
  emit_cid(invocation_template_cid, writer)
  @encode.key(writer, "parameter_names")
  @encode.begin_array(writer)
  for name in @syntax.program_parameter_names(value.source) {
    @encode.string_value(writer, name)
  }
  @encode.end_array(writer)
  @encode.key(writer, "parameter_values_cid")
  @encode.string_value(writer, identity.parameter_values_cid)
  @encode.key(writer, "program")
  emit_program(program, writer)
  @encode.key(writer, "program_definition_cid")
  @encode.string_value(writer, identity.program_definition_cid)
  @encode.key(writer, "result_plan_logical_cids")
  @encode.begin_object(writer)
  for index in 0..<names.length() {
    @encode.key(writer, names[index])
    emit_cid(result_cids[index], writer)
  }
  @encode.end_object(writer)
  @encode.end_object(writer)
}

///|
/// Measure the original pure compilation material without constructing its
/// semantic Program wire/tree, Result Plans, template, bindings or their CIDs.
/// Those component extents and the measuring workspace remain separate parts
/// of the same Request owner's complete construction overlap.
pub fn measure_prepared_client_execution_material(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), ClientExecutionMaterialIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let program = try {
    let out = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    @syntax.emit_metadata_stripped_program(value.source, out)
    @encode.finish_measurement_usage(out)
  } catch {
    _ => return Err(Encoding)
  }
  let names : Array[String] = []
  let result_cids : Array[Unit] = []
  for result in 0..<prepared_client_result_count(value) {
    let (_, _, name, _, _, _) = match
      client_result_plan_originals(value, result) {
      Err(issue) => return Err(ResultPlan(issue))
      Ok(original) => original
    }
    if names.contains(name) {
      return Err(DuplicateResultName)
    }
    names.push(name)
    result_cids.push(())
  }
  try {
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_execution_material_body(
      writer,
      value,
      manifests,
      program,
      (),
      (),
      names,
      result_cids,
      [],
      None,
      (value, out) => @encode.emit_measurement(out, value),
      measure_client_fragment_cid,
    )
    Ok(@encode.finish_measurement_usage(writer))
  } catch {
    _ => Err(Encoding)
  }
}
