///|
pub(all) enum ClientValuesExecutablePlanIssue {
  InvalidLimits
  Graph(ClientValuesPlanGraphIssue)
  TaskGraph(ClientTaskPlanGraphIssue)
  Material(ClientExecutionMaterialIssue)
  Facts(ClientPublicationPlanFactIssue)
  Witnesses(ClientPublicationWitnessIssue)
  FactManifest(PlanFactManifestIdentityIssue)
  Encoding
}

///|
pub(all) enum ClientValuesExecutablePlanAdmissionIssue {
  Issue(ClientValuesExecutablePlanIssue)
  MismatchedPlan
}

///|
/// A complete private Plan for one checked, direct REL.values task. Its
/// separate fact manifest must be retained alongside the Plan for admission.
pub struct ClientValuesExecutablePlan {
  wire : String
  cid : String
  fact_manifest_wire : String
  fact_manifest_cid : String
  transformations : Array[ClientResultTransformation]
  graph_logical_cid : String?
}

///|
pub struct ClientTaskExecutablePlan {
  plan : ClientValuesExecutablePlan
}

///|
// Same-construction immutable parts, not a cache, capability or new Owner.
priv struct ClientValuesExecutablePlanParts {
  owner : PreparedClientProgram
  plan : ClientValuesExecutablePlan
  template : @publication.RunEvidenceValue
  fragment : ClientValuesFragmentNode
}

///|
pub fn client_task_executable_plan_wire(
  value : ClientTaskExecutablePlan,
) -> String {
  value.plan.wire
}

///|
pub fn client_task_executable_plan_cid(
  value : ClientTaskExecutablePlan,
) -> String {
  value.plan.cid
}

///|
pub fn client_task_executable_plan_fact_manifest_wire(
  value : ClientTaskExecutablePlan,
) -> String {
  value.plan.fact_manifest_wire
}

///|
pub fn client_values_executable_plan_wire(
  value : ClientValuesExecutablePlan,
) -> String {
  value.wire
}

///|
pub fn client_values_executable_plan_cid(
  value : ClientValuesExecutablePlan,
) -> String {
  value.cid
}

///|
pub fn client_values_executable_plan_fact_manifest_wire(
  value : ClientValuesExecutablePlan,
) -> String {
  value.fact_manifest_wire
}

///|
pub fn client_values_executable_plan_fact_manifest_cid(
  value : ClientValuesExecutablePlan,
) -> String {
  value.fact_manifest_cid
}

