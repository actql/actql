///|
fn graph_fixture() -> @carrier.Carrier {
  let id = @contract.primitive(@contract.NumberType, nullable=false)
  let node_properties = @carrier.rows(
    [
      (
        @schema.Unqualified("name"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  let edge_properties = @carrier.rows(
    [(@schema.Unqualified("weight"), Some(id))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [id],
    node_properties,
    ["Person"],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  let element = @carrier.property_node_definition(
    "E",
    [id],
    edge_properties,
    ["Knows"],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [@carrier.property_edge_definition(element, "N", "N").unwrap()],
    max_definitions=2,
    max_contract_work=1000,
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
test "declared keyed graph retains parallel edge records and closes endpoints" {
  let builder = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_property_node(builder, 0, [number(1)], [text("a")]).unwrap()
  append_property_node(builder, 0, [number(2)], [text("b")]).unwrap()
  append_property_edge(builder, 0, [number(10)], [number(1)], [number(2)], [
    number(3),
  ]).unwrap()
  append_property_edge(builder, 0, [number(11)], [number(1)], [number(2)], [
    number(3),
  ]).unwrap()
  let graph = finish(builder).unwrap()
  assert_eq(mode(graph), DeclaredNodes)
  assert_eq(node_count(graph), 2)
  assert_eq(edge_count(graph), 2)
  assert_eq(input_row_count(graph), 4)
  assert_eq(edge_endpoints(graph, 0), Some((0, 1)))
  assert_eq(edge_endpoints(graph, 1), Some((0, 1)))
  assert_true(node_property(graph, 0, 0) is Some(_))
  assert_true(edge_property(graph, 0, 0) is Some(_))
  assert_true(retained_value_bytes(graph) > 0)
  assert_true(measured_input_value_bytes(graph) > retained_value_bytes(graph))
  assert_true(construction_work(graph) > 0)
  assert_true(retained_workspace_slots(graph) > 0)
  assert_eq(
    node_index(
      graph,
      lookup_identity("N", "sha256:" + "0".repeat(64), "number", "1"),
    ),
    Ok(Some(0)),
  )
  assert_eq(
    edge_identity_index(
      graph,
      lookup_identity("E", "sha256:" + "0".repeat(64), "number", "10"),
    ),
    Ok(Some(0)),
  )
  assert_eq(
    edge_identity_index(
      graph,
      lookup_identity("E", "sha256:" + "0".repeat(64), "number", "11"),
    ),
    Ok(Some(1)),
  )
}

///|
test "completed keyed graph reuses its admitted identity index and revokes it on discard" {
  let builder = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_property_node(builder, 0, [number(2)], [text("b")]).unwrap()
  append_property_node(builder, 0, [number(1)], [text("a")]).unwrap()
  let graph = finish(builder).unwrap()
  let domain = "sha256:" + "0".repeat(64)
  let first = lookup_identity("N", domain, "number", "2")
  assert_eq(node_index(graph, first), Ok(Some(0)))
  assert_eq(
    node_index(graph, lookup_identity("N", domain, "number", "1")),
    Ok(Some(1)),
  )
  assert_eq(
    node_index(graph, lookup_identity("N", domain, "number", "4")),
    Ok(None),
  )
  assert_true(node_index(graph, text("2")) is Err(InvalidIdentity))
  discard(graph)
  assert_eq(node_index(graph, first), Ok(None))
  discard(graph)
  assert_eq(node_count(graph), 0)
}

///|
test "keyed graph keeps atomic key conflict capacity work and cancellation boundaries" {
  let conflict = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_property_node(conflict, 0, [number(1)], [text("a")]).unwrap()
  assert_true(
    append_property_node(conflict, 0, [number(1)], [text("a")])
    is Err(DuplicateNodeKey),
  )
  assert_true(finish(conflict) is Err(Closed))
  assert_true(cancel(conflict))
  assert_eq(builder_node_count(conflict), 0)
  assert_eq(builder_retained_value_bytes(conflict), 0)

  let missing = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_property_edge(missing, 0, [number(10)], [number(1)], [number(2)], [
    number(1),
  ]).unwrap()
  let missing_graph = finish(missing).unwrap()
  assert_eq(node_count(missing_graph), 0)
  assert_eq(edge_count(missing_graph), 0)
  assert_eq(input_row_count(missing_graph), 1)

  let tiny = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_workspace_slots: 4,
  }).unwrap()
  assert_true(
    append_property_node(tiny, 0, [number(1)], [text("a")])
    is Err(WorkspaceLimit),
  )
  assert_true(finish(tiny) is Err(Closed))
  assert_true(cancel(tiny))
  assert_eq(builder_workspace_slots(tiny), 0)

  let work_short = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_work: 4,
  }).unwrap()
  assert_true(
    append_property_node(work_short, 0, [number(1)], [text("a")])
    is Err(WorkLimit),
  )
  assert_true(finish(work_short) is Err(Closed))
  assert_true(cancel(work_short))

  let cancelled = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_property_node(cancelled, 0, [number(1)], [text("a")]).unwrap()
  assert_true(cancel(cancelled))
  assert_false(cancel(cancelled))
  assert_true(finish(cancelled) is Err(Closed))

  let measured = prepare(graph_fixture(), DeclaredNodes, limits()).unwrap()
  append_property_node(measured, 0, [number(1)], [text("a")]).unwrap()
  let retained = retained_value_bytes(finish(measured).unwrap())
  let exact = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_retained_value_bytes: retained,
  }).unwrap()
  append_property_node(exact, 0, [number(1)], [text("a")]).unwrap()
  assert_eq(retained_value_bytes(finish(exact).unwrap()), retained)
  let short = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_retained_value_bytes: retained - 1,
  }).unwrap()
  assert_true(
    append_property_node(short, 0, [number(1)], [text("a")])
    is Err(RetainedValueLimit),
  )
  assert_true(finish(short) is Err(Closed))
  assert_true(cancel(short))
}

///|
test "keyed graph storage admits independently counted canonical UTF-8 byte limits" {
  // The definition-scoped identity is ASCII; ["é"] is six UTF-8 bytes.
  let identity = "[{\"definition\":\"N\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}]"
  let bytes = identity.length() + 6
  let exact = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_total_value_bytes: bytes,
    max_retained_value_bytes: bytes,
  }).unwrap()
  append_property_node(exact, 0, [number(1)], [text("é")]).unwrap()
  let stored = finish(exact).unwrap()
  assert_eq(measured_input_value_bytes(stored), bytes)
  assert_eq(retained_value_bytes(stored), bytes)
  let short = prepare(graph_fixture(), DeclaredNodes, {
    ..limits(),
    max_total_value_bytes: bytes - 1,
    max_retained_value_bytes: bytes,
  }).unwrap()
  assert_true(
    append_property_node(short, 0, [number(1)], [text("é")]) is Err(ValueLimit),
  )
  assert_true(finish(short) is Err(Closed))
  assert_true(cancel(short))
}
