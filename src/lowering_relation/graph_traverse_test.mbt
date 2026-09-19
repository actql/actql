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
