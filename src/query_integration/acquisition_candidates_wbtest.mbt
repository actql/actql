///|
test "common acquisition comparison preserves provider binding and unknown costs" {
  let registry = @connector.prepare_capability_registry(
    [
      { name: "mock", acquisition: true, fixed_compute: false, },
      { name: "duckdb", acquisition: true, fixed_compute: true, },
      { name: "local", acquisition: false, fixed_compute: true, },
    ],
    3,
    15,
  ).unwrap()
  let mock_registration = @connector.capability_registration_at(registry, 0).unwrap()
  let duckdb_registration = @connector.capability_registration_at(registry, 1).unwrap()
  let checked = query_checked_program_fixture()
  let sequence = query_checked_sequence(checked)
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let requirement = @planning.prepare_query_requirement(
    material,
    @program_check.source_identity(checked),
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let prepared = @duckdb_query.prepare_duckdb_query(
    requirement,
    "main",
    "records",
    10,
    native_compile_limits(),
  ).unwrap()
  let quantities : @connector.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let mock_offer = @mock.offer_mock_query(
    sequence,
    @mock.BroadWithResidual,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6], milliseconds: Some(20L), }],
    quantities,
    100,
  ).unwrap()
  // The public connector construction boundary cannot bypass cost/quantity
  // validation or fabricate a selected payload. It grants no execution rights.
  assert_true(
    @planning.bind_acquisition_candidate(
      mock_registration,
      requirement,
      (),
      @cost.Complete(-1L),
      quantities,
    )
    is Err(NegativeQuantity),
  )
  assert_true(
    @planning.bind_acquisition_candidate(
      mock_registration,
      requirement,
      (),
      @cost.Unknown,
      { ..quantities, retained_bytes: Some(-1L), },
    )
    is Err(NegativeQuantity),
  )
  let mock_binding = @mock.mock_acquisition_candidate(
    mock_registration, requirement, mock_offer,
  ).unwrap()
  let mock = @planning.prepared_acquisition_candidate(mock_binding)
  let broad_binding = @duckdb_query.duckdb_broad_candidate(
    duckdb_registration,
    prepared,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
    quantities,
    100,
  ).unwrap()
  let broad = @planning.prepared_acquisition_candidate(broad_binding)
  let unknown_binding = @duckdb_query.duckdb_broad_candidate(
    duckdb_registration,
    prepared,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6], milliseconds: Some(1L), }],
    quantities,
    100,
  ).unwrap()
  let unknown = @planning.prepared_acquisition_candidate(unknown_binding)
  assert_true(@planning.acquisition_candidate_duration(unknown) is Unknown)
  assert_true(
    @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [mock, unknown],
      None,
      100,
    )
    is Ok(Deferred),
  )
  assert_true(
    @duckdb_query.duckdb_broad_candidate(
      duckdb_registration,
      prepared,
      [
        { work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), },
        { work_slots: [2], milliseconds: Some(1L), },
      ],
      quantities,
      100,
    )
    is Err(Cost(DuplicateSlot(2))),
  )
  for candidates in [[mock, broad], [broad, mock]] {
    let selected = @planning.choose_acquisition_candidate(
      registry,
      requirement,
      candidates,
      None,
      100,
    ).unwrap()
    guard selected is Proposed(choice) else { abort("expected cost proposal") }
    let candidate = @planning.acquisition_choice_candidate(choice)
    assert_true(
      physical_equal(
        @planning.acquisition_candidate_registration(candidate),
        duckdb_registration,
      ),
    )
    let selected = @planning.acquisition_choice_payload(choice, broad_binding).unwrap()
    assert_true(
      @planning.acquisition_choice_payload(choice, mock_binding) is None,
    )
    assert_true(physical_equal(selected, prepared))
    let input = @execution.capture_input(
      @query.query_sequence_owner(sequence),
      0,
      [
        input_cursor("{\"id\":3}"),
        input_cursor("{\"id\":1}"),
        input_cursor("{\"id\":2}"),
      ],
      max_rows=3,
      run_limits().input_values,
    ).unwrap()
    let (completed, _) = @duckdb_query.execute_duckdb_broad_residual(
      selected,
      input,
      compute_test_limits(),
      { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    ).unwrap()
    let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
  }
  let equal_binding = @duckdb_query.duckdb_broad_candidate(
    duckdb_registration,
    prepared,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(20L), }],
    quantities,
    100,
  ).unwrap()
  let equal = @planning.prepared_acquisition_candidate(equal_binding)
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [mock, equal],
      Some([1, 0]),
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("expected tie proposal")
  }
  assert_true(
    @planning.acquisition_choice_payload(choice, equal_binding) is Some(_),
  )
  assert_true(
    @planning.acquisition_choice_payload(choice, broad_binding) is None,
  )
  let foreign_registry = @connector.prepare_capability_registry(
    [{ name: "duckdb", acquisition: true, fixed_compute: true, }],
    1,
    6,
  ).unwrap()
  assert_true(
    @planning.choose_acquisition_candidate(
      foreign_registry,
      requirement,
      [broad],
      None,
      100,
    )
    is Err(ForeignCapability(0)),
  )
  let local_registration = @connector.capability_registration_at(registry, 2).unwrap()
  assert_true(
    @mock.mock_acquisition_candidate(
      local_registration, requirement, mock_offer,
    )
    is Err(AcquisitionUnsupported),
  )
  let duplicate = @planning.prepare_query_requirement(
    material,
    @program_check.source_identity(checked),
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  assert_eq(
    @planning.query_requirement_cid(duplicate),
    @planning.query_requirement_cid(requirement),
  )
  assert_true(
    @planning.choose_acquisition_candidate(
      registry,
      duplicate,
      [broad],
      None,
      100,
    )
    is Err(ForeignQuery(0)),
  )
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [mock, equal],
      Some([0, 1]),
      100,
    ).unwrap()
    is Proposed(mock_choice) else {
    abort("expected mock tie choice")
  }
  let strategy = @mock.mock_acquisition_strategy(mock_choice, mock_binding).unwrap()
  assert_true(
    @planning.acquisition_choice_payload(mock_choice, equal_binding) is None,
  )
  let attempt = @mock.prepare_requirement_mock_query_attempt(
    requirement,
    strategy,
    [
      input_cursor("{\"id\":3}"),
      input_cursor("{\"id\":1}"),
      input_cursor("{\"id\":2}"),
    ],
    3,
  ).unwrap()
  let computed = @mock.execute_mock_query(
    attempt,
    mock_strategy_limits(),
    guard_measure=Some(query_guard_physical()),
  ).unwrap()
  assert_eq(@mock.mock_query_output_rows(computed), 2)
  @connector.close_capability_registry(registry)
  assert_true(
    @planning.acquisition_choice_payload(choice, equal_binding) is None,
  )
  assert_true(
    @mock.mock_acquisition_candidate(mock_registration, requirement, mock_offer)
    is Err(CapabilityClosed),
  )
  assert_true(
    @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [broad],
      None,
      100,
    )
    is Err(ForeignCapability(0)),
  )
}
