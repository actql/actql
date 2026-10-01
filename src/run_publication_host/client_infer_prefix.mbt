///|
/// Select the checked Relation owner consumed by the initial source-free
/// Infer path. Both compilation and execution use this exact selection;
/// equal source text, row values, or model identities cannot replace it.
/// Other task/input shapes need their own admitted acquisition connection.
pub fn client_infer_prefix_owner(
  value : PreparedClientProgram,
  task : Int,
  infer_step : Int,
) -> @lower.BoundPrepared? {
  guard task == 0 &&
    @strategy.graph_task_count(value.graph) == 1 &&
    @strategy.graph_task_selected_step(value.graph, task) is None &&
    @strategy.graph_task_prefix_end(value.graph, task) is None &&
    infer_step > 0 &&
    @strategy.graph_task_owner(value.graph, task) is Some(owner) &&
    @lower.preparation_input_count(@lower.bound_preparation(owner)) == 0 &&
    @lower.node_at(@lower.bound_preparation(owner), infer_step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(_) &&
    @lower.node_input_target(node, 0) == Some(@pipeline.Step(infer_step - 1)) &&
    @lower.preparation_carrier_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(infer_step - 1),
    )
    is Some(input) &&
    @carrier.kind(input) == RelationKind else {
    return None
  }
  Some(owner)
}

///|
pub(all) enum ClientInferHostCapacityIssue {
  UnsupportedProgram
  Capacity(@environment.CapacityIssue)
  MissingItemCeiling
}

///|
/// Read the actual checked Host policy, never an adapter default. This is one
/// physical admission candidate, not the complete inference Plan envelope.
pub fn prepared_client_infer_host_item_ceiling(
  value : PreparedClientProgram,
  step : Int,
) -> Result[Int64, ClientInferHostCapacityIssue] {
  if client_infer_prefix_owner(value, 0, step) is None {
    return Err(UnsupportedProgram)
  }
  let capacity = match
    @environment.read_capacity(
      @checked.checked_environment(@strategy.graph_program(value.graph)),
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  guard @capacity_policy.ceiling(
      @environment.capacity_policy(capacity),
      "max_infer_items",
    )
    is Some(ceiling) else {
    return Err(MissingItemCeiling)
  }
  Ok(@capacity_policy.ceiling_value(ceiling))
}
