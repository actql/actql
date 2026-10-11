///|
test "Shortest lowering binds repeated Relation selectors to separate ordered ports" {
  let owner = graph_current_owner(
    "[{\"from\":\"g\",\"shortest_path\":{\"source\":{\"from\":\"selected\",\"id\":\"key\"},\"target\":{\"from\":\"selected\",\"id\":\"key\"},\"selection\":\"each_pair\",\"direction\":\"out\",\"max_hops\":3}}]",
    true,
  )
  let node = node_at(bound_preparation(owner), 0).unwrap()
  assert_eq(operation(node), "SGA.shortest_path")
  assert_eq(node_input_count(node), 3)
  assert_eq(node_input_target(node, 0), Some(@pipeline.Input(0)))
  assert_eq(node_input_target(node, 1), Some(@pipeline.Input(1)))
  assert_eq(node_input_target(node, 2), Some(@pipeline.Input(1)))
  assert_true(node_supports_selected_managed_execution(node))
  assert_true(node_accepts_managed_relation_view(node, 1))
  assert_true(node_accepts_managed_relation_view(node, 2))
  let sequence = prepare_sequence(owner, sequence_limits()).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"shortest_path_0\",\"in\":[\"input_0\",\"input_1\",\"input_1\"],\"op\":\"SGA.shortest_path\",\"params\":{\"source\":{\"input_port\":1,\"id\":\"key\"},\"target\":{\"input_port\":2,\"id\":\"key\"},\"selection\":\"each_pair\",\"direction\":\"out\",\"max_hops\":3}}]",
  )
}

///|
test "Shortest source and target predicates lower as distinct existing expression roots" {
  let owner = graph_current_owner(
    "[{\"from\":\"g\",\"shortest_path\":{\"source\":{\"where\":\"active\"},\"target\":{\"where\":\"false\"},\"selection\":\"nearest_pair\",\"direction\":\"both\",\"max_hops\":2}}]",
    false,
  )
  let sequence = prepare_sequence(owner, sequence_limits()).unwrap()
  guard sequence_step(sequence, 0) is Some(GraphTraverseStep(prepared)) else {
    fail("shared path preparation")
  }
  assert_true(graph_traverse_start_predicate(prepared) is Some(_))
  assert_true(graph_traverse_target_predicate(prepared) is Some(_))
  assert_true(graph_traverse_shortest(prepared) is Some(_))
  assert_true(graph_traverse_emits_paths(prepared))
  let writer = @encode.writer(20000, 2000, 100)
  emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"shortest_path_0\",\"in\":[\"input_0\"],\"op\":\"SGA.shortest_path\",\"params\":{\"source\":{\"where\":{\"body\":\"active\",\"op\":\"field\"}},\"target\":{\"where\":{\"body\":false,\"op\":\"literal\"}},\"selection\":\"nearest_pair\",\"direction\":\"both\",\"max_hops\":2}}]",
  )
}
