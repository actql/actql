///|
test "Graph traversal retains homogeneous bounds and edge types" {
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[2]},\"direction\":\"out\",\"edge_types\":[\"owns\"],\"min_hops\":1,\"max_hops\":3,\"emit\":\"nodes\",\"max_output_rows\":10}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, false),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"traverse_0\",\"in\":[\"input_0\"],\"op\":\"SGA.traverse\",\"params\":{\"start\":{\"ids\":[2]},\"direction\":\"out\",\"edge_types\":[\"owns\"],\"min_hops\":1,\"max_hops\":3,\"emit\":\"nodes\",\"max_output_rows\":10}}]",
  )
}

///|
test "Graph traversal exposes a complete homogeneous kernel view" {
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[2,2]},\"direction\":\"out\",\"edge_types\":[\"owns\",\"owns\"],\"min_hops\":1,\"max_hops\":3,\"emit\":\"nodes\",\"max_output_rows\":10}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, false),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphTraverseStep(view)) else {
    fail("expected prepared graph traversal")
  }
  assert_false(@lowering_relation.graph_traverse_patterned(view))
  assert_false(@lowering_relation.graph_traverse_emits_paths(view))
  assert_eq(@lowering_relation.graph_traverse_bounds(view), Some((1L, 3L)))
  assert_eq(@lowering_relation.graph_traverse_output_guard(view), Some(10L))
  assert_eq(@lowering_relation.graph_traverse_start_id_count(view), 2)
  assert_true(
    @lowering_relation.graph_traverse_start_id_at(view, 0).unwrap().value
    is @value.Number(2.0),
  )
  assert_eq(@lowering_relation.graph_traverse_start_relation_field(view), None)
  assert_true(@lowering_relation.graph_traverse_start_predicate(view) is None)
  assert_eq(@lowering_relation.graph_traverse_hop_count(view), 1)
  assert_eq(
    @lowering_relation.graph_traverse_hop_direction(view, 0),
    Some(@graph.Outgoing),
  )
  assert_eq(@lowering_relation.graph_traverse_hop_type_count(view, 0), Some(2))
  assert_eq(
    @lowering_relation.graph_traverse_hop_type_at(view, 0, 1),
    Some("owns"),
  )
  assert_eq(
    @schema.field_count(@lowering_relation.graph_traverse_output_schema(view)),
    3,
  )
}

///|
test "Graph traversal retains patterned predicates and selector port" {
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"selected\",\"id\":\"key\"},\"hops\":[{\"direction\":\"both\",\"edge_types\":[\"owns\"],\"edge_where\":\"active\",\"node_where\":\"active\"}],\"emit\":\"paths\"}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, true),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(30000, 3000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"traverse_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.traverse\",\"params\":{\"start\":{\"input_port\":1,\"id\":\"key\"},\"hops\":[{\"direction\":\"both\",\"edge_types\":[\"owns\"],\"edge_where\":{\"body\":\"active\",\"op\":\"field\"},\"node_where\":{\"body\":\"active\",\"op\":\"field\"}}],\"emit\":\"paths\"}}]",
  )
}

///|
test "Graph traversal exposes patterned predicates and relation selector" {
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"selected\",\"id\":\"key\"},\"hops\":[{\"direction\":\"both\",\"edge_types\":[\"owns\"],\"edge_where\":\"active\",\"node_where\":\"active\"}],\"emit\":\"paths\"}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_subgraph_owner(source, true),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphTraverseStep(view)) else {
    fail("expected prepared graph traversal")
  }
  assert_true(@lowering_relation.graph_traverse_patterned(view))
  assert_true(@lowering_relation.graph_traverse_emits_paths(view))
  assert_eq(@lowering_relation.graph_traverse_bounds(view), None)
  assert_eq(
    @lowering_relation.graph_traverse_start_relation_field(view),
    Some(@schema.Unqualified("key")),
  )
  assert_true(
    @lowering_relation.graph_traverse_hop_edge_predicate(view, 0) is Some(_),
  )
  assert_true(
    @lowering_relation.graph_traverse_hop_node_predicate(view, 0) is Some(_),
  )
  assert_eq(
    @lowering_relation.graph_traverse_hop_direction(view, 0),
    Some(@graph.Both),
  )
  assert_eq(
    @schema.field_count(@lowering_relation.graph_traverse_output_schema(view)),
    5,
  )
}

///|
test "Graph traversal prepares type and selector names before emission" {
  let source = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"selected\",\"id\":\"key\"},\"direction\":\"out\",\"edge_types\":[\"owns\"],\"min_hops\":0,\"max_hops\":1,\"emit\":\"nodes\"}}]"
  let owner = graph_subgraph_owner(source, true)
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_name_bytes: 7,
    })
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_name_bytes: 6,
    })
    is Err(
      @lowering_relation.GraphTraverseFailure(
        0,
        @lowering_relation.GraphTraversePreparationLimit
      )
    ),
  )
}
