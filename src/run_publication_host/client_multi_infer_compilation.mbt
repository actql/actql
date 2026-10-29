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
  let graph = match
    issue_prepared_client_multi_infer_task_plan_graph(
      value, components, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(graph) => graph
    Err(issue) => return Err(Graph(issue))
  }
  let profiles = [
    ("actql-infer/0.1", @environment.compiler_inference_barrier_contract_cid()),
  ]
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
  )
}
