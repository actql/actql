///|
/// Close the checked pure prefix and model barrier with the existing task
/// compilation owner. No model response, capture or future Invocation CID
/// enters this Plan. The Host must still admit physical model dependencies
/// and current egress before dispatching the retained barrier.
pub fn issue_prepared_client_infer_compilation(
  value : PreparedClientProgram,
  graph : ClientInferPlanGraph,
  manifests : ClientCompilationManifests,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  issue_prepared_client_infer_compilation_owned(
    value, graph, manifests, max_facts, max_witnesses, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
/// Observe the SAME final Plan hash/text writers for the Request's existing
/// work receipt. Failed construction retains its consumed node prefix in this
/// original cell; neither a count nor completion grants physical Model work.
pub fn observe_prepared_client_infer_plan_encoding(
  value : PreparedClientProgram,
  graph : ClientInferPlanGraph,
  manifests : ClientCompilationManifests,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  nodes_out~ : Ref[Int64],
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  nodes_out.val = 0L
  issue_prepared_client_infer_compilation_owned(
    value,
    graph,
    manifests,
    max_facts,
    max_witnesses,
    max_wire_bytes,
    max_nodes,
    max_depth,
    plan_encoding_nodes_out=Some(nodes_out),
  )
}

///|
fn issue_prepared_client_infer_compilation_owned(
  value : PreparedClientProgram,
  graph : ClientInferPlanGraph,
  manifests : ClientCompilationManifests,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  plan_encoding_nodes_out? : Ref[Int64]? = None,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  if !physical_equal(value, graph.owner) {
    return Err(ForeignInferOwner)
  }
  let material = match
    issue_prepared_client_infer_execution_material(
      value, graph, manifests, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Material(issue))
  }
  let plan = match
    issue_prepared_client_executable_plan_with_parts(
      value,
      graph.graph.wire,
      graph.graph.transformations,
      material,
      max_facts,
      max_witnesses,
      max_wire_bytes,
      max_nodes,
      max_depth,
      required_profiles=client_infer_required_profiles(graph),
      result_plans=graph.graph.result_plans,
      plan_encoding_nodes_out~,
    ) {
    Ok(value) => { plan: value, }
    Err(issue) => return Err(Plan(issue))
  }
  let template = match
    @publication.admit_run_evidence_value(
      "bound_invocation_template",
      material.invocation_template_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Template(issue))
  }
  finish_client_task_compilation(
    value,
    plan,
    template,
    graph.graph,
    max_wire_bytes,
    max_nodes,
    max_depth,
    infer=Some(graph),
    serialization=graph.serialization,
  )
}
