///|
test "unconnected delta consumer refuses current Graph before snapshot allocation" {
  let current = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [],
    [],
    max_definitions=0,
    max_contract_work=100,
  ).unwrap()
  let builder = @storage.prepare(current, DeclaredNodes, storage_limits()).unwrap()
  let storage = @storage.finish(builder).unwrap()
  let contract = @graph_contract.admit(current, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  assert_true(
    prepare(
      storage,
      storage,
      @contract.primitive(NumberType, nullable=false),
      @graph_contract.cid(contract),
      diff_limits(1000),
    )
    is Err(UnsupportedGraphOperation),
  )
  assert_eq(@storage.node_count(storage), 0)
  assert_eq(@storage.edge_count(storage), 0)
  assert_eq(
    @graph_contract.cid(
      @graph_contract.admit(@storage.carrier(storage), {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 100,
      }).unwrap(),
    ),
    @graph_contract.cid(contract),
  )
}

///|
test "unconnected delta refuses parallel independent edges without consuming input" {
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let number = @contract.primitive(NumberType, nullable=false)
  let node = @carrier.property_node_definition(
    "N",
    [number],
    empty,
    ["Node"],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  let element = @carrier.property_node_definition(
    "E",
    [number],
    empty,
    ["Link"],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  let current = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [@carrier.property_edge_definition(element, "N", "N").unwrap()],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  let checked_number = value => {
    @value.recheck_runtime_value(@value.number_value(value).unwrap(), number, {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 0,
    }).unwrap()
  }
  let builder = @storage.prepare(current, DeclaredNodes, storage_limits()).unwrap()
  @storage.append_property_node(builder, 0, [checked_number(1)], []).unwrap()
  @storage.append_property_edge(
    builder,
    0,
    [checked_number(10)],
    [checked_number(1)],
    [checked_number(1)],
    [],
  ).unwrap()
  @storage.append_property_edge(
    builder,
    0,
    [checked_number(11)],
    [checked_number(1)],
    [checked_number(1)],
    [],
  ).unwrap()
  let storage = @storage.finish(builder).unwrap()
  let first = @storage.edge_identity(storage, 0).unwrap()
  let second = @storage.edge_identity(storage, 1).unwrap()
  assert_true(
    prepare(
      storage,
      storage,
      number,
      "sha256:" + "0".repeat(64),
      diff_limits(1000),
    )
    is Err(UnsupportedGraphOperation),
  )
  assert_eq(@storage.node_count(storage), 1)
  assert_eq(@storage.edge_count(storage), 2)
  assert_eq(@storage.edge_identity_index(storage, first), Ok(Some(0)))
  assert_eq(@storage.edge_identity_index(storage, second), Ok(Some(1)))
}

///|
test "unconnected delta retains pure limit validation before typed refusal" {
  let current = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [],
    [],
    max_definitions=0,
    max_contract_work=100,
  ).unwrap()
  let storage = @storage.finish(
    @storage.prepare(current, DeclaredNodes, storage_limits()).unwrap(),
  ).unwrap()
  let number = @contract.primitive(NumberType, nullable=false)
  for
    invalid in [
      { ..diff_limits(0), max_workspace_slots: -1, },
      { ..diff_limits(0), max_output_nodes: -1, },
      { ..diff_limits(0), max_output_text_bytes: -1, },
      { ..diff_limits(0), max_output_depth: -1, },
      { ..diff_limits(0), max_identity_bytes: -1, },
      { ..diff_limits(0), max_identity_nodes: -1, },
      { ..diff_limits(0), max_identity_depth: -1, },
    ] {
    assert_true(
      prepare(storage, storage, number, "sha256:" + "0".repeat(64), invalid)
      is Err(InvalidLimits),
    )
  }
  assert_true(
    prepare(
      storage,
      storage,
      number,
      "sha256:" + "0".repeat(64),
      diff_limits(0),
    )
    is Err(UnsupportedGraphOperation),
  )
  assert_eq(@storage.retained_value_bytes(storage), 0)
}
