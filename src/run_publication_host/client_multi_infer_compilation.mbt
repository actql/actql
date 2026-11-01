///|
/// Compile all checked Model occurrences into the original task Run. Every
/// barrier remains an acquisition component, with the normal graph validating
/// producers, port contracts and Named Result transformations.
pub fn issue_prepared_client_multi_infer_compilation(
  value : PreparedClientProgram,
  components : Array[ClientInferPlanGraph],
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  issue_prepared_client_multi_infer_compilation_owned(
    value, components, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
/// Same compiler and final Plan writers; this is not full compiler work.
pub fn observe_prepared_client_multi_infer_plan_encoding(
  value : PreparedClientProgram,
  components : Array[ClientInferPlanGraph],
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  nodes_out~ : Ref[Int64],
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  nodes_out.val = 0L
  issue_prepared_client_multi_infer_compilation_owned(
    value,
    components,
    manifests,
    sequence_limits,
    max_facts,
    max_witnesses,
    max_wire_bytes,
    max_nodes,
    max_depth,
    plan_encoding_nodes_out=Some(nodes_out),
  )
}

///|
fn[T] client_multi_infer_required_profiles(
  contract : T,
  content_contract? : T? = None,
) -> Array[(String, T)] {
  let profiles = [("actql-infer/0.1", contract)]
  if content_contract is Some(original) {
    profiles.push(("actql-content/0.1", original))
  }
  profiles
}

///|
fn issue_prepared_client_multi_infer_compilation_owned(
  value : PreparedClientProgram,
  components : Array[ClientInferPlanGraph],
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  plan_encoding_nodes_out? : Ref[Int64]? = None,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  // Retain the same singular Content original when the composed compiler has
  // one. Multiple components remain in their original infer graphs; a singular
  // getter must not choose one arbitrarily. This issues no generation or Scope.
  let mut serialization = None
  let mut content_count = 0
  for component in components {
    if component.serialization is Some(original) {
      content_count += 1
      serialization = if content_count == 1 { Some(original) } else { None }
    }
  }
  let graph = match
    issue_prepared_client_multi_infer_task_plan_graph(
      value, components, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(graph) => graph
    Err(issue) => return Err(Graph(issue))
  }
  let profiles = client_multi_infer_required_profiles(
    @environment.compiler_inference_barrier_contract_cid(),
    content_contract=if content_count == 0 {
      None
    } else {
      Some(@environment.compiler_content_barrier_contract_cid())
    },
  )
  let template = match
    issue_client_task_bound_template(
      value,
      manifests,
      max_wire_bytes,
      max_nodes,
      max_depth,
      required_profiles=profiles,
    ) {
    Ok(template) => template
    Err(issue) => return Err(Material(TaskTemplate(issue)))
  }
  let material = match
    issue_prepared_client_execution_material_with_template(
      value,
      manifests,
      template,
      max_wire_bytes,
      max_nodes,
      max_depth,
      result_plans=graph.result_plans,
    ) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  let plan = match
    issue_prepared_client_executable_plan_with_parts(
      value,
      graph.wire,
      graph.transformations,
      material,
      max_facts,
      max_witnesses,
      max_wire_bytes,
      max_nodes,
      max_depth,
      required_profiles=profiles,
      result_plans=graph.result_plans,
      plan_encoding_nodes_out~,
    ) {
    Ok(plan) => { plan, }
    Err(issue) => return Err(Plan(issue))
  }
  finish_client_task_compilation(
    value,
    plan,
    template,
    graph,
    max_wire_bytes,
    max_nodes,
    max_depth,
    infers=components,
    serialization~,
  )
}
