///|
test "source-free fixed requests expose no ordered input ports" {
  let owner = zero_input_request_owner(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":7}]},\"as\":\"seed\"}]",
  )
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }
  let request = @connector.prepare_source_free_fixed_compute_request(
    owner, capacity,
  ).unwrap()
  assert_eq(@connector.fixed_compute_request_input_count(request), 0)
  assert_eq(@connector.fixed_compute_request_inputs(request).length(), 0)
  assert_true(@connector.fixed_compute_request_input(request, 0) is None)
  assert_false(@connector.fixed_compute_request_has_supplied_input(request))
  let selected = @connector.prepare_selected_fixed_compute_request_with_inputs(
    owner,
    0,
    [],
    capacity,
  ).unwrap()
  assert_eq(@connector.fixed_compute_request_input_count(selected), 0)
  assert_eq(@connector.fixed_compute_request_inputs(selected).length(), 0)
}

///|
test "selected fixed requests bind the checked operation input" {
  let input = duckdb_captured_input(filter="id > 2")
  let owner = @execution.producer_read_receiver(input)
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }
  assert_true(
    @connector.prepare_selected_fixed_compute_request(
      owner,
      0,
      [input],
      capacity,
    )
    is Ok(_),
  )
  assert_true(
    @connector.prepare_selected_fixed_compute_request(
      owner,
      1,
      [input],
      capacity,
    )
    is Err(@connector.UnsupportedInputShape),
  )
  assert_true(
    @connector.prepare_selected_fixed_compute_request(
      owner,
      0,
      [input, input],
      capacity,
    )
    is Err(@connector.UnsupportedInputShape),
  )
}

