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
