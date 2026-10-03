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
fn graph_union_property_carrier() -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=false)
  let properties = @carrier.rows(
    [(@schema.Unqualified("score"), Some(number))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  @carrier.graph(
    number,
    properties,
    properties,
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

///|
test "Graph union emits checked property merge laws" {
  let graph = graph_union_property_carrier()
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"a\",\"union_graphs\":{\"with\":[\"b\"],\"merge\":{\"node_properties\":{\"score\":\"number_max\"},\"edge_properties\":{\"score\":\"number_sum\"}}}}]",
    ),
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
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphUnionStep(union)) else {
    fail("prepared graph union")
  }
  assert_eq(@lowering_relation.graph_union_input_count(union), 2)
  assert_eq(
    @lowering_relation.graph_union_fold_strategy_count(union, 0, @schema.Left),
    Some(1),
  )
  assert_eq(
    @lowering_relation.graph_union_fold_strategy_name(union, 0, @schema.Left, 0),
    Some("score"),
  )
  assert_eq(
    @lowering_relation.graph_union_fold_strategy_kind(union, 0, @schema.Left, 0),
    Some(@graph.NumberMax),
  )
  assert_true(
    @lowering_relation.graph_union_fold_output(union, 0)
    is Some(@carrier.GraphValue(_)),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"union_graphs_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.union_structural\",\"params\":{\"merge\":{\"edge_properties\":{\"score\":\"number_sum\"},\"node_properties\":{\"score\":\"number_max\"}}}}]",
  )
}

///|
test "Structural graph lowering retains binary operation and merge laws" {
  let graph = graph_union_property_carrier()
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"a\",\"subtract_graphs\":{\"with\":\"b\",\"merge\":{\"node_properties\":{\"score\":\"number_max\"},\"edge_properties\":{\"score\":\"number_sum\"}}}}]",
    ),
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
  let node = @lowering_relation.node_at(prepared, 0).unwrap()
  assert_eq(@lowering_relation.operation(node), "SGA.diff_structural")
  assert_eq(@lowering_relation.input_ids(node), ["input_0", "input_1"])
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphStructuralStep(structural)) else {
    fail("prepared graph subtraction")
  }
  assert_eq(
    @lowering_relation.graph_structural_strategy_count(
      structural,
      @schema.Right,
    ),
    1,
  )
  assert_eq(
    @lowering_relation.graph_structural_strategy_name(
      structural,
      @schema.Right,
      0,
    ),
    Some("score"),
  )
  assert_eq(
    @lowering_relation.graph_structural_strategy_kind(
      structural,
      @schema.Right,
      0,
    ),
    Some(@graph.NumberSum),
  )
  assert_true(
    @lowering_relation.graph_structural_output(structural)
    is @carrier.GraphValue(_),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"subtract_graphs_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.diff_structural\",\"params\":{\"merge\":{\"edge_properties\":{\"score\":\"number_sum\"},\"node_properties\":{\"score\":\"number_max\"}}}}]",
  )
}
