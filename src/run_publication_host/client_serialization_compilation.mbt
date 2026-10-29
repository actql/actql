///|
/// Close the checked Content component under the existing task compilation
/// owner. No bytes, ContentRef or future invocation identity enter this Plan.
/// The Host still has to reserve inputs/Store and complete trusted generation.
pub fn issue_prepared_client_serialization_compilation(
  owner : PreparedClientProgram,
  component : ClientSerializationPlanGraph,
  manifests : ClientCompilationManifests,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  if !physical_equal(owner, component.owner) {
    return Err(ForeignSerializationOwner)
  }
  let profiles = [
    ("actql-content/0.1", @environment.compiler_content_barrier_contract_cid()),
  ]
  let template = match
    issue_client_task_bound_template(
      owner,
      manifests,
      max_wire_bytes,
      max_nodes,
      max_depth,
      required_profiles=profiles,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Material(TaskTemplate(issue)))
  }
  let material = match
    issue_prepared_client_execution_material_with_template(
      owner,
      manifests,
      template,
      max_wire_bytes,
      max_nodes,
      max_depth,
      result_plans=component.graph.transformations,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Material(issue))
  }
  let plan = match
    issue_prepared_client_executable_plan_with_parts(
      owner,
      component.graph.wire,
      component.graph.transformations,
      material,
      max_facts,
      max_witnesses,
      max_wire_bytes,
      max_nodes,
      max_depth,
      required_profiles=profiles,
    ) {
    Ok(plan) => { plan, }
    Err(issue) => return Err(Plan(issue))
  }
  finish_client_task_compilation(
    owner,
    plan,
    template,
    component.graph,
    max_wire_bytes,
    max_nodes,
    max_depth,
    serialization=Some(component),
  )
}
