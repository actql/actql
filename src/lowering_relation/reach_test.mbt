///|
test "Reach lowering retains original operation and selector port" {
  let owner = graph_current_owner(
    "[{\"from\":\"g\",\"reach\":{\"start\":{\"from\":\"selected\",\"id\":\"key\"},\"direction\":\"both\",\"max_depth\":3}}]",
    true,
  )
  let node = node_at(bound_preparation(owner), 0).unwrap()
  assert_eq(operation(node), "SGA.reachable")
  assert_eq(node_input_target(node, 0), Some(@pipeline.Input(0)))
  assert_eq(node_input_target(node, 1), Some(@pipeline.Input(1)))
  assert_true(node_supports_selected_managed_execution(node))
  let sequence = prepare_sequence(owner, sequence_limits()).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"reach_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.reachable\",\"params\":{\"start\":{\"input_port\":1,\"id\":\"key\"},\"direction\":\"both\",\"max_depth\":3}}]",
  )
}
