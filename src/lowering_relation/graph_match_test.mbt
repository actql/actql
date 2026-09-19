///|
fn graph_match_carrier() -> @carrier.Carrier {
  let boolean = @contract.primitive(BooleanType, nullable=true)
  let properties = @carrier.rows(
    [(@schema.Unqualified("active"), Some(boolean))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let names = @carrier.graph_row_names(
    @schema.Unqualified("node_id"),
    @schema.Unqualified("source_id"),
    @schema.Unqualified("target_id"),
    Some(@schema.Unqualified("edge_type")),
    max_name_bytes=100,
  ).unwrap()
  @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    properties,
    properties,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
    label_contract=Some(@contract.primitive(StringType, nullable=true)),
  ).unwrap()
}

///|
fn graph_match_owner(source : String) -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor(source),
    [("g", graph_match_carrier())],
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
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn graph_match_wire(source : String) -> String raise {
  let sequence = @lowering_relation.prepare_sequence(
    graph_match_owner(source),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  @encode.finish(writer)
}

///|
test "Graph node match retains repeated typed IDs and projection order" {
  assert_eq(
    graph_match_wire(
      "[{\"from\":\"g\",\"match_nodes\":{\"ids\":[2,10,2],\"fields\":[\"node_id\",\"active\"]}}]",
    ),
    "[{\"id\":\"match_nodes_0\",\"in\":[\"input_0\"],\"op\":\"SGA.match_nodes\",\"params\":{\"fields\":[\"node_id\",\"active\"],\"ids\":[2,10,2]}}]",
  )
}

///|
test "Graph edge match lowers checked predicate references" {
  assert_eq(
    graph_match_wire(
      "[{\"from\":\"g\",\"match_edges\":{\"types\":[\"owns\",\"owns\"],\"where\":\"active\",\"fields\":[\"source_id\",\"edge_type\"]}}]",
    ),
    "[{\"id\":\"match_edges_0\",\"in\":[\"input_0\"],\"op\":\"SGA.match_edges\",\"params\":{\"fields\":[\"source_id\",\"edge_type\"],\"types\":[\"owns\",\"owns\"],\"where\":{\"body\":\"active\",\"op\":\"field\"}}}]",
  )
}

///|
test "Graph match preparation enforces field and type name budgets" {
  let owner = graph_match_owner(
    "[{\"from\":\"g\",\"match_edges\":{\"types\":[\"owns\"],\"fields\":[\"source_id\"]}}]",
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_name_bytes: 13,
    })
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_name_bytes: 12,
    })
    is Err(
      @lowering_relation.GraphMatchFailure(
        0,
        @lowering_relation.GraphMatchPreparationLimit
      )
    ),
  )
}
