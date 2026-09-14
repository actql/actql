///|
test "common input value guard precedes join cardinality in both realizations" {
  let (issuer, acquisition) = query_issuer_fixture()
  let owner = @query.query_sequence_owner(acquisition)
  let receiver = typed_receiver(
    owner, "[{\"join\":{\"with\":\"prior\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"cardinality\":\"one_to_one\",\"select\":{\"id\":\"left.id\"}}}]",
  )
  let generated = @execution.prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["join_0"],
    100000,
    10000,
  ).unwrap()
  let acquisition_attempt = @planning.prepare_issued_mock_query_attempt(
    issuer,
    strategy_for(acquisition, @planning.BroadWithResidual),
    [input_cursor("{\"id\":3}"), input_cursor("{\"id\":3}")],
    2,
  ).unwrap()
  query_issuer_run(acquisition_attempt)
  let records = @planning.issue_mock_query_records(
    acquisition_attempt,
    query_material_limits(),
  ).unwrap()
  let observation = @planning.capture_mock_query(
    issuer,
    acquisition_attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let binding = @planning.bind_captured_query_input(
    issuer, acquisition_attempt, observation, receiver, 0, owner,
  ).unwrap()
  let inputs = [
    @execution.prepare_producer_read(receiver, binding, 100, 1000).unwrap(),
  ]
  let query = @duckdb.compile_fixed_inner_join(
    receiver,
    "main",
    ["owned_input"],
    native_compile_limits(),
  ).unwrap()
  // Binding must not fail on the duplicate before common guards are selected.
  let imported = @duckdb.prepare_fixed_join_inputs(
    query,
    inputs,
    { max_rows: 2, max_work: 10000, max_entries: 100, },
    2,
    10000,
  ).unwrap()
  let compute = @duckdb.prepare_fixed_join_compute(imported, 100).unwrap()
  let registry = search_registry()
  let quantities : @planning.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  for ceiling in [0, 100] {
    let request = @planning.prepare_fixed_compute_request(inputs, {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 2,
      max_value_bytes: ceiling,
      common_fragment: None,
    }).unwrap()
    let local_candidate = @planning.local_fixed_compute_candidate(
      @planning.capability_registration_at(registry, 0).unwrap(),
      request,
      generated,
      [],
      quantities,
      100,
    ).unwrap()
    let native = @planning.duckdb_bound_compute_candidate(
      @planning.capability_registration_at(registry, 1).unwrap(),
      request,
      compute,
      [],
      quantities,
      100,
    ).unwrap()
    guard @planning.choose_fixed_compute_candidate(
        registry,
        request,
        [@planning.prepared_compute_candidate(local_candidate)],
        Some([0]),
        100,
      ).unwrap()
      is Proposed(local_choice) else {
      abort("local choice")
    }
    guard @planning.choose_fixed_compute_candidate(
        registry,
        request,
        [@planning.prepared_compute_candidate(native)],
        Some([0]),
        100,
      ).unwrap()
      is Proposed(native_choice) else {
      abort("native choice")
    }
    let limits = fixed_compute_attempt_limits()
    let local_result = @planning.execute_local_fixed_compute(
      local_choice,
      local_candidate,
      compute_test_limits(),
      measurement=limits.values,
    )
    let native_result = @planning.start_duckdb_compute_attempt(
      native_choice,
      native,
      generated,
      limits,
      _ => false,
    )
    if ceiling == 0 {
      assert_true(local_result is Err(Guard(ValueBytes(InputValues, 0, 0))))
      assert_true(native_result is Err(Guard(ValueBytes(InputValues, 0, 0))))
    } else {
      assert_true(
        local_result is Err(Execution(Rows(0, JoinDuplicateKey(true, 1, 0)))),
      )
      assert_true(
        native_result is Err(JoinValidation(JoinDuplicateKey(true, 1, 0))),
      )
    }
  }
  @planning.close_mock_query_issuer(issuer)
  assert_false(@duckdb.fixed_join_inputs_available(imported))
}