///|
test "registered fixed Compute candidates keep the same capture and Local execution budgets" {
  let registry = @connector.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, effect: false, },
      { name: "duckdb", acquisition: true, fixed_compute: true, effect: false, },
      {
        name: "source-only",
        acquisition: true,
        fixed_compute: false,
        effect: false,
      },
    ],
    3,
    22,
  ).unwrap()
  let local_registration = @connector.capability_registration_at(registry, 0).unwrap()
  let duckdb_registration = @connector.capability_registration_at(registry, 1).unwrap()
  let input = duckdb_captured_input(filter="id > 2")
  let request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  assert_true(
    physical_equal(
      @execution.fixed_relation_read_completed(
        @connector.fixed_compute_request_input(request, 0).unwrap(),
      ).unwrap(),
      input,
    ),
  )
  let generated = query_generated(@execution.producer_read_receiver(input))
  let exported_inputs = @connector.fixed_compute_request_inputs(request)
  assert_true(
    physical_equal(
      @execution.fixed_relation_read_completed(exported_inputs[0]).unwrap(),
      input,
    ),
  )
  exported_inputs.clear()
  assert_eq(@connector.fixed_compute_request_input_count(request), 1)
  assert_true(
    physical_equal(
      @execution.fixed_relation_read_completed(
        @connector.fixed_compute_request_input(request, 0).unwrap(),
      ).unwrap(),
      input,
    ),
  )
  let capacity = @connector.fixed_compute_request_capacity(request)
  assert_eq(capacity.max_rows, 100)
  assert_eq(capacity.max_value_bytes, 10000)
  assert_true(
    @connector.prepare_fixed_compute_request([input], {
      ..capacity,
      contract_cid: "sha256:wrong",
    })
    is Err(CapacityContract),
  )
  assert_true(
    @connector.prepare_fixed_compute_request([input], {
      ..capacity,
      max_rows: -1,
    })
    is Err(InvalidLimits),
  )
  // Two retained input rows cannot escape a common limit of one by selecting
  // a native filter that publishes just one row.
  assert_true(
    @connector.prepare_fixed_compute_request([input], {
      ..capacity,
      max_rows: 1,
    })
    is Err(CommonInputRows),
  )
  assert_true(
    @connector.prepare_fixed_compute_request([input], {
      ..capacity,
      max_rows: 2,
    })
    is Ok(_),
  )
  let quantities : @connector.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let local_estimate : Array[@cost.SerialEstimateLine] = [
    { work_slots: [0, 1, 2, 3, 4], milliseconds: Some(5L), },
  ]
  // Public SDK construction is still bounded and owned. A private payload is
  // recoverable only through this exact proposal, never through equal content.
  let sdk = @connector.bind_compute_candidate(
    local_registration, request, "opaque-payload", 5, local_estimate, quantities,
    100,
  ).unwrap()
  let profile = @numeric.builtin_profile()
  let support = @connector.numeric_reduction_support(
    @numeric.cid(profile),
    @numeric.member_cid_at(profile, 0).unwrap(),
  ).unwrap()
  let declarations = [support]
  let numeric_sdk = @connector.bind_compute_candidate(
    local_registration,
    request,
    "numeric-payload",
    5,
    local_estimate,
    quantities,
    100,
    numeric_reductions=declarations,
  ).unwrap()
  declarations.clear()
  let numeric_candidate = @connector.prepared_compute_candidate(numeric_sdk)
  assert_eq(
    @connector.fixed_compute_candidate_numeric_reduction_count(
      numeric_candidate,
    ),
    1,
  )
  assert_eq(
    @connector.numeric_reduction_support_member_cid(
      @connector.fixed_compute_candidate_numeric_reduction_at(
        numeric_candidate, 0,
      ).unwrap(),
    ),
    @numeric.member_cid_at(profile, 0).unwrap(),
  )
  assert_true(
    @connector.bind_compute_candidate(
      local_registration,
      request,
      "duplicate-profile",
      5,
      local_estimate,
      quantities,
      100,
      numeric_reductions=[support, support],
    )
    is Err(InvalidLimits),
  )
  let equal_sdk = @connector.bind_compute_candidate(
    local_registration, request, "opaque-payload", 5, local_estimate, quantities,
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(sdk)],
      None,
      100,
    )
    is Ok(Proposed(sdk_choice)) else {
    fail("owned SDK proposal")
  }
  assert_eq(
    @connector.fixed_compute_choice_payload(sdk_choice, sdk),
    Some("opaque-payload"),
  )
  assert_true(
    @connector.fixed_compute_choice_payload(sdk_choice, equal_sdk) is None,
  )
  assert_true(
    @connector.bind_compute_candidate(
      local_registration,
      request,
      "opaque-payload",
      5,
      local_estimate,
      { ..quantities, transfer_bytes: Some(-1L), },
      100,
    )
    is Err(NegativeQuantity),
  )
  assert_true(
    @connector.bind_compute_candidate(
      local_registration, request, "opaque-payload", 5, local_estimate, quantities,
      0,
    )
    is Err(Cost(PlanningLimit)),
  )
  let common = @connector.prepare_fixed_compute_request([input], {
    ..capacity,
    common_fragment: Some(
      @execution.generated_sequence_requirements(generated, 100).unwrap(),
    ),
  }).unwrap()
  assert_true(
    @local_connector.local_fixed_compute_candidate(
      local_registration, common, generated, local_estimate, quantities, 100,
    )
    is Ok(_),
  )
  assert_true(
    @local_connector.local_fixed_compute_candidate(
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
    @duckdb_compute.duckdb_fixed_compute_candidate(
      duckdb_registration,
      common,
      "owned_input",
      native_compile_limits(),
      [],
      quantities,
      100,
    )
    is Err(Request(CommonFragmentUnsupported)),
  )
  let local_binding = @local_connector.local_fixed_compute_candidate(
    local_registration, request, generated, local_estimate, quantities, 100,
  ).unwrap()
  let duckdb_binding = @duckdb_compute.duckdb_fixed_compute_candidate(
    duckdb_registration,
    request,
    "owned_input",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(40L), }],
    quantities,
    100,
  ).unwrap()
  let local_candidate = @connector.prepared_compute_candidate(local_binding)
  for ceiling in [0, 4, 5] {
    let guarded_request = @connector.prepare_fixed_compute_request([input], {
      ..capacity,
      max_value_bytes: ceiling,
    }).unwrap()
    let guarded = @local_connector.local_fixed_compute_candidate(
      local_registration, guarded_request, generated, local_estimate, quantities,
      100,
    ).unwrap()
    guard @connector.choose_fixed_compute_candidate(
        registry,
        guarded_request,
        [@connector.prepared_compute_candidate(guarded)],
        None,
        100,
      ).unwrap()
      is Proposed(guarded_choice) else {
      abort("guarded Local")
    }
    let run = @local_connector.execute_local_fixed_compute(
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
          @local_connector.execute_local_fixed_compute(
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
          @local_connector.execute_local_fixed_compute(
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
  let duckdb_candidate = @connector.prepared_compute_candidate(duckdb_binding)
  guard @connector.choose_fixed_compute_candidate(
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
    @connector.fixed_compute_choice_reason(choice) is EstimatedFastest(0, 5L),
  )
  assert_true(
    @connector.fixed_compute_choice_payload(choice, duckdb_binding) is None,
  )
  assert_true(
    @local_connector.execute_local_fixed_compute(
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
    let completed = @local_connector.execute_local_fixed_compute(
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
  let fast = @duckdb_compute.duckdb_fixed_compute_candidate(
    duckdb_registration,
    request,
    "owned_input",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
    quantities,
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [local_candidate, @connector.prepared_compute_candidate(fast)],
      None,
      100,
    ).unwrap()
    is Proposed(native_choice) else {
    abort("expected DuckDB")
  }
  let compiled = @connector.fixed_compute_choice_payload(native_choice, fast).unwrap()
  assert_true(
    physical_equal(
      @duckdb.fixed_import_input(
        @duckdb.fixed_compute_import(compiled, 0).unwrap(),
      ),
      input,
    ),
  )
  assert_eq(
    @duckdb.fixed_query_sql(@duckdb.fixed_compute_query(compiled)),
    "SELECT \"id\" AS \"id\" FROM \"main\".\"owned_input\" WHERE CAST(\"id\" AS DOUBLE) > ?",
  )
  assert_true(
    @local_connector.execute_local_fixed_compute(
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
  let unknown = @duckdb_compute.duckdb_fixed_compute_candidate(
    duckdb_registration,
    request,
    "owned_input",
    native_compile_limits(),
    [{ work_slots: [0, 2, 3, 4, 5, 6, 7], milliseconds: Some(0L), }],
    quantities,
    100,
  ).unwrap()
  assert_true(
    @connector.fixed_compute_candidate_duration(
      @connector.prepared_compute_candidate(unknown),
    )
    is Unknown,
  )
  assert_true(
    @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [local_candidate, @connector.prepared_compute_candidate(unknown)],
      None,
      100,
    )
    is Ok(Deferred),
  )
  let other_request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  assert_true(
    @connector.choose_fixed_compute_candidate(
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
    @local_connector.local_fixed_compute_candidate(
      local_registration,
      request,
      query_generated(@execution.producer_read_receiver(other_input)),
      local_estimate,
      quantities,
      100,
    )
    is Err(ForeignPreparation),
  )
  let source_registration = @connector.capability_registration_at(registry, 2).unwrap()
  assert_true(
    @local_connector.local_fixed_compute_candidate(
      source_registration, request, generated, local_estimate, quantities, 100,
    )
    is Err(ComputeUnsupported),
  )
  @connector.close_capability_registry(registry)
  assert_true(@connector.fixed_compute_choice_payload(sdk_choice, sdk) is None)
  assert_true(
    @connector.fixed_compute_choice_payload(native_choice, fast) is None,
  )
  assert_true(
    @local_connector.execute_local_fixed_compute(
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
