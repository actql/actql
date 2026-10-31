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
  issue_prepared_client_serialization_compilation_owned(
    owner, component, manifests, max_facts, max_witnesses, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
/// Observe only the original final Plan writers on this same serialization
/// compiler invocation. No component, Run identity or numeric bound is issued
/// a second time. The output survives typed failure and synchronous unwind.
pub fn observe_prepared_client_serialization_plan_encoding(
  owner : PreparedClientProgram,
  component : ClientSerializationPlanGraph,
  manifests : ClientCompilationManifests,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  nodes_out~ : Ref[Int64],
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  nodes_out.val = 0L
  issue_prepared_client_serialization_compilation_owned(
    owner,
    component,
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
fn issue_prepared_client_serialization_compilation_owned(
  owner : PreparedClientProgram,
  component : ClientSerializationPlanGraph,
  manifests : ClientCompilationManifests,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  plan_encoding_nodes_out? : Ref[Int64]? = None,
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
      result_plans=component.graph.result_plans,
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
      result_plans=component.graph.result_plans,
      plan_encoding_nodes_out~,
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