///|
fn client_plan_parse_array(
  bodies : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Array[@canonical.CanonicalValue]? {
  let values : Array[@canonical.CanonicalValue] = []
  for body in bodies {
    guard parse_plan_identity_value(body, max_wire_bytes, max_nodes, max_depth)
      is Some(value) else {
      return None
    }
    values.push(value)
  }
  Some(values)
}

///|
fn client_plan_emit_array(
  writer : @encode.Writer,
  values : Array[@canonical.CanonicalValue],
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  for value in values {
    @canonical.emit_value(value, writer)
  }
  @encode.end_array(writer)
}

///|
/// Close the single-step Values graph with all checked Result-publication
/// limits, their witnesses, and exact enforcement bindings. This supported
/// path has no external source, Effect, barrier, or additional profile fact.
/// The result is compilation material, not Run acceptance or Host authority.
pub fn issue_prepared_client_values_executable_plan(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesExecutablePlan, ClientValuesExecutablePlanIssue] {
  issue_prepared_client_values_executable_plan_parts(
    value, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
    max_nodes, max_depth,
  ).map(parts => parts.plan)
}

///|
fn issue_prepared_client_values_executable_plan_parts(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesExecutablePlanParts, ClientValuesExecutablePlanIssue] {
  if max_facts <= 0 ||
    max_witnesses <= 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let (graph, fragment, aoa) = match
    issue_prepared_client_values_plan_graph_parts(
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(parts) => parts
    Err(issue) => return Err(Graph(issue))
  }
  let template = match
    issue_source_free_client_bound_template_from_aoa(
      value, manifests, aoa, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(template) => template
    Err(issue) => return Err(Material(Template(issue)))
  }
  let material = match
    issue_prepared_client_execution_material_with_template(
      value, manifests, template, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  issue_prepared_client_executable_plan_with_parts(
    value,
    graph.wire,
    graph.transformations,
    material.wire,
    max_facts,
    max_witnesses,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map(plan => { owner: value, plan, template, fragment, })
}

///|
/// Seal checked multi-task graph material into the same Executable Plan
/// contract. The resulting Plan still needs source capture, Host policy and
/// Run admission before any provider I/O.
pub fn issue_prepared_client_task_executable_plan(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskExecutablePlan, ClientValuesExecutablePlanIssue] {
  issue_prepared_client_task_plan_parts(
    value, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
    max_nodes, max_depth,
  ).map(parts => parts.0)
}

///|
/// Same issuer and validation order as the public Plan entry. Compilation can
/// retain the immutable graph/material already used by that exact Plan rather
/// than reissue them under the same prepared Owner and limits. No caller can
/// supply wire bytes or substitute an owner through this private composition.
fn issue_prepared_client_task_plan_parts(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientTaskExecutablePlan, ClientExecutionMaterial, ClientTaskPlanGraph),
  ClientValuesExecutablePlanIssue,
] {
  if max_facts <= 0 ||
    max_witnesses <= 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let graph = match
    issue_prepared_client_task_plan_graph(
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(graph) => graph
    Err(issue) => return Err(TaskGraph(issue))
  }
  // The immediately preceding issuer validated this exact immutable graph
  // under the same Owner and limits. The template's public entry performs
  // that same graph check; private composition uses its checked continuation
  // without issuing and discarding a second identical graph.
  let template = match
    issue_client_task_bound_template(
      value, manifests, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(template) => template
    Err(issue) => return Err(Material(TaskTemplate(issue)))
  }
  let material = match
    issue_prepared_client_execution_material_with_template(
      value, manifests, template, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  issue_prepared_client_executable_plan_with_parts(
    value,
    graph.wire,
    graph.transformations,
    material.wire,
    max_facts,
    max_witnesses,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map(plan => ({ plan, }, material, graph))
}

///|
fn issue_prepared_client_executable_plan_with_parts(
  value : PreparedClientProgram,
  graph_wire : String,
  transformations : Array[ClientResultTransformation],
  material_wire : String,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  required_profiles? : Array[(String, String)] = [],
) -> Result[ClientValuesExecutablePlan, ClientValuesExecutablePlanIssue] {
  let facts = match
    issue_prepared_client_publication_plan_facts(
      value, max_facts, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(facts) => facts
    Err(issue) => return Err(Facts(issue))
  }
  let witnesses = match
    issue_prepared_client_publication_witnesses(
      value, max_witnesses, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(witnesses) => witnesses
    Err(issue) => return Err(Witnesses(issue))
  }
  guard client_plan_parse_array(
      facts.entries,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(fact_values) &&
    client_plan_parse_array(facts.limits, max_wire_bytes, max_nodes, max_depth)
    is Some(limit_values) &&
    client_plan_parse_array(
      facts.bindings,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(binding_values) &&
    client_plan_parse_array(
      witnesses.bodies,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(witness_values) else {
    return Err(Encoding)
  }
  guard parse_plan_identity_value(
      graph_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(graph_value) &&
    @canonical.object_field(graph_value, "nodes") is Some(nodes) &&
    @canonical.object_field(graph_value, "data_edges") is Some(edges) &&
    @canonical.object_field(graph_value, "root_refs") is Some(roots) &&
    parse_plan_identity_value(
      material_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(material_value) else {
    return Err(Encoding)
  }
  let facts_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  client_plan_emit_array(facts_writer, fact_values) catch {
    _ => return Err(Encoding)
  }
  let facts_wire = @encode.finish(facts_writer) catch {
    _ => return Err(Encoding)
  }
  let manifest = match
    encode_plan_fact_manifest_identity(
      facts_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(manifest) => manifest
    Err(issue) => return Err(FactManifest(issue))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "bound_witnesses")
    client_plan_emit_array(writer, witness_values)
    @encode.key(writer, "data_edges")
    @canonical.emit_value(edges, writer)
    @encode.key(writer, "execution_material")
    @canonical.emit_value(material_value, writer)
    @encode.key(writer, "limit_bindings")
    client_plan_emit_array(writer, binding_values)
    @encode.key(writer, "nodes")
    @canonical.emit_value(nodes, writer)
    @encode.key(writer, "plan_fact_manifest_cid")
    @encode.string_value(writer, manifest.cid)
    @encode.key(writer, "plan_facts")
    client_plan_emit_array(writer, fact_values)
    @encode.key(writer, "required_profiles")
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
    @encode.key(writer, "resolved_limits")
    client_plan_emit_array(writer, limit_values)
    @encode.key(writer, "root_refs")
    @canonical.emit_value(roots, writer)
    @encode.key(writer, "source_state_requirements")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-executable-plan/0.1")
    @encode.end_object(writer)
    let raw = @encode.finish(writer)
    guard parse_plan_identity_value(raw, max_wire_bytes, max_nodes, max_depth)
      is Some(body) else {
      return Err(Encoding)
    }
    let cid = @canonical.cid_value(body, max_wire_bytes, max_nodes, max_depth)
    guard @canonical.object_with_string_field(body, "executable_plan_cid", cid)
      is Some(complete) else {
      return Err(Encoding)
    }
    let wire = @canonical.stringify_value(
      complete, max_wire_bytes, max_nodes, max_depth,
    )
    Ok({
      wire,
      cid,
      fact_manifest_wire: manifest.wire,
      fact_manifest_cid: manifest.cid,
      transformations: transformations.copy(),
      graph_logical_cid: if transformations.is_empty() {
        None
      } else {
        Some(
          @canonical.cid_value(
            graph_value, max_wire_bytes, max_nodes, max_depth,
          ),
        )
      },
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Reissue every supported Values Plan component before admitting saved
/// material. Host request and Run authorization remain separate checks.
pub fn admit_prepared_client_values_executable_plan(
  value : PreparedClientProgram,
  saved_wire : String,
  saved_fact_manifest_wire : String,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientValuesExecutablePlan,
  ClientValuesExecutablePlanAdmissionIssue,
] {
  let issued = match
    issue_prepared_client_values_executable_plan(
      value, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(plan) => plan
    Err(issue) => return Err(Issue(issue))
  }
  if saved_wire != issued.wire ||
    saved_fact_manifest_wire != issued.fact_manifest_wire {
    return Err(MismatchedPlan)
  }
  Ok(issued)
}
