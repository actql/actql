///|
test "static map reads original input-only Stage without a fabricated operation" {
  let prepared = input_result_prepared(input_result_document)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let wire = client_task_static_plan_view(
    prepared, compilation, 100000, 10000, 100,
  ).unwrap()
  assert_eq(
    client_task_static_plan_view(prepared, compilation, 100000, 10000, 100).unwrap(),
    wire,
  )
  let view = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  let map = @canonical.object_field(view, "logical_map").unwrap()
  guard @canonical.object_field(map, "steps") is Some(@canonical.Array(steps)) else {
    fail("logical map lacks original stages")
  }
  assert_eq(@canonical.array_count(steps), 2)
  let producer = @canonical.array_at(steps, 0).unwrap()
  assert_true(
    @canonical.object_field(producer, "operator")
    is Some(@canonical.String("values")),
  )
  let receiving = @canonical.array_at(steps, 1).unwrap()
  assert_true(
    @canonical.object_field(receiving, "operator") is Some(@canonical.Null),
  )
  let occurrence = @canonical.object_field(
    @canonical.object_field(receiving, "key").unwrap(),
    "occurrence",
  ).unwrap()
  assert_true(
    @canonical.object_field(occurrence, "kind")
    is Some(@canonical.String("input_output")),
  )
  guard @canonical.object_field(receiving, "ports")
    is Some(@canonical.Array(ports)) else {
    fail("receiving map lacks ports")
  }
  assert_eq(@canonical.array_count(ports), 2)
  let input = @canonical.array_at(ports, 0).unwrap()
  let output = @canonical.array_at(ports, 1).unwrap()
  assert_true(
    @canonical.object_field(input, "role") is Some(@canonical.String("input")),
  )
  assert_true(
    @canonical.object_field(output, "role") is Some(@canonical.String("output")),
  )
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(input, "carrier_contract_cid").unwrap(),
      1000,
      100,
      10,
    ),
    @canonical.stringify_value(
      @canonical.object_field(output, "carrier_contract_cid").unwrap(),
      1000,
      100,
      10,
    ),
  )
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(input, "source").unwrap(),
      1000,
      100,
      10,
    ),
    @canonical.stringify_value(
      @canonical.object_field(output, "source").unwrap(),
      1000,
      100,
      10,
    ),
  )
  let capabilities = @canonical.object_field(view, "capabilities").unwrap()
  for field in ["durable_control", "inspect", "cost_guard", "execution_batch"] {
    assert_true(
      @canonical.object_field(capabilities, field)
      is Some(@canonical.Bool(false)),
    )
  }
}

///|
test "static view rejects a separately prepared identical owner and finite limits" {
  let prepared = input_result_prepared(input_result_document)
  let foreign = input_result_prepared(input_result_document)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(
    client_task_static_plan_view(foreign, compilation, 100000, 10000, 100),
    Err(ForeignCompilation),
  )
  assert_eq(
    client_task_static_plan_view(prepared, compilation, 0, 10000, 100),
    Err(InvalidReadLimits),
  )
  assert_true(
    client_task_static_plan_view(prepared, compilation, 100000, 1, 100)
    is Err(_),
  )
}

///|
test "static map retains checked chain occurrences rather than physical task coordinates" {
  let document =
    #|{"version":"actql/0.1","id":"static-chain","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"original"},{"from":"original","filter":"id > 1","as":"filtered"},{"from":"filtered","select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = input_result_prepared(document)
  let compilation = issue_prepared_client_values_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let wire = client_values_static_plan_view(
    prepared, compilation, 100000, 10000, 100,
  ).unwrap()
  let view = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  let map = @canonical.object_field(view, "logical_map").unwrap()
  guard @canonical.object_field(map, "steps") is Some(@canonical.Array(steps)) else {
    fail("missing checked chain")
  }
  assert_eq(@canonical.array_count(steps), 3)
  assert_eq(@strategy.graph_task_count(prepared_client_graph(prepared)), 1)
  for i in 0..<3 {
    let step = @canonical.array_at(steps, i).unwrap()
    assert_eq(
      @canonical.stringify_value(
        @canonical.object_field(step, "operator").unwrap(),
        1000,
        100,
        10,
      ),
      ["\"values\"", "\"filter\"", "\"select\""][i],
    )
    if i > 0 {
      guard @canonical.object_field(step, "ports")
        is Some(@canonical.Array(ports)) else {
        fail("missing input port")
      }
      let source = @canonical.object_field(
        @canonical.array_at(ports, 0).unwrap(),
        "source",
      ).unwrap()
      assert_true(
        @canonical.object_field(source, "kind")
        is Some(@canonical.String("logical_output")),
      )
      let previous = @canonical.array_at(steps, i - 1).unwrap()
      assert_eq(
        @canonical.stringify_value(
          @canonical.object_field(source, "step_id").unwrap(),
          1000,
          100,
          10,
        ),
        @canonical.stringify_value(
          @canonical.object_field(previous, "step_id").unwrap(),
          1000,
          100,
          10,
        ),
      )
    }
  }
}
