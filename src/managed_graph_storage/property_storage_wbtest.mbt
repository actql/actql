///|
fn property_fixture(composite? : Bool = false) -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let key = @contract.primitive(@contract.NumberType, nullable=true)
  let extra = @contract.primitive(@contract.StringType, nullable=false)
  let keys = if composite { [key, extra] } else { [key] }
  let node = @carrier.property_node_definition(
    "N",
    keys,
    empty,
    ["Node", "Person"],
    max_fields=4,
    max_name_bytes=64,
  ).unwrap()
  let other = @carrier.property_node_definition(
    "Other",
    keys,
    empty,
    ["Node"],
    max_fields=4,
    max_name_bytes=64,
  ).unwrap()
  let element = @carrier.property_node_definition(
    "E",
    keys,
    empty,
    ["R", "Friend"],
    max_fields=4,
    max_name_bytes=64,
  ).unwrap()
  let edge = @carrier.property_edge_definition(element, "n", "N").unwrap()
  @carrier.property_graph(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    [node, other],
    [edge],
    max_definitions=3,
    max_contract_work=1000,
  ).unwrap()
}

///|
fn property_limits() -> Limits {
  {
    ..limits(),
    max_work: 10000,
    max_total_value_bytes: 50000,
    max_retained_value_bytes: 50000,
    max_value_bytes: 5000,
  }
}

///|
fn nullable_null() -> @value.CheckedValue {
  @value.checked_null_value(
    @contract.primitive(@contract.NumberType, nullable=true),
  ).unwrap()
}

