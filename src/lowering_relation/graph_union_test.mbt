///|
test "union lowers one finite ordered fold without deduplicating shared inputs" {
  let graph = graph_match_carrier()
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"g\",\"union_graphs\":{\"with\":[\"peer\",\"g\",\"peer\"]}}]",
    ),
    [("g", graph), ("peer", graph)],
    None,
    None,
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 4000,
    },
  ).unwrap()
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let node = @lowering_relation.node_at(
    @lowering_relation.bound_preparation(owner),
    0,
  ).unwrap()
  assert_eq(@lowering_relation.operation(node), "SGA.union_structural")
  assert_eq(@lowering_relation.node_input_count(node), 4)
  assert_eq(
    @lowering_relation.node_input_target(node, 2),
    Some(@pipeline.Input(0)),
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphUnionStep(union)) else {
    fail("prepared union expected")
  }
  assert_eq(
    @graph.union_input_count(@lowering_relation.graph_union_checked(union)),
    4,
  )
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"union_graphs_0\",\"in\":[\"input_0\",\"input_1\",\"input_0\",\"input_1\"],\"op\":\"SGA.union_structural\",\"params\":{}}]",
  )
}
