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
    prepared,
    compilation,
    100000,
    10000,
    100,
    inspect_installed=true,
  ).unwrap()
  assert_eq(
    client_task_static_plan_view(
      prepared,
      compilation,
      100000,
      10000,
      100,
      inspect_installed=true,
    ).unwrap(),
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
  assert_true(
    @canonical.object_field(output, "port_ordinal")
    is Some(@canonical.Number(0.0)),
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
  for field in ["static_plan", "inspect"] {
    assert_true(
      @canonical.object_field(capabilities, field)
      is Some(@canonical.Bool(true)),
    )
  }
  for field in ["durable_control", "cost_guard", "execution_batch"] {
    assert_true(
      @canonical.object_field(capabilities, field)
      is Some(@canonical.Bool(false)),
    )
  }
  let default_view = parse_plan_identity_value(
    client_task_static_plan_view(prepared, compilation, 100000, 10000, 100).unwrap(),
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    @canonical.object_field(
      @canonical.object_field(default_view, "capabilities").unwrap(),
      "inspect",
    )
    is Some(@canonical.Bool(false)),
  )
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
test "task Static Explanation shares the existing Plan and Map without a Run" {
  let prepared = input_result_prepared(input_result_document)
  let foreign = input_result_prepared(input_result_document)
  let compiled = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(
    capture_client_static_pure_explanation_original(
      foreign,
      Tasks(compiled),
      65536,
      8192,
      64,
    )
    is Err(ForeignOriginal),
  )
  let (original, plan) = capture_client_static_pure_explanation_original(
    prepared,
    Tasks(compiled),
    65536,
    8192,
    64,
  ).unwrap()
  assert_eq(
    plan,
    client_task_static_plan_view(prepared, compiled, 65536, 8192, 64).unwrap(),
  )
  let geometry = measure_client_static_pure_explanation_facts(
    original, 65536, 8192, 64,
  ).unwrap()
  let (bytes, nodes, depth) = geometry.complete
  let facts = seal_client_static_pure_explanation_facts(
    original, bytes, nodes, depth,
  ).unwrap()
  let facts = @publication.parse_interactive_run_control_shape(
    "explanation_facts",
    @publication.run_evidence_value_json(facts),
    bytes,
    nodes,
    depth,
  ).unwrap()
  let writer = @encode.writer(65536, 8192, 64)
  write_client_static_pure_explanation_context(original, writer, 10000).unwrap()
  let context = @publication.parse_interactive_run_control_shape(
    "explanation_context",
    @encode.finish(writer),
    65536,
    8192,
    64,
  ).unwrap()
  let binding = explanation_original_field(context, "binding")
  let plan_ref = compiled_run_plan_field(original.map, "compiled_plan_cid")
  assert_eq(compiled_run_plan_field(binding, "compiled_plan_cid"), plan_ref)
  assert_eq(compiled_run_plan_field(facts, "compiled_plan_cid"), plan_ref)
  let map_ref = compiled_run_plan_field(original.map, "self_cid")
  assert_eq(compiled_run_plan_field(binding, "logical_map_cid"), map_ref)
  assert_eq(compiled_run_plan_field(facts, "logical_map_cid"), map_ref)
  assert_eq(
    compiled_run_plan_field(binding, "check_environment_cid"),
    prepared_client_check_environment_cid(prepared),
  )
  let items = explanation_original_field(context, "items")
  guard items is @canonical.Array(items) else { fail("original Context items") }
  assert_eq(@canonical.array_count(items), 1)
  assert_eq(
    compiled_run_plan_field(@canonical.array_at(items, 0).unwrap(), "kind"),
    "result",
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
    guard @canonical.object_field(step, "ports")
      is Some(@canonical.Array(ports)) else {
      fail("missing checked ports")
    }
    let mut outputs = 0
    for position in 0..<@canonical.array_count(ports) {
      let port = @canonical.array_at(ports, position).unwrap()
      if @canonical.object_field(port, "role")
        is Some(@canonical.String("output")) {
        outputs += 1
        assert_true(
          @canonical.object_field(port, "port_ordinal")
          is Some(@canonical.Number(0.0)),
        )
      }
    }
    assert_eq(outputs, 1)
    if i > 0 {
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
