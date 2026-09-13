///|
test "registered fixed Compute candidates keep the same capture and Local execution budgets" {
  let registry = @planning.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, },
      { name: "duckdb", acquisition: true, fixed_compute: true, },
      { name: "source-only", acquisition: true, fixed_compute: false, },
    ],
    3,
    22,
  ).unwrap()
  let local_registration = @planning.capability_registration_at(registry, 0).unwrap()
  let duckdb_registration = @planning.capability_registration_at(registry, 1).unwrap()
  let input = duckdb_captured_input(filter="id > 2")
  let request = @planning.prepare_fixed_compute_request(input, {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  assert_true(
    physical_equal(@planning.fixed_compute_request_input(request), input),
  )
  let generated = query_generated(@execution.producer_read_receiver(input))
  let capacity = @planning.fixed_compute_request_capacity(request)
  assert_eq(capacity.max_rows, 100)
  assert_eq(capacity.max_value_bytes, 10000)
  assert_true(
    @planning.prepare_fixed_compute_request(input, {
      ..capacity,
      contract_cid: "sha256:wrong",
    })
    is Err(CapacityContract),
  )
  assert_true(
    @planning.prepare_fixed_compute_request(input, { ..capacity, max_rows: -1, })
    is Err(InvalidLimits),
  )
  // Two retained input rows cannot escape a common limit of one by selecting
  // a native filter that publishes just one row.
  assert_true(
    @planning.prepare_fixed_compute_request(input, { ..capacity, max_rows: 1, })
    is Err(CommonInputRows),
  )
  assert_true(
    @planning.prepare_fixed_compute_request(input, { ..capacity, max_rows: 2, })
    is Ok(_),
  )
  let quantities : @planning.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let local_estimate : Array[@cost.SerialEstimateLine] = [
    { work_slots: [0, 1, 2, 3, 4], milliseconds: Some(5L), },
  ]
  let common = @planning.prepare_fixed_compute_request(input, {
    ..capacity,
    common_fragment: Some(generated),
  }).unwrap()
  assert_true(
    @planning.local_fixed_compute_candidate(
      local_registration, common, generated, local_estimate, quantities, 100,
    )
    is Ok(_),
  )
  assert_true(
    @planning.local_fixed_compute_candidate(
      local_registration,
      common,
      query_generated(@execution.producer_read_receiver(input)),
      local_estimate,
      quantities,
      100,
    )
    is Err(ForeignPreparation),
  )
  assert_true(
    @planning.duckdb_fixed_compute_candidate(
      duckdb_registration,
      common,
      "owned_input",
      native_compile_limits(),
      [],
      quantities,
      100,
    )
    is Err(CommonFragmentUnsupported),
  )
  let local_binding = @planning.local_fixed_compute_candidate(
    local_registration, request, generated, local_estimate, quantities, 100,
  ).unwrap()
  let duckdb_binding = @planning.duckdb_fixed_compute_candidate(
    duckdb_registration,
    request,
    "owned_input",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(40L), }],
    quantities,
    100,
  ).unwrap()
  let local_candidate = @planning.prepared_compute_candidate(local_binding)
  for ceiling in [0, 4, 5] {
    let guarded_request = @planning.prepare_fixed_compute_request(input, {
      ..capacity,
      max_value_bytes: ceiling,
    }).unwrap()
    let guarded = @planning.local_fixed_compute_candidate(
      local_registration, guarded_request, generated, local_estimate, quantities,
      100,
    ).unwrap()
    guard @planning.choose_fixed_compute_candidate(
        registry,
        guarded_request,
        [@planning.prepared_compute_candidate(guarded)],
        None,
        100,
      ).unwrap()
      is Proposed(guarded_choice) else {
      abort("guarded Local")
    }
    let run = @planning.execute_local_fixed_compute(
      guarded_choice,
      guarded,
      compute_test_limits(),
      measurement={
        max_work: 10000,
        max_bytes: 3,
        max_nodes: 3,
        max_depth: 100,
      },
    )
    match ceiling {
      0 => assert_true(run is Err(Guard(ValueBytes(InputValues, 0, 0))))
      4 => assert_true(run is Err(Execution(_))) // false root needs five bytes
      _ => {
        assert_true(run is Ok(_))
        // The same ledger spans input and output, with no reset at execution.
        assert_true(
          @planning.execute_local_fixed_compute(
            guarded_choice,
            guarded,
            compute_test_limits(),
            measurement={
              max_work: 10000,
              max_bytes: 2,
              max_nodes: 3,
              max_depth: 100,
            },
          )
          is Err(Guard(Measurement(Output, 0, 0, _))),
        )
        assert_true(
          @planning.execute_local_fixed_compute(
            guarded_choice,
            guarded,
            compute_test_limits(),
            measurement={
              max_work: 10000,
              max_bytes: 3,
              max_nodes: 2,
              max_depth: 100,
            },
          )
          is Err(Guard(Measurement(Output, 0, 0, _))),
        )
      }
    }
  }
  let duckdb_candidate = @planning.prepared_compute_candidate(duckdb_binding)
  guard @planning.choose_fixed_compute_candidate(
      registry,
      request,
      [local_candidate, duckdb_candidate],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("expected Local")
  }
  assert_true(
    @planning.fixed_compute_choice_reason(choice) is EstimatedFastest(0, 5L),
  )
  assert_true(
    @planning.fixed_compute_choice_payload(choice, duckdb_binding) is None,
  )
  assert_true(
    @planning.execute_local_fixed_compute(
      choice,
      local_binding,
      { ..compute_test_limits(), rows: { ..run_limits(), max_rows: 0, }, },
      measurement={
        max_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    )
    is Err(Execution(_)),
  )
  // Receiving failure does not consume the retained upstream or reset its identity.
  for _ in 0..<2 {
    let completed = @planning.execute_local_fixed_compute(
      choice,
      local_binding,
      compute_test_limits(),
      measurement={
        max_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    ).unwrap()
    let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), 1)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_eq(@execution.producer_read_row_count(input), 2)
  }
  // Change cost, not input or canonical meaning. Recover only the selected
  // isolated import/query preparation; no source connection is present.
  let fast = @planning.duckdb_fixed_compute_candidate(
    duckdb_registration,
    request,
    "owned_input",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
    quantities,
    100,
  ).unwrap()
  guard @planning.choose_fixed_compute_candidate(
      registry,
      request,
      [local_candidate, @planning.prepared_compute_candidate(fast)],
      None,
      100,
    ).unwrap()
    is Proposed(native_choice) else {
    abort("expected DuckDB")
  }
  let compiled = @planning.fixed_compute_choice_payload(native_choice, fast).unwrap()
  assert_true(
    physical_equal(
      @duckdb.fixed_import_input(@duckdb.fixed_compute_import(compiled)),
      input,
    ),
  )
  assert_eq(
    @duckdb.native_query_sql(@duckdb.fixed_compute_query(compiled)),
    "SELECT \"id\" AS \"id\" FROM \"main\".\"owned_input\" WHERE CAST(\"id\" AS DOUBLE) > ?",
  )
  assert_true(
    @planning.execute_local_fixed_compute(
      native_choice,
      local_binding,
      compute_test_limits(),
      measurement={
        max_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    )
    is Err(NotSelected),
  )
  let unknown = @planning.duckdb_fixed_compute_candidate(
    duckdb_registration,
    request,
    "owned_input",
    native_compile_limits(),
    [{ work_slots: [0, 2, 3, 4, 5, 6, 7], milliseconds: Some(0L), }],
    quantities,
    100,
  ).unwrap()
  assert_true(
    @planning.fixed_compute_candidate_duration(
      @planning.prepared_compute_candidate(unknown),
    )
    is Unknown,
  )
  assert_true(
    @planning.choose_fixed_compute_candidate(
      registry,
      request,
      [local_candidate, @planning.prepared_compute_candidate(unknown)],
      None,
      100,
    )
    is Ok(Deferred),
  )
  let other_request = @planning.prepare_fixed_compute_request(input, {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  assert_true(
    @planning.choose_fixed_compute_candidate(
      registry,
      other_request,
      [local_candidate],
      None,
      100,
    )
    is Err(ForeignRequest(0)),
  )
  let other_input = duckdb_captured_input(filter="id > 2")
  assert_true(
    @planning.local_fixed_compute_candidate(
      local_registration,
      request,
      query_generated(@execution.producer_read_receiver(other_input)),
      local_estimate,
      quantities,
      100,
    )
    is Err(ForeignPreparation),
  )
  let source_registration = @planning.capability_registration_at(registry, 2).unwrap()
  assert_true(
    @planning.local_fixed_compute_candidate(
      source_registration, request, generated, local_estimate, quantities, 100,
    )
    is Err(ComputeUnsupported),
  )
  @planning.close_capability_registry(registry)
  assert_true(
    @planning.fixed_compute_choice_payload(native_choice, fast) is None,
  )
  assert_true(
    @planning.execute_local_fixed_compute(
      choice,
      local_binding,
      compute_test_limits(),
      measurement={
        max_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    )
    is Err(NotSelected),
  )
  assert_eq(@execution.producer_read_row_count(input), 2)
}
