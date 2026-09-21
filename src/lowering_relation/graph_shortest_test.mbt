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
test "Graph shortest path exposes one typed kernel view" {
  let source = "[{\"from\":\"g\",\"shortest_path\":{" +
    "\"source\":1,\"target\":2,\"direction\":\"out\"," +
    "\"max_hops\":3,\"edge_types\":[\"owns\"]}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, false),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphShortestStep(shortest)) else {
    fail("missing shortest-path step")
  }
  assert_true(
    @lowering_relation.graph_shortest_endpoint_single(shortest, @schema.Left)
    is Some(_),
  )
  assert_true(
    @lowering_relation.graph_shortest_endpoint_single(shortest, @schema.Right)
    is Some(_),
  )
  assert_eq(
    @lowering_relation.graph_shortest_endpoint_id_count(shortest, @schema.Left),
    0,
  )
  assert_eq(
    @lowering_relation.graph_shortest_endpoint_relation_field(
      shortest,
      @schema.Left,
    ),
    None,
  )
  assert_true(
    @lowering_relation.graph_shortest_endpoint_predicate(shortest, @schema.Left)
    is None,
  )
  assert_eq(
    @lowering_relation.graph_shortest_endpoint_input_port(
      shortest,
      @schema.Left,
    ),
    None,
  )
  assert_eq(
    @lowering_relation.graph_shortest_selection(shortest),
    @graph.EachPair,
  )
  assert_eq(
    @lowering_relation.graph_shortest_direction(shortest),
    @graph.Outgoing,
  )
  assert_eq(@lowering_relation.graph_shortest_max_hops(shortest), Some(3))
  assert_eq(@lowering_relation.graph_shortest_type_count(shortest), Some(1))
  assert_eq(
    @lowering_relation.graph_shortest_type_at(shortest, 0),
    Some("owns"),
  )
  assert_eq(@lowering_relation.graph_shortest_weight(shortest), None)
  assert_eq(@lowering_relation.graph_shortest_output_guard(shortest), None)
  assert_eq(
    @schema.field_count(
      @lowering_relation.graph_shortest_output_schema(shortest),
    ),
    6,
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
