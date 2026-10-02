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
      material.wire,
      max_facts,
      max_witnesses,
      max_wire_bytes,
      max_nodes,
      max_depth,
      required_profiles=[
        (
          "actql-infer/0.1",
          @environment.compiler_inference_barrier_contract_cid(),
        ),
      ],
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
  )
}
