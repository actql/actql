///|
fn graph_union_carrier() -> @carrier.Carrier {
  let rows = @carrier.rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
  @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    rows,
    rows,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
test "Graph union lowers one ordered finite-list occurrence" {
  let graph = graph_union_carrier()
  let checked = @pipeline.check_carriers(
    cursor("[{\"from\":\"a\",\"union_graphs\":{\"with\":[\"b\",\"a\",\"b\"]}}]"),
    [("a", graph), ("b", graph)],
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
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  assert_true(@lowering_relation.preparation_input_schema(prepared, 0) is None)
  let node = @lowering_relation.node_at(prepared, 0).unwrap()
  assert_eq(@lowering_relation.operation(node), "SGA.union_structural")
  assert_eq(@lowering_relation.input_ids(node), [
    "input_0", "input_1", "input_0", "input_1",
  ])
  assert_true(@lowering_relation.node_relation_schema(node) is None)
  assert_eq(
    @carrier.kind(@lowering_relation.node_output_carrier(node)),
    @carrier.GraphKind,
  )
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 0),
    Some(1),
  )
  let occurrence = @lowering_relation.sequence_canonical_node_at(sequence, 0, 0).unwrap()
  assert_eq(occurrence.operation, "SGA.union_structural")
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"union_graphs_0\",\"in\":[\"input_0\",\"input_1\",\"input_0\",\"input_1\"],\"op\":\"SGA.union_structural\",\"params\":{}}]",
  )
}
