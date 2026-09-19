///|
fn graph_fixture(
  label? : Bool = true,
  node_fields? : Bool = true,
) -> @carrier.Carrier {
  let id = @contract.primitive(@contract.NumberType, nullable=false)
  let node_properties = @carrier.rows(
    if node_fields {
      [
        (
          @schema.Unqualified("name"),
          Some(@contract.primitive(@contract.StringType, nullable=false)),
        ),
      ]
    } else {
      []
    },
    field_set=@carrier.Closed,
    max_fields=if node_fields { 1 } else { 0 },
    max_name_bytes=4,
  ).unwrap()
  let edge_properties = @carrier.rows(
    [
      (
        @schema.Unqualified("weight"),
        Some(@contract.primitive(@contract.NumberType, nullable=false)),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  @carrier.graph(
    id,
    node_properties,
    edge_properties,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    label_contract=if label {
      Some(@contract.primitive(@contract.StringType, nullable=true))
    } else {
      None
    },
  ).unwrap()
}

///|
fn limits() -> Limits {
  {
    max_input_rows: 20,
    max_nodes: 10,
    max_edges: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 1000, max_nodes: 100, max_depth: 20, },
      source_path="managed-graph-test.json",
    ).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
fn number(value : Double) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.NumberType, nullable=false),
    cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn text(value : String, nullable? : Bool = false) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.StringType, nullable~),
    cursor("\"" + value + "\""),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 100, },
  ).unwrap()
}

///|
test "declared graph collapses equal payloads and closes endpoints" {
  let builder = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  assert_true(append_node(builder, number(1.0), [text("a")]) is Ok(_))
  assert_true(append_node(builder, number(2.0), [text("b")]) is Ok(_))
  assert_true(append_node(builder, number(1.0), [text("a")]) is Ok(_))
  assert_true(
    append_edge(
      builder,
      number(1.0),
      number(2.0),
      Some(text("knows", nullable=true)),
      [number(3.0)],
    )
    is Ok(_),
  )
  assert_true(
    append_edge(
      builder,
      number(1.0),
      number(2.0),
      Some(text("knows", nullable=true)),
      [number(3.0)],
    )
    is Ok(_),
  )
  let graph = finish(builder).unwrap()
  assert_eq(mode(graph), DeclaredNodes)
  assert_eq(node_count(graph), 2)
  assert_eq(edge_count(graph), 1)
  assert_eq(input_row_count(graph), 5)
  assert_eq(edge_endpoints(graph, 0), Some((0, 1)))
  assert_true(node_property(graph, 0, 0) is Some(_))
  assert_true(edge_property(graph, 0, 0) is Some(_))
  assert_true(retained_value_bytes(graph) > 0)
  assert_true(measured_input_value_bytes(graph) > retained_value_bytes(graph))
  assert_eq(construction_work(graph), 37)
  assert_true(retained_workspace_slots(graph) > 0)
}

///|
test "derived graph creates endpoint nodes without partial conflicts" {
  let builder = prepare(
    graph_fixture(label=false, node_fields=false),
    DerivedEndpoints,
    limits(),
  ).unwrap()
  assert_true(
    append_edge(builder, number(1.0), number(2.0), None, [number(3.0)]) is Ok(_),
  )
  assert_true(
    append_edge(builder, number(2.0), number(2.0), None, [number(4.0)]) is Ok(_),
  )
  let graph = finish(builder).unwrap()
  assert_eq(node_count(graph), 2)
  assert_eq(edge_count(graph), 2)
  assert_eq(edge_endpoints(graph, 1), Some((1, 1)))
  assert_true(node_property(graph, 0, 0) is None)
}

///|
test "graph construction rejects conflicts missing endpoints and preallocation overflow" {
  let conflict = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_node(conflict, number(1.0), [text("a")]).unwrap()
  assert_true(
    append_node(conflict, number(1.0), [text("b")])
    is Err(DuplicateNodeConflict),
  )
  assert_true(finish(conflict) is Err(Closed))

  let missing = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  assert_true(
    append_edge(
      missing,
      number(1.0),
      number(2.0),
      Some(text("x", nullable=true)),
      [number(1.0)],
    )
    is Err(MissingEndpoint),
  )

  let tiny = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_workspace_slots: 4,
  }).unwrap()
  assert_true(
    append_node(tiny, number(1.0), [text("a")]) is Err(WorkspaceLimit),
  )
  assert_true(finish(tiny) is Err(Closed))

  let work_short = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_work: 4,
  }).unwrap()
  assert_true(
    append_node(work_short, number(1.0), [text("a")]) is Err(WorkLimit),
  )

  let cancelled = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_node(cancelled, number(1.0), [text("a")]).unwrap()
  assert_true(cancel(cancelled))
  assert_false(cancel(cancelled))
  assert_true(finish(cancelled) is Err(Closed))

  let measured = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_node(measured, number(1.0), [text("a")]).unwrap()
  let retained = retained_value_bytes(finish(measured).unwrap())
  let exact = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_retained_value_bytes: retained,
  }).unwrap()
  assert_true(append_node(exact, number(1.0), [text("a")]) is Ok(_))
  let short = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_retained_value_bytes: retained - 1,
  }).unwrap()
  assert_true(
    append_node(short, number(1.0), [text("a")]) is Err(RetainedValueLimit),
  )
}
