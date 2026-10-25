///|
test "producer read metadata exact linear-search entries are independent of row workspace" {
  for width in [32, 50] {
    let bindings : Array[String] = []
    for index in 0..<(width - 2) {
      bindings.push("\"c" + index.to_string() + "\":{\"literal\":1}")
    }
    let owner = row_owner(",{\"derive\":{" + bindings.join(",") + "}}")
    let completion = evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["derive_1"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
    ).unwrap()
    let receiver = producer_consumer(owner, Step(1))
    let output = completed_output(completion, Step(1)).unwrap()
    let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
    let demand = bound_producer_read_demand(receiver, bound).unwrap()
    assert_eq(producer_read_demand_columns(demand), width)
    let derived = prepare_producer_read(
      receiver,
      bound,
      producer_read_demand_entries(demand),
      producer_read_demand_name_bytes(demand),
    ).unwrap()
    assert_eq(@schema.field_count(producer_read_schema(derived)), width)
    let exact = width + width * (width + 1) / 2
    let read = prepare_producer_read(receiver, bound, exact, 100000).unwrap()
    assert_eq(@schema.field_count(producer_read_schema(read)), width)
    assert_true(
      prepare_producer_read(receiver, bound, exact - 1, 100000) is Err(Limit),
    )
    if width == 32 {
      assert_true(prepare_producer_read(receiver, bound, 1000, 100000) is Ok(_))
    } else {
      assert_true(
        prepare_producer_read(receiver, bound, 1000, 100000) is Err(Limit),
      )
    }
  }
}

///|
test "producer read schema demand preserves Unicode names and rejects foreign or overflowing facts" {
  let pieces : Array[String] = []
  for _ in 0..<100 {
    pieces.push("列😀")
  }
  let name = pieces.join("")
  let owner = row_owner(",{\"derive\":{\"" + name + "\":{\"literal\":1}}}")
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["derive_1"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
  ).unwrap()
  let receiver = producer_consumer(owner, Step(1))
  let output = completed_output(completion, Step(1)).unwrap()
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  let demand = bound_producer_read_demand(receiver, bound).unwrap()
  assert_eq(producer_read_demand_columns(demand), 3)
  assert_true(producer_read_demand_name_bytes(demand) > 700)
  let read = prepare_producer_read(
    receiver,
    bound,
    producer_read_demand_entries(demand),
    producer_read_demand_name_bytes(demand),
  ).unwrap()
  assert_true(producer_read_available(read))
  let schema = producer_read_schema(read)
  assert_true(producer_read_schema_demand(schema, schema, -1) is None)
  assert_true(producer_read_schema_demand(schema, schema, 2147483647) is None)
  let foreign = producer_consumer(owner, Step(1))
  assert_true(bound_producer_read_demand(foreign, bound) is None)
}
