///|
test "task Events contracts preserve roles and exact canonical byte limits" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
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
  // Independent SHA-256 of the existing 233-byte structural contract body.
  assert_eq(
    client_task_carrier_contract(events, 233, 100, 20),
    Some(
      (
        "events", "sha256:45db22824c827cb7c33597a52421b2f6677ea5336cfc5d4b068045e5e00df15f",
      ),
    ),
  )
  assert_eq(client_task_carrier_contract(events, 232, 100, 20), None)
  assert_eq(client_task_carrier_contract(events, 233, 1, 20), None)
  assert_eq(client_task_carrier_contract(events, 233, 100, 1), None)
  let changed = @carrier.events(
    records,
    id=@schema.Unqualified("clock"),
    time=@schema.Unqualified("id"),
  ).unwrap()
  assert_not_eq(
    client_task_carrier_contract(changed, 233, 100, 20),
    client_task_carrier_contract(events, 233, 100, 20),
  )
  assert_eq(
    client_task_carrier_contract(
      @carrier.unknown_carrier(EventsKind),
      1000,
      100,
      20,
    ),
    None,
  )
  assert_eq(client_task_carrier_kind("events"), Some(EventsKind))
  assert_eq(client_task_carrier_kind("unknown"), None)
}

///|
test "task Vectors contracts retain ordered identity roles and typed components" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let records = @carrier.rows(
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
  ).unwrap()
  let vectors = @carrier.vectors(
    records,
    ids=[@schema.Unqualified("z"), @schema.Unqualified("a")],
    components=@schema.Unqualified("embedding"),
    max_identity_fields=2,
  ).unwrap()
  // Independent SHA-256, with f32 components and authored z/a role order.
  assert_eq(
    client_task_carrier_contract(vectors, 328, 100, 20),
    Some(
      (
        "vectors", "sha256:4239573e5ffeee2a106539870c801c1e556890d2c2aa93407bb07f970092d30e",
      ),
    ),
  )
  assert_eq(client_task_carrier_contract(vectors, 327, 100, 20), None)
  assert_eq(client_task_carrier_contract(vectors, 328, 1, 20), None)
  let reversed = @carrier.vectors(
    records,
    ids=[@schema.Unqualified("a"), @schema.Unqualified("z")],
    components=@schema.Unqualified("embedding"),
    max_identity_fields=2,
  ).unwrap()
  assert_eq(
    client_task_carrier_contract(reversed, 328, 100, 20),
    Some(
      (
        "vectors", "sha256:ba6851a3a9f9bd6ebc5dbc30928a4f4ef926ffac855f90b04c456fd4b22d4a84",
      ),
    ),
  )
  assert_not_eq(
    client_task_carrier_contract(vectors, 328, 100, 20),
    client_task_carrier_contract(reversed, 328, 100, 20),
  )
  assert_eq(
    client_task_carrier_contract(
      @carrier.unknown_carrier(VectorsKind),
      1000,
      100,
      20,
    ),
    None,
  )
  assert_eq(client_task_carrier_kind("vectors"), Some(VectorsKind))
}

///|
test "normal Events and Vectors Programs compile exact typed task edges and roots" {
  let documents = [
    (
      "events",
      (
        #|{"version":"actql/0.1","id":"typed-events","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"from":"seed","to_events":{"id":"id","time":"id"},"as":"carrier"},{"from":"carrier","watermark_events":{"watermark_ms":2,"policy":"mark"},"as":"computed"},{"from":"computed","events":true,"as":"rows"}],"results":{"out":{"from":"rows","fields":["id","late"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
      ),
    ),
    (
      "vectors",
      (
        #|{"version":"actql/0.1","id":"typed-vectors","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false}},"rows":[{"id":1,"embedding":[0,2]}]},"as":"seed"},{"from":"seed","to_vectors":{"id":"id","vector":"embedding"},"as":"carrier"},{"from":"carrier","normalize_vectors":true,"as":"computed"},{"from":"computed","vectors":true,"as":"rows"}],"results":{"out":{"from":"rows","fields":["id","embedding"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
      ),
    ),
  ]
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: true, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = run_materials_limits()
  for (sort, document) in documents {
    let prepared = prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      limits.preparation,
    ).unwrap()
    let graph = prepared_client_graph(prepared)
    assert_eq(@strategy.graph_task_count(graph), 4)
    let carrier = issue_prepared_client_task_fragment(
      prepared,
      1,
      limits.sequence,
      100000,
      10000,
      100,
    ).unwrap()
    let compute = issue_prepared_client_task_fragment(
      prepared,
      2,
      limits.sequence,
      100000,
      10000,
      100,
    ).unwrap()
    assert_eq(carrier.output_carrier, sort)
    assert_eq(compute.output_carrier, sort)
    let plan = issue_prepared_client_task_plan_graph(
      prepared,
      limits.sequence,
      100000,
      10000,
      100,
    ).unwrap()
    assert_false(plan.wire.contains("\"root_refs\":[]"))
    assert_false(plan.wire.contains("\"data_edges\":[]"))
    assert_eq(
      client_task_plan_graph_wire(
        admit_prepared_client_task_plan_graph(
          prepared,
          plan.wire,
          limits.sequence,
          100000,
          10000,
          100,
        ).unwrap(),
      ),
      plan.wire,
    )
    assert_true(
      admit_prepared_client_task_plan_graph(
        prepared,
        plan.wire.replace(old="\"" + sort + "\"", new="\"foreign-carrier\""),
        limits.sequence,
        100000,
        10000,
        100,
      )
      is Err(MismatchedGraph),
    )
    let compilation = issue_prepared_client_task_compilation(
      prepared,
      run_materials_manifests(),
      limits.sequence,
      1000,
      1000,
      100000,
      10000,
      100,
    ).unwrap()
    assert_eq(client_task_compilation_result_names(compilation), ["answer"])
    let foreign = prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      limits.preparation,
    ).unwrap()
    let policy = "sha256:" + "a".repeat(64)
    assert_true(
      issue_client_task_compiled_run(
        foreign, compilation, policy, policy, "2099-01-01T00:00:00.000Z",
      )
      is Err(ForeignOwner),
    )
  }
}
