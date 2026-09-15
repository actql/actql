///|
test "fixed join request binds both captured ports through registered Local selection" {
  let (issuer, acquisition) = query_issuer_fixture()
  let source_owner = @query.query_sequence_owner(acquisition)
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    Step(1),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"left\":\"left.id\",\"right\":\"right.id\"}},\"from\":\"l\"}]",
    ),
    [
      ("l", @pipeline.ProducedInput(producer)),
      ("r", @pipeline.ProducedInput(producer)),
    ],
    None,
    None,
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let generated = @execution.prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["join_0"],
    100000,
    10000,
  ).unwrap()
  let attempt = query_issuer_attempt(
    issuer,
    acquisition,
    @planning.BroadWithResidual,
  )
  query_issuer_run(attempt)
  let records = @planning.issue_mock_query_records(
    attempt,
    query_material_limits(),
  ).unwrap()
  let observation = @planning.capture_mock_query(
    issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let inputs = [0, 1].map(index => {
    let bound = @planning.bind_captured_query_input(
      issuer, attempt, observation, receiver, index, source_owner,
    ).unwrap()
    @execution.prepare_producer_read(receiver, bound, 100, 1000).unwrap()
  })
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 2,
    max_value_bytes: 100,
    common_fragment: None,
  }
  assert_true(
    @connector.prepare_fixed_compute_request([], capacity)
    is Err(UnsupportedInputShape),
  )
  assert_true(
    @connector.prepare_fixed_compute_request([inputs[0]], capacity)
    is Err(UnsupportedInputShape),
  )
  assert_true(
    @connector.prepare_fixed_compute_request([inputs[1], inputs[0]], capacity)
    is Err(UnsupportedInputShape),
  )
  assert_true(
    @connector.prepare_fixed_compute_request([inputs[0], inputs[0]], capacity)
    is Err(UnsupportedInputShape),
  )
  assert_true(
    @connector.prepare_fixed_compute_request(inputs, {
      ..capacity,
      max_rows: 1,
    })
    is Err(CommonInputRows),
  )
  let short_attempt = @planning.prepare_issued_mock_query_attempt(
    issuer,
    strategy_for(acquisition, @planning.BroadWithResidual),
    [input_cursor("{\"id\":3}")],
    1,
  ).unwrap()
  query_issuer_run(short_attempt)
  let short_records = @planning.issue_mock_query_records(
    short_attempt,
    query_material_limits(),
  ).unwrap()
  let short_observation = @planning.capture_mock_query(
    issuer,
    short_attempt,
    short_records,
    query_capture_limits(),
  ).unwrap()
  let short = @execution.prepare_producer_read(
    receiver,
    @planning.bind_captured_query_input(
      issuer, short_attempt, short_observation, receiver, 0, source_owner,
    ).unwrap(),
    100,
    1000,
  ).unwrap()
  // The first input fits; checking only it would miss the second input's limit.
  assert_true(
    @connector.prepare_fixed_compute_request([short, inputs[1]], {
      ..capacity,
      max_rows: 1,
    })
    is Err(CommonInputRows),
  )
  let foreign_owner = typed_receiver(source_owner, "[{\"select\":[\"id\"]}]")
  let foreign = @execution.prepare_producer_read(
    foreign_owner,
    @planning.bind_captured_query_input(
      issuer, attempt, observation, foreign_owner, 0, source_owner,
    ).unwrap(),
    100,
    1000,
  ).unwrap()
  assert_true(
    @connector.prepare_fixed_compute_request([inputs[0], foreign], capacity)
    is Err(ForeignPreparation),
  )
  let request = @connector.prepare_fixed_compute_request(inputs, capacity).unwrap()
  assert_true(
    physical_equal(@connector.fixed_compute_request_owner(request), receiver),
  )
  assert_eq(@connector.fixed_compute_request_input_count(request), 2)
  assert_true(@connector.fixed_compute_request_input(request, -1) is None)
  assert_true(@connector.fixed_compute_request_input(request, 2) is None)
  let right = inputs[1]
  inputs[1] = inputs[0]
  assert_true(
    physical_equal(
      @connector.fixed_compute_request_input(request, 1).unwrap(),
      right,
    ),
  )
  inputs[1] = right
  let tables = ["left_input", "right_input"]
  let native_query = @duckdb.compile_fixed_inner_join(
    receiver,
    "main",
    tables,
    native_compile_limits(),
  ).unwrap()
  tables[1] = "substituted"
  let validation_limits : @execution.FixedJoinValidationLimits = {
    max_rows: 2,
    max_work: 10000,
    max_entries: 100,
  }
  let native_inputs = @duckdb.prepare_fixed_join_inputs(
    native_query, inputs, validation_limits, 2, 10000,
  ).unwrap()
  assert_eq(@duckdb.fixed_join_import_count(native_inputs), 2)
  assert_eq(
    @duckdb.fixed_import_create_sql(
      @duckdb.fixed_join_import_at(native_inputs, 1).unwrap(),
    ),
    "CREATE TEMP TABLE \"right_input\" (\"id\" DOUBLE NOT NULL)",
  )
  assert_true(@duckdb.fixed_join_import_at(native_inputs, 2) is None)
  assert_true(@duckdb.fixed_join_inputs_available(native_inputs))
  let profile = @duckdb.native_inner_join_profile(native_query)
  let validated = @execution.validate_fixed_join_inputs(
    receiver, profile, inputs, validation_limits,
  ).unwrap()
  assert_true(
    @execution.fixed_join_validation_matches(
      validated, receiver, profile, inputs,
    ),
  )
  assert_false(
    @execution.fixed_join_validation_matches(validated, receiver, profile, [
      inputs[1],
      inputs[0],
    ]),
  )
  let another_query = @duckdb.compile_fixed_inner_join(
    receiver,
    "main",
    ["left_input", "right_input"],
    native_compile_limits(),
  ).unwrap()
  assert_false(
    @execution.fixed_join_validation_matches(
      validated,
      receiver,
      @duckdb.native_inner_join_profile(another_query),
      inputs,
    ),
  )
  let (work, peak) = @execution.fixed_join_validation_usage(
    @duckdb.validate_fixed_join_preflight(native_inputs).unwrap(),
  )
  assert_true(work > 0 && peak > 0)
  assert_true(
    (@duckdb.prepare_fixed_join_inputs(
      native_query,
      inputs,
      { ..validation_limits, max_work: work, max_entries: peak, },
      2,
      10000,
    ).unwrap()
    |> @duckdb.validate_fixed_join_preflight)
    is Ok(_),
  )
  assert_true(
    (@duckdb.prepare_fixed_join_inputs(
      native_query,
      inputs,
      { ..validation_limits, max_work: work - 1, },
      2,
      10000,
    ).unwrap()
    |> @duckdb.validate_fixed_join_preflight)
    is Err(RowLimit),
  )
  assert_true(
    (@duckdb.prepare_fixed_join_inputs(
      native_query,
      inputs,
      { ..validation_limits, max_entries: peak - 1, },
      2,
      10000,
    ).unwrap()
    |> @duckdb.validate_fixed_join_preflight)
    is Err(RowLimit),
  )
  assert_true(
    @duckdb.prepare_fixed_join_inputs(
      native_query, inputs, validation_limits, 1, 10000,
    )
    is Err(Import(Limit)),
  )
  assert_true(
    @duckdb.prepare_fixed_join_inputs(
      native_query,
      [inputs[1], inputs[0]],
      validation_limits,
      2,
      10000,
    )
    is Err(Validation(InputMismatch)),
  )
  let registry = @connector.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, },
      { name: "duckdb", acquisition: false, fixed_compute: true, },
    ],
    2,
    20,
  ).unwrap()
  let quantities : @connector.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let candidate = @local_connector.local_fixed_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    generated,
    [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(10L), }],
    quantities,
    100,
  ).unwrap()
  let native_compute = @duckdb.prepare_fixed_join_compute(native_inputs, 2).unwrap()
  assert_eq(@duckdb.fixed_compute_import_count(native_compute), 2)
  assert_true(@duckdb.fixed_compute_import(native_compute, 2) is None)
  let native_candidate = @duckdb_compute.duckdb_bound_compute_candidate(
    @connector.capability_registration_at(registry, 1).unwrap(),
    request,
    native_compute,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
    quantities,
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [
        @connector.prepared_compute_candidate(candidate),
        @connector.prepared_compute_candidate(native_candidate),
      ],
      None,
      100,
    ).unwrap()
    is Proposed(native_choice) else {
    abort("native join candidate")
  }
  let native_transport : FixedComputeTestTransport = { settled: None, }
  let native_attempt = @duckdb_compute.start_duckdb_compute_attempt(
    native_choice,
    native_candidate,
    generated,
    fixed_compute_attempt_limits(),
    current => {
      native_transport.settled is Some(expected) &&
      physical_equal(current, expected)
    },
  ).unwrap()
  @duckdb_compute.begin_duckdb_compute_result(native_attempt, [
    ("left", @duckdb.Float64),
    ("right", @duckdb.Float64),
  ]).unwrap()
  for bits in ["[\"4008000000000000\"]", "[\"4000000000000000\"]"] {
    @duckdb_compute.receive_duckdb_compute_chunk(native_attempt, 1, [
      input_cursor(bits),
      input_cursor(bits),
    ]).unwrap()
  }
  @duckdb_compute.finish_duckdb_compute_result(native_attempt).unwrap()
  native_transport.settled = Some(native_attempt)
  let native_output = @duckdb_compute.complete_duckdb_compute_attempt(
    native_attempt,
  ).unwrap()
  for (row, expected) in [(0, 3.0), (1, 2.0)] {
    for column in 0..<2 {
      assert_true(
        @execution.completed_cell(native_output, row, column) is Some(Number(v)) &&
        v == expected,
      )
    }
  }
  let unfinished = @duckdb_compute.start_duckdb_compute_attempt(
    native_choice,
    native_candidate,
    generated,
    fixed_compute_attempt_limits(),
    _ => true,
  ).unwrap()
  @duckdb_compute.begin_duckdb_compute_result(unfinished, [
    ("left", @duckdb.Float64),
    ("right", @duckdb.Float64),
  ]).unwrap()
  // A lower selected join ceiling is enforced at chunk admission, not after
  // a later count. The two inputs remain independently admitted at two rows.
  let bounded = @duckdb.prepare_fixed_join_compute(native_inputs, 1).unwrap()
  let limits = fixed_compute_attempt_limits()
  let receiving = @duckdb.prepare_fixed_compute_receiving(
    bounded,
    [("left", @duckdb.Float64), ("right", @duckdb.Float64)],
    limits.physical,
    limits.retention,
    limits.metadata_work,
  ).unwrap()
  assert_true(
    @duckdb.receive_fixed_compute_chunk(receiving, 2, [
      input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
      input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
    ])
    is Err(Physical(RowLimit)),
  )
  assert_true(
    @duckdb.finish_fixed_compute_receiving(receiving) is Err(InvalidState),
  )
  assert_true(
    @duckdb_compute.duckdb_fixed_compute_candidate(
      @connector.capability_registration_at(registry, 1).unwrap(),
      request,
      "input",
      native_compile_limits(),
      [],
      quantities,
      100,
    )
    is Err(Request(UnsupportedInputShape)),
  )
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(candidate)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("Local join candidate")
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 1000,
    max_bytes: 1000,
    max_nodes: 1000,
    max_depth: 100,
  }
  let completed = @local_connector.execute_local_fixed_compute(
    choice,
    candidate,
    compute_test_limits(),
    measurement~,
  ).unwrap()
  let output = @execution.completed_output(completed, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  for (row, expected) in [(0, 3.0), (1, 2.0)] {
    for column in 0..<2 {
      assert_true(
        @execution.completed_cell(output, row, column) is Some(Number(v)) &&
        v == expected,
      )
    }
  }
  @planning.close_mock_query_issuer(issuer)
  assert_true(
    @duckdb_compute.finish_duckdb_compute_result(unfinished)
    is Err(Receiving(InputUnavailable)),
  )
  assert_true(
    @duckdb_compute.complete_duckdb_compute_attempt(unfinished)
    is Err(InvalidState),
  )
  assert_true(
    @duckdb_compute.start_duckdb_compute_attempt(
      native_choice,
      native_candidate,
      generated,
      fixed_compute_attempt_limits(),
      _ => true,
    )
    is Err(ForeignPreparation),
  )
  assert_false(@duckdb.fixed_join_inputs_available(native_inputs))
  assert_false(
    @execution.fixed_join_validation_matches(
      validated, receiver, profile, inputs,
    ),
  )
  assert_true(
    @connector.prepare_fixed_compute_request(inputs, capacity)
    is Err(InputUnavailable),
  )
  assert_true(
    @local_connector.execute_local_fixed_compute(
      choice,
      candidate,
      compute_test_limits(),
      measurement~,
    )
    is Err(Guard(ForeignInput)),
  )
  let downstream_owner = typed_receiver(
    receiver,
    "[{\"select\":[\"left\"]}]",
    target=Step(0),
  )
  assert_true(
    @execution.bind_completed_input(downstream_owner, 0, receiver, output)
    is Ok(_),
  )
  let native_bound = @execution.bind_completed_input(
    downstream_owner, 0, receiver, native_output,
  ).unwrap()
  let downstream = @execution.execute_generated_sequence(
    compute_test_sequence(downstream_owner),
    [],
    compute_test_limits(),
    produced=[native_bound],
  ).unwrap()
  assert_eq(
    @execution.completed_row_count(
      @execution.completed_output(downstream, Step(0)).unwrap(),
    ),
    2,
  )
  @duckdb_compute.close_duckdb_compute_attempt(native_attempt)
  assert_true(
    @execution.bind_completed_input(
      downstream_owner, 0, receiver, native_output,
    )
    is Err(_),
  )
  assert_eq(
    @execution.completed_row_count(
      @execution.completed_output(downstream, Step(0)).unwrap(),
    ),
    2,
  )
}
