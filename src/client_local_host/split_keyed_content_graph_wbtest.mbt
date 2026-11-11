///|
// The actual public frontend selects these original checked owners. Diagnostic
// coordinates explain a refusal; they are not acquisition or completion proof.
test "split keyed Content graph keeps the actual public output target" {
  let (value, _, _, _) = split_keyed_content_limits_fixture()
  let graph = @publication_host.prepared_client_graph(value.prepared)
  let owner = @strategy.graph_task_owner(graph, value.task).unwrap()
  let prepared = @lower.bound_preparation(owner)
  let terminal = match @lower.preparation_output_target(prepared) {
    Some(@pipeline.Step(index)) => index
    _ => -1
  }
  let terminal_node = @lower.node_at(prepared, terminal)
    .map(@lower.node_id)
    .unwrap_or("none")
  let issue = match
    @publication_host.issue_prepared_client_acquired_serialization_plan_graph(
      value.prepared,
      value.task,
      value.step,
      3,
      4096,
      1000000,
      @publication_host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ) {
    Ok(_) => None
    Err(InvalidLimits) => Some("InvalidLimits")
    Err(UnsupportedGraph) => Some("UnsupportedGraph")
    Err(UnsupportedOrder) => Some("UnsupportedOrder")
    Err(Policy(_)) => Some("Policy")
    Err(PolicyClosure(_)) => Some("PolicyClosure")
    Err(SourcePolicy(_)) => Some("SourcePolicy")
    Err(Preparation(_)) => Some("Preparation")
    Err(Input(_)) => Some("Input")
    Err(Root(_)) => Some("Root")
    Err(Encoding) => Some("Encoding")
  }
  assert_true(
    issue is None,
    msg="original graph issue=" +
      issue.unwrap_or("none") +
      ", task=" +
      value.task.to_string() +
      ", step=" +
      value.step.to_string() +
      ", unit=" +
      @strategy.graph_task_unit_index(graph, value.task)
      .unwrap_or(-1)
      .to_string() +
      ", inputs=" +
      @strategy.graph_task_input_count(graph, value.task)
      .unwrap_or(-1)
      .to_string() +
      ", selected=" +
      @strategy.graph_task_selected_step(graph, value.task)
      .unwrap_or(-1)
      .to_string() +
      ", terminal=" +
      terminal.to_string() +
      ", terminal_node=" +
      terminal_node,
  )
}
