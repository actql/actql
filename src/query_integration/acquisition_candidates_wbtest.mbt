///|
test "common acquisition comparison preserves provider binding and unknown costs" {
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
  let prepared = @planning.prepare_duckdb_query(
    requirement,
    "main",
    "records",
    10,
    native_compile_limits(),
  ).unwrap()
  let quantities : @planning.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let mock_offer = @planning.offer_mock_query(
    sequence,
    @planning.BroadWithResidual,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6], milliseconds: Some(20L), }],
    quantities,
    100,
  ).unwrap()
  let mock = @planning.mock_acquisition_candidate(requirement, mock_offer).unwrap()
  let broad = @planning.duckdb_broad_candidate(
    prepared,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
    quantities,
    100,
  ).unwrap()
  let unknown = @planning.duckdb_broad_candidate(
    prepared,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6], milliseconds: Some(1L), }],
    quantities,
    100,
  ).unwrap()
  assert_true(@planning.acquisition_candidate_duration(unknown) is Unknown)
  assert_true(
    @planning.choose_acquisition_candidate(
      requirement,
      [mock, unknown],
      None,
      100,
    )
    is Ok(Deferred),
  )
  assert_true(
    @planning.duckdb_broad_candidate(
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
      requirement,
      candidates,
      None,
      100,
    ).unwrap()
    guard selected is Proposed(choice) else { abort("expected cost proposal") }
    let candidate = @planning.acquisition_choice_candidate(choice)
    guard @planning.acquisition_candidate_binding(candidate)
      is DuckDBBroad(selected) else {
      abort("expected DuckDB broad binding")
    }
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
    let (completed, _) = @planning.execute_duckdb_broad_residual(
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
  let equal = @planning.duckdb_broad_candidate(
    prepared,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(20L), }],
    quantities,
    100,
  ).unwrap()
  guard @planning.choose_acquisition_candidate(
      requirement,
      [mock, equal],
      Some([1, 0]),
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("expected tie proposal")
  }
  assert_true(
    @planning.acquisition_candidate_binding(
      @planning.acquisition_choice_candidate(choice),
    )
    is DuckDBBroad(_),
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
    @planning.choose_acquisition_candidate(duplicate, [broad], None, 100)
    is Err(ForeignQuery(0)),
  )
}
