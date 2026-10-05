///|
test "current subgraph lowers full typed identities without a tuple fallback" {
  let id = graph_match_identity(2)
  let source = "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[" +
    id +
    "]}}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_current_owner(source, false),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphSubgraphStep(view)) else {
    fail("prepared subgraph")
  }
  assert_eq(@lowering_relation.graph_subgraph_literal_id_count(view), Some(1))
  assert_eq(
    graph_match_checked_value_wire(
      @lowering_relation.graph_subgraph_literal_id_at(view, 0).unwrap(),
    ),
    id,
  )
  assert_eq(
    @lowering_relation.graph_subgraph_relation_selector_field(view),
    None,
  )
  assert_eq(
    @lowering_relation.graph_subgraph_literal_edge_predicate(view),
    Some(true),
  )
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"subgraph_0\",\"in\":[\"input_0\"],\"op\":\"SGA.subgraph\",\"params\":{\"nodes\":{\"ids\":[" +
    id +
    "]},\"edges\":{\"body\":true,\"op\":\"literal\"}}}]",
  )
}

///|
test "current subgraph lowers Relation selector and edge predicate on exact ports" {
  let source = "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"from\":\"selected\",\"id\":\"key\"},\"edges\":\"active\"}}]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_current_owner(source, true),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphSubgraphStep(view)) else {
    fail("prepared Relation subgraph")
  }
  assert_eq(@lowering_relation.graph_subgraph_literal_id_count(view), None)
  assert_eq(
    @lowering_relation.graph_subgraph_relation_selector_field(view),
    Some(Unqualified("key")),
  )
  assert_true(@lowering_relation.graph_subgraph_edge_predicate(view) is Some(_))
  assert_eq(
    @lowering_relation.graph_subgraph_literal_edge_predicate(view),
    None,
  )
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"subgraph_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.subgraph\",\"params\":{\"nodes\":{\"input_port\":1,\"id\":\"key\"},\"edges\":{\"body\":\"active\",\"op\":\"field\"}}}]",
  )
}
