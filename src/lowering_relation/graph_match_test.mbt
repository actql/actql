///|
fn graph_match_carrier() -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=false)
  let boolean = @contract.primitive(BooleanType, nullable=true)
  let properties = @carrier.rows(
    [(@schema.Unqualified("active"), Some(boolean))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let node = @carrier.graph_node_definition(
    "N",
    [number],
    properties,
    ["Node"],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.graph_node_definition(
    "E",
    [number],
    properties,
    ["owns"],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  @carrier.graph(
    "sha256:" + "0".repeat(64),
    [node],
    [@carrier.graph_edge_definition(edge, "N", "N").unwrap()],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
}

///|
fn graph_match_identity(key : Int) -> String {
  "{\"definition\":\"N\",\"domain\":\"sha256:" +
  "0".repeat(64) +
  "\",\"key\":[" +
  key.to_string() +
  "],\"key_types\":[{\"kind\":\"number\"}]}"
}

///|
fn graph_match_checked_value_wire(value : @value.CheckedValue) -> String raise {
  let writer = @encode.writer(10000, 1000, 100)
  @value.emit_checked_wire_value(value, writer)
  @encode.finish(writer)
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
test "definition-selected node MATCH retains repeated typed IDs and projection order" {
  let ids = "[" +
    graph_match_identity(2) +
    "," +
    graph_match_identity(10) +
    "," +
    graph_match_identity(2) +
    "]"
  assert_eq(
    graph_match_wire(
      "[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"label\":\"Node\",\"bindings\":{\"identity\":\"node_id\"},\"ids\":" +
      ids +
      ",\"fields\":[\"node_id\",\"active\"]}}]",
    ),
    "[{\"id\":\"match_nodes_0\",\"in\":[\"input_0\"],\"op\":\"SGA.match_nodes\",\"params\":{\"definition\":\"N\",\"label\":\"Node\",\"bindings\":{\"identity\":\"node_id\"},\"fields\":[\"node_id\",\"active\"],\"ids\":" +
    "[{\"$json\":" +
    graph_match_identity(2) +
    "},{\"$json\":" +
    graph_match_identity(10) +
    "},{\"$json\":" +
    graph_match_identity(2) +
    "}]" +
    "}}]",
  )
}

///|
test "current MATCH exposes one checked definition scope and typed kernel view" {
  let ids = "[" +
    graph_match_identity(2) +
    "," +
    graph_match_identity(10) +
    "," +
    graph_match_identity(2) +
    "]"
  let sequence = @lowering_relation.prepare_sequence(
    graph_match_owner(
      "[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"node_id\"},\"ids\":" +
      ids +
      ",\"fields\":[\"node_id\",\"active\"]}}]",
    ),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphMatchStep(view)) else {
    fail("expected prepared keyed MATCH")
  }
  assert_true(@lowering_relation.graph_match_nodes(view))
  assert_false(@lowering_relation.graph_match_has_predicate(view))
  assert_eq(@lowering_relation.graph_match_property_definition(view), 0)
  assert_eq(
    @lowering_relation.graph_match_graph_binding(view, "identity"),
    Some(@schema.Unqualified("node_id")),
  )
  assert_eq(@lowering_relation.graph_match_graph_binding(view, "source"), None)
  assert_eq(@lowering_relation.graph_match_field_count(view), 2)
  assert_eq(
    @lowering_relation.graph_match_field_at(view, 0),
    Some(@schema.Unqualified("node_id")),
  )
  assert_eq(
    @lowering_relation.graph_match_field_at(view, 1),
    Some(@schema.Unqualified("active")),
  )
  assert_eq(@lowering_relation.graph_match_id_count(view), 3)
  assert_eq(
    graph_match_checked_value_wire(
      @lowering_relation.graph_match_id_at(view, 0).unwrap(),
    ),
    "{\"$json\":" + graph_match_identity(2) + "}",
  )
  assert_eq(
    graph_match_checked_value_wire(
      @lowering_relation.graph_match_id_at(view, 2).unwrap(),
    ),
    "{\"$json\":" + graph_match_identity(2) + "}",
  )
  let schema = @lowering_relation.graph_match_output_schema(view)
  assert_eq(@schema.field_count(schema), 2)
  guard @schema.lookup(schema, @schema.Unqualified("node_id")) is Some(identity) else {
    fail("identity contract")
  }
  assert_true(identity.shape is @contract.Json)
  assert_false(identity.nullable)
  assert_true(@schema.lookup(schema, @schema.Unqualified("active")) is Some(_))
  assert_true(@schema.lookup(schema, @schema.Unqualified("Node")) is None)
}

///|
test "definition-selected edge MATCH lowers business predicates separately from label and identity" {
  assert_eq(
    graph_match_wire(
      "[{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"label\":\"owns\",\"bindings\":{\"identity\":\"edge_id\",\"source\":\"source_id\"},\"types\":[\"owns\",\"owns\"],\"where\":\"active\",\"fields\":[\"source_id\",\"edge_id\",\"active\"]}}]",
    ),
    "[{\"id\":\"match_edges_0\",\"in\":[\"input_0\"],\"op\":\"SGA.match_edges\",\"params\":{\"definition\":\"E\",\"label\":\"owns\",\"bindings\":{\"identity\":\"edge_id\",\"source\":\"source_id\"},\"fields\":[\"source_id\",\"edge_id\",\"active\"],\"types\":[\"owns\",\"owns\"],\"where\":{\"body\":\"active\",\"op\":\"field\"}}}]",
  )
}

///|
test "current MATCH preparation enforces definition label binding and field name budgets" {
  let owner = graph_match_owner(
    "[{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"label\":\"owns\",\"bindings\":{\"source\":\"source_id\"},\"fields\":[\"source_id\"]}}]",
  )
  // E (1) + owns (4) + binding source_id (9) + projected source_id (9).
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 4,
      max_name_bytes: 23,
    })
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 4,
      max_name_bytes: 22,
    })
    is Err(
      @lowering_relation.GraphMatchFailure(
        0,
        @lowering_relation.GraphMatchPreparationLimit
      )
    ),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 3,
      max_name_bytes: 23,
    })
    is Err(
      @lowering_relation.GraphMatchFailure(
        0,
        @lowering_relation.GraphMatchPreparationLimit
      )
    ),
  )
}
