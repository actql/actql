///|
test "compiler Carrier construction includes required and conditional Relation bodies" {
  let number = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.primitive(NumberType, nullable=true)
  let conditional = @schema.from_presence_fields(
    [
      (@schema.Unqualified("id"), number, @schema.Required),
      (@schema.Unqualified("p"), nullable, @schema.Conditional),
    ],
    max_fields=2,
    max_name_bytes=10,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(conditional))
  let extent = measure_client_task_carrier_contract(carrier, 117, 100, 20).unwrap()
  assert_eq(extent.0, 117)
  assert_true(extent.1 > 1 && extent.2 > 1)
  for
    (b, n, d) in [
      (116, 100, 20),
      (117, extent.1 - 1, 20),
      (117, 100, extent.2 - 1),
    ] {
    assert_true(measure_client_task_carrier_contract(carrier, b, n, d) is None)
  }
  let dense = @schema.from_fields(
    [(@schema.Unqualified("id"), number), (@schema.Unqualified("p"), nullable)],
    max_fields=2,
    max_name_bytes=10,
  ).unwrap()
  let dense = @carrier.relation(@carrier.typed_rows(dense))
  let dense_extent = measure_client_task_carrier_contract(dense, 1000, 100, 20).unwrap()
  assert_true(dense_extent != extent)
  assert_true(
    client_task_carrier_contract(dense, 1000, 100, 20) !=
    client_task_carrier_contract(carrier, 1000, 100, 20),
  )
}

///|
test "compiler Carrier construction measures the current keyed Graph codec" {
  let body = keyed_task_contract_body()
  let parsed = @source.parse_json(body, {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 1000,
    max_depth: 100,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  let original = @graph_contract.read_cursor(cursor, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let carrier = @carrier.graph_carrier(@graph_contract.graph(original))
  let measured = measure_client_task_carrier_contract(carrier, 10000, 1000, 100).unwrap()
  assert_eq(measured, publication_original_wire_geometry(body))
  assert_eq(measured.0, body.length())
  assert_true(
    measure_client_task_carrier_contract(carrier, measured.0 - 1, 1000, 100)
    is None,
  )
  assert_true(
    measure_client_task_carrier_contract(
      @carrier.unknown_carrier(GraphKind),
      10000,
      1000,
      100,
    )
    is None,
  )
}

///|
test "compiler Carrier construction preserves Events and ordered Vectors roles" {
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
  for (carrier, bytes) in [(events, 233), (vectors, 328)] {
    let measured = measure_client_task_carrier_contract(carrier, bytes, 100, 20).unwrap()
    assert_eq(measured.0, bytes)
    let records = match carrier {
      @carrier.EventValue(v) => @carrier.event_records(v)
      @carrier.VectorValue(v) => @carrier.vector_records(v)
      _ => fail("record Carrier fixture")
    }
    let row = @schema.as_object(@carrier.complete_schema(records).unwrap()).unwrap()
    let writer = @encode.writer(bytes, measured.1, measured.2)
    assert_true(emit_client_task_record_carrier_body(carrier, row, writer))
    let wire = @encode.finish(writer)
    assert_eq(measured, publication_original_wire_geometry(wire))
    for
      (b, n, d) in [
        (bytes - 1, measured.1, measured.2),
        (bytes, measured.1 - 1, measured.2),
        (bytes, measured.1, measured.2 - 1),
      ] {
      assert_true(
        measure_client_task_carrier_contract(carrier, b, n, d) is None,
      )
    }
  }
}

///|
test "Task construction retains separate original port contracts rather than CID-width backing" {
  let value = task_pipeline_geometry_original()
  let sequence = prepared_client_values_sequence_limits(value)
  let mut inputs = 0
  for task in 0..<@strategy.graph_task_count(value.graph) {
    let measured = measure_prepared_client_task_fragment_construction(
      value, task, sequence, 1000000, 100000, 100,
    ).unwrap()
    let original = issue_prepared_client_task_fragment(
      value, task, sequence, 1000000, 100000, 100,
    ).unwrap()
    assert_eq(measured.node_id, original.node_id)
    assert_eq(measured.output_port, original.output_port)
    assert_eq(measured.output_carrier, original.output_carrier)
    assert_true(measured.output_contract.0 > 73)
    for contract in measured.input_contracts {
      assert_true(contract.0 > 73)
    }
    inputs += measured.input_contracts.length()
    let tree = parse_plan_identity_value(original.wire, 1000000, 100000, 100).unwrap()
    let actual = result_graph_value_geometry(tree)
    assert_true(actual.0 <= measured.fragment.0)
    assert_eq(actual.1, measured.fragment.1)
    assert_eq(actual.2, measured.fragment.2)
  }
  assert_true(inputs > 0)
}
