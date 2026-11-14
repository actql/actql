///|
test "pre-writer Carrier nodes bound the original measuring branches" {
  let number = @contract.primitive(NumberType, nullable=false)
  let row = @schema.from_presence_fields(
    [
      (@schema.Qualified(Left, "é"), number, @schema.Conditional),
      (@schema.Unqualified("id"), number, @schema.Required),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let dense = @carrier.rows(
    [(@schema.Unqualified("id"), Some(number))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let node = @carrier.graph_node_definition(
    "Node",
    [number],
    dense,
    ["Label"],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let edge_node = @carrier.graph_node_definition(
    "Edge",
    [number],
    dense,
    ["EdgeLabel"],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.graph_edge_definition(edge_node, "Node", "Node").unwrap()
  let graph = @carrier.graph(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    [node],
    [edge],
    max_definitions=10,
    max_contract_work=10000,
  ).unwrap()
  for
    carrier in [
      @carrier.relation(dense),
      @carrier.relation(@carrier.typed_rows(row)),
      graph,
    ] {
    let extent = client_carrier_measurement_construction(carrier).unwrap()
    let (_, nodes, depth) = measure_client_task_carrier_contract(
      carrier,
      100000,
      extent.value_nodes,
      extent.depth,
    ).unwrap()
    assert_eq(nodes, extent.value_nodes)
    assert_true(depth <= extent.depth)
    assert_true(extent.max_contract_nodes > 0)
    let variable = client_carrier_measurement_variable_layout(extent).unwrap()
    assert_true(variable.collections.record_headers > 0L)
    assert_eq(variable.presence_fields, extent.presence_fields)
  }
  let conditional = client_carrier_measurement_construction(
    @carrier.relation(@carrier.typed_rows(row)),
  ).unwrap()
  assert_eq(conditional.presence_fields, Some(2))
  assert_true(conditional.reference_name_utf16 > 0L)
  let g = client_carrier_measurement_construction(graph).unwrap()
  assert_eq(
    (g.graph_nodes, g.graph_edges, g.max_graph_keys, g.max_graph_labels),
    (1, 1, 1, 1),
  )
}

///|
test "pre-writer record role geometry agrees with Events and Vectors" {
  let number = @contract.primitive(NumberType, nullable=false)
  let records = @carrier.rows(
    [
      (@schema.Unqualified("id"), Some(number)),
      (@schema.Unqualified("clock"), Some(number)),
    ],
    field_set=@carrier.Closed,
    max_fields=2,
    max_name_bytes=20,
  ).unwrap()
  let events = @carrier.events(
    records,
    id=@schema.Unqualified("id"),
    time=@schema.Unqualified("clock"),
  ).unwrap()
  let vectors = @carrier.vectors(
    @carrier.rows(
      [
        (@schema.Unqualified("z"), Some(number)),
        (@schema.Unqualified("a"), Some(number)),
        (
          @schema.Unqualified("embedding"),
          Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=3,
      max_name_bytes=20,
    ).unwrap(),
    ids=[@schema.Unqualified("z"), @schema.Unqualified("a")],
    components=@schema.Unqualified("embedding"),
    max_identity_fields=2,
  ).unwrap()
  for carrier in [events, vectors] {
    let extent = client_carrier_measurement_construction(carrier).unwrap()
    let (_, nodes, depth) = measure_client_task_carrier_contract(
      carrier,
      100000,
      extent.value_nodes,
      extent.depth,
    ).unwrap()
    assert_eq(nodes, extent.value_nodes)
    assert_eq(depth, extent.depth)
  }
}