///|
fn lookup_identity(
  definition : String,
  domain : String,
  kind : String,
  key : String,
) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.JsonType, nullable=false),
    cursor(
      "{\"definition\":\"" +
      definition +
      "\",\"domain\":\"" +
      domain +
      "\",\"key\":[" +
      key +
      "],\"key_types\":[{\"kind\":\"" +
      kind +
      "\"}]}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
test "keyed lookup refuses foreign definition domains and key types rather than treating them as missing" {
  let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  append_property_node(builder, 0, [number(1)], []).unwrap()
  append_property_edge(builder, 0, [number(10)], [number(1)], [number(1)], []).unwrap()
  let storage = finish(builder).unwrap()
  let domain = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let foreign = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
  assert_eq(
    node_index(storage, lookup_identity("N", foreign, "number", "1")),
    Err(InvalidIdentity),
  )
  assert_eq(
    edge_identity_index(storage, lookup_identity("E", foreign, "number", "10")),
    Err(InvalidIdentity),
  )
  assert_eq(
    node_index(storage, lookup_identity("N", domain, "string", "1")),
    Err(InvalidIdentity),
  )
  assert_eq(
    edge_identity_index(storage, lookup_identity("E", domain, "string", "10")),
    Err(InvalidIdentity),
  )
  assert_eq(
    node_index(storage, lookup_identity("N", domain, "number", "null")),
    Err(InvalidIdentity),
  )
  for key in ["\"1\"", "true", "{}", "[]"] {
    assert_eq(
      node_index(storage, lookup_identity("N", domain, "number", key)),
      Err(InvalidIdentity),
    )
    assert_eq(
      edge_identity_index(storage, lookup_identity("E", domain, "number", key)),
      Err(InvalidIdentity),
    )
  }
  assert_eq(
    node_index(storage, lookup_identity("n", domain, "number", "1")),
    Err(InvalidIdentity),
  )
  assert_eq(
    node_index(storage, lookup_identity("E", domain, "number", "10")),
    Err(InvalidIdentity),
  )
  assert_eq(
    edge_identity_index(storage, lookup_identity("N", domain, "number", "1")),
    Err(InvalidIdentity),
  )
  assert_eq(
    node_index(storage, lookup_identity("N", domain, "number", "2")),
    Ok(None),
  )
  assert_eq(
    edge_identity_index(storage, lookup_identity("E", domain, "number", "11")),
    Ok(None),
  )
}

///|
test "keyed graph preserves independent parallel edges and scoped composite keys" {
  let builder = prepare(
    property_fixture(composite=true),
    DeclaredNodes,
    property_limits(),
  ).unwrap()
  assert_true(
    append_property_node(builder, 0, [number(1), text("a")], []) is Ok(_),
  )
  assert_true(
    append_property_node(builder, 1, [number(1), text("a")], []) is Ok(_),
  )
  assert_true(
    append_property_edge(
      builder,
      0,
      [number(10), text("edge")],
      [number(1), text("a")],
      [number(1), text("a")],
      [],
    )
    is Ok(_),
  )
  assert_true(
    append_property_edge(
      builder,
      0,
      [number(11), text("edge")],
      [number(1), text("a")],
      [number(1), text("a")],
      [],
    )
    is Ok(_),
  )
  let storage = finish(builder).unwrap()
  assert_eq(node_count(storage), 2)
  assert_eq(edge_count(storage), 2)
  let first = node_identity(storage, 0).unwrap()
  let second = node_identity(storage, 1).unwrap()
  assert_eq(node_index(storage, first), Ok(Some(0)))
  assert_eq(node_index(storage, second), Ok(Some(1)))
  assert_eq(edge_endpoints(storage, 0), Some((0, 0)))
  assert_eq(edge_endpoints(storage, 1), Some((0, 0)))
  assert_eq(
    edge_identity_index(storage, edge_identity(storage, 0).unwrap()),
    Ok(Some(0)),
  )
  assert_eq(
    edge_identity_index(storage, edge_identity(storage, 1).unwrap()),
    Ok(Some(1)),
  )
  assert_eq(node_definition_index(storage, 1), Some(1))
  assert_eq(edge_definition_index(storage, 1), Some(0))
  assert_eq(node_typed_key(storage, 0).unwrap().length(), 2)
  assert_eq(edge_typed_key(storage, 1).unwrap().length(), 2)
  let out = @encode.writer(5000, 100, 10)
  @value.emit_checked_wire_value(edge_identity(storage, 0).unwrap(), out)
  assert_eq(
    @encode.finish(out),
    "{\"definition\":\"E\",\"domain\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"key\":[10,\"edge\"],\"key_types\":[{\"kind\":\"number\"},{\"kind\":\"string\"}]}",
  )
  assert_eq(edge_index(storage, first, first, None), Err(WrongProfile))
}

///|
test "keyed graph excludes null keys and missing endpoints without synthesizing nodes" {
  let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  assert_true(append_property_node(builder, 0, [nullable_null()], []) is Ok(_))
  assert_true(append_property_node(builder, 0, [number(1)], []) is Ok(_))
  assert_true(
    append_property_edge(
      builder,
      0,
      [nullable_null()],
      [number(1)],
      [number(1)],
      [],
    )
    is Ok(_),
  )
  assert_true(
    append_property_edge(builder, 0, [number(10)], [number(1)], [number(2)], [])
    is Ok(_),
  )
  assert_true(
    append_property_edge(
      builder,
      0,
      [number(11)],
      [nullable_null()],
      [number(1)],
      [],
    )
    is Ok(_),
  )
  assert_eq(builder_node_count(builder), 1)
  assert_eq(builder_edge_count(builder), 0)
  assert_eq(builder.excluded_edge_keys.length(), 2)
  let retained = builder_retained_value_bytes(builder)
  let storage = finish(builder).unwrap()
  assert_eq(input_row_count(storage), 5)
  assert_eq(node_count(storage), 1)
  assert_eq(edge_count(storage), 0)
  assert_true(retained_value_bytes(storage) < retained)
  assert_true(builder.excluded_edge_keys.is_empty())
  assert_eq(storage.edge_keys.length(), 0)
}

///|
test "duplicate keyed nodes reject even identical rows and discard private output" {
  let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  assert_true(append_property_node(builder, 0, [number(1)], []) is Ok(_))
  assert_eq(
    append_property_node(builder, 0, [number(1)], []),
    Err(DuplicateNodeKey),
  )
  assert_true(finish(builder) is Err(Closed))
  assert_true(cancel(builder))
  assert_eq(builder_node_count(builder), 0)
  assert_eq(builder_retained_value_bytes(builder), 0)
  assert_eq(builder_workspace_slots(builder), 0)
  assert_false(cancel(builder))
}

///|
test "duplicate keyed edges reject before missing endpoint exclusion" {
  let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  assert_true(
    append_property_edge(builder, 0, [number(10)], [number(1)], [number(2)], [])
    is Ok(_),
  )
  assert_true(builder_retained_value_bytes(builder) > 0)
  assert_eq(
    append_property_edge(builder, 0, [number(10)], [number(3)], [number(4)], []),
    Err(DuplicateEdgeKey),
  )
  assert_true(finish(builder) is Err(Closed))
  assert_true(cancel(builder))
  assert_eq(builder_retained_value_bytes(builder), 0)
  assert_eq(builder_workspace_slots(builder), 0)
  assert_true(builder.excluded_edge_keys.is_empty())
}

///|
test "keyed graph limits and cancellation do not hand off partial graph material" {
  let builder = prepare(property_fixture(), DeclaredNodes, {
    ..property_limits(),
    max_nodes: 1,
  }).unwrap()
  assert_true(append_property_node(builder, 0, [number(1)], []) is Ok(_))
  assert_eq(append_property_node(builder, 0, [number(2)], []), Err(NodeLimit))
  assert_true(finish(builder) is Err(Closed))
  assert_true(cancel(builder))
  assert_eq(builder_retained_value_bytes(builder), 0)
  let excluded = prepare(property_fixture(), DeclaredNodes, {
    ..property_limits(),
    max_retained_value_bytes: 0,
  }).unwrap()
  assert_eq(
    append_property_edge(excluded, 0, [number(10)], [number(1)], [number(2)], []),
    Err(RetainedValueLimit),
  )
  assert_true(finish(excluded) is Err(Closed))
  assert_true(cancel(excluded))
  let stopped = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  assert_true(append_property_node(stopped, 0, [number(1)], []) is Ok(_))
  assert_true(cancel(stopped))
  assert_eq(append_property_node(stopped, 0, [number(2)], []), Err(Closed))
  assert_true(finish(stopped) is Err(Closed))
}

///|
test "opaque Graph knowledge cannot allocate keyed material" {
  assert_true(
    prepare(@carrier.unknown_carrier(GraphKind), DeclaredNodes, limits())
    is Err(WrongCarrier),
  )
}
