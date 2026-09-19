///|
test "Graph shortest path retains typed scalar endpoints" {
  let source = "[{\"from\":\"g\",\"shortest_path\":{\"source\":1,\"target\":2,\"direction\":\"out\",\"max_hops\":3,\"edge_types\":[\"owns\"]}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, false),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"shortest_path_0\",\"in\":[\"input_0\"],\"op\":\"SGA.shortest_path\",\"params\":{\"source\":1,\"target\":2,\"selection\":\"each_pair\",\"direction\":\"out\",\"max_hops\":3,\"edge_types\":[\"owns\"],\"weight\":null}}]",
  )
}

///|
test "Graph shortest path retains repeated selector input positions" {
  let source = "[{\"from\":\"g\",\"shortest_path\":{\"source\":{\"from\":\"selected\",\"id\":\"key\"},\"target\":{\"from\":\"selected\",\"id\":\"key\"},\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, true),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(30000, 3000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"shortest_path_0\",\"in\":[\"input_0\",\"input_1\",\"input_1\"],\"op\":\"SGA.shortest_path\",\"params\":{\"source\":{\"input_port\":1,\"id\":\"key\"},\"target\":{\"input_port\":2,\"id\":\"key\"},\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2,\"weight\":null}}]",
  )
}

///|
test "Graph shortest path lowers endpoint predicates independently" {
  let source = "[{\"from\":\"g\",\"shortest_path\":{\"source\":{\"where\":\"active\"},\"target\":{\"where\":\"active\"},\"selection\":\"nearest_pair\",\"direction\":\"in\",\"max_hops\":1}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, false),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(30000, 3000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"shortest_path_0\",\"in\":[\"input_0\"],\"op\":\"SGA.shortest_path\",\"params\":{\"source\":{\"where\":{\"body\":\"active\",\"op\":\"field\"}},\"target\":{\"where\":{\"body\":\"active\",\"op\":\"field\"}},\"selection\":\"nearest_pair\",\"direction\":\"in\",\"max_hops\":1,\"weight\":null}}]",
  )
}
