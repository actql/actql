///|
fn query_guard_physical() -> @query.QueryGuardMeasureLimits {
  { max_work: 10000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, }
}

///|
test "query root guard does not demand a lazy failing branch or cap a whole row as one cell" {
  let (query, bound) = query_sequence_fixture(
    filter="if(id > 0, true, 1 / (id - id) > 0)",
  )
  let sequence = @query.prepare_query_sequence(
    query,
    query_generated(bound),
    10000,
  ).unwrap()
  let receipt = @query.admit_query_receipt(
    sequence,
    [input_cursor("{\"id\":1}")],
    1,
    run_limits().input_values,
  ).unwrap()
  let (completed, _) = @query.execute_query_receipt_guarded(
    sequence,
    receipt,
    compute_test_limits(),
    max_output_rows=1,
    max_value_bytes=4,
    query_guard_physical(),
  ).unwrap()
  assert_eq(
    @execution.completed_row_count(
      @execution.completed_output(completed, @pipeline.Step(1)).unwrap(),
    ),
    1,
  )
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=1,
      max_value_bytes=3,
      query_guard_physical(),
    )
    is Err(
      Execution(
        Execution(
          Rows(
            0,
            Evaluation(
              0,
              0,
              { kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }
            )
          )
        )
      )
    ),
  )
}

///|
test "query guards measure complete scan before demanded failure and preserve reusable preparation" {
  let (query, bound) = query_sequence_fixture(filter="1 / (id - id) > 0")
  let sequence = @query.prepare_query_sequence(
    query,
    query_generated(bound),
    10000,
  ).unwrap()
  let receipt = @query.admit_query_receipt(
    sequence,
    [input_cursor("{\"id\":1}"), input_cursor("{\"id\":123456}")],
    2,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=0,
      max_value_bytes=5,
      query_guard_physical(),
    )
    is Err(ValueBytes(Scan, 1, 0)),
  )
  // Raising the value ceiling exposes the demanded expression failure, before
  // the output-row ceiling. Neither failed run changes the checked preparation.
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=0,
      max_value_bytes=10,
      query_guard_physical(),
    )
    is Err(Execution(Execution(Rows(_, _)))),
  )
}

///|
test "query guard byte ceiling applies to predicate roots without changing demand" {
  let sequence = strategy_test_owner()
  let receipt = @query.admit_query_receipt(
    sequence,
    [input_cursor("{\"id\":1}")],
    1,
    run_limits().input_values,
  ).unwrap()
  // The input number is one byte, but false is five. No output row is needed
  // for the demanded predicate root to enforce its own value ceiling.
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=0,
      max_value_bytes=4,
      query_guard_physical(),
    )
    is Err(Execution(Execution(Rows(_, _)))),
  )
  let (completed, _) = @query.execute_query_receipt_guarded(
    sequence,
    receipt,
    compute_test_limits(),
    max_output_rows=0,
    max_value_bytes=5,
    query_guard_physical(),
  ).unwrap()
  assert_eq(
    @execution.completed_row_count(
      @execution.completed_output(completed, @pipeline.Step(1)).unwrap(),
    ),
    0,
  )
  let empty = @query.admit_query_receipt(
    sequence,
    [],
    0,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      empty,
      compute_test_limits(),
      max_output_rows=0,
      max_value_bytes=0,
      query_guard_physical(),
    )
    is Ok(_),
  )
}

///|
test "query guard measurement shares physical counters across scan and output" {
  let sequence = strategy_test_owner()
  let receipt = @query.admit_query_receipt(
    sequence,
    [
      input_cursor("{\"id\":3}"),
      input_cursor("{\"id\":1}"),
      input_cursor("{\"id\":2}"),
    ],
    3,
    run_limits().input_values,
  ).unwrap()
  let limits = query_guard_physical()
  let (completed, usage) = @query.execute_query_receipt_guarded(
    sequence,
    receipt,
    compute_test_limits(),
    max_output_rows=2,
    max_value_bytes=5,
    limits,
  ).unwrap()
  assert_eq(usage, (11, 5, 5)) // five rows + five cells + one context copy
  assert_true(
    @execution.completed_cell(
      @execution.completed_output(completed, @pipeline.Step(1)).unwrap(),
      0,
      0,
    )
    is Some(Number(3)),
  )
  let exact = { ..limits, max_work: 11, max_bytes: 5, max_nodes: 5, }
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      exact,
    )
    is Ok(_),
  )
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      { ..exact, max_work: 10, },
    )
    is Err(MeasurementWork),
  )
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      { ..exact, max_bytes: 4, },
    )
    is Err(Measurement(Output, 1, 0, _)),
  )
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      { ..exact, max_nodes: 4, },
    )
    is Err(Measurement(Output, 1, 0, _)),
  )
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=1,
      max_value_bytes=5,
      exact,
    )
    is Err(OutputRows),
  )
  let other = strategy_test_owner()
  assert_true(
    @query.execute_query_receipt_guarded(
      other,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      exact,
    )
    is Err(ForeignReceipt),
  )
}

///|
test "both mock realizations enforce their exact requirement before capture" {
  let (program, sequence) = query_program_fixture()
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let requirement = @planning.prepare_query_requirement(
    material,
    program,
    { max_rows: 1, max_value_bytes: 5, },
    query_material_limits(),
  ).unwrap()
  let rows = [input_cursor("{\"id\":3}"), input_cursor("{\"id\":2}")]
  for route in [@planning.NativeQuery, @planning.BroadWithResidual] {
    let strategy = strategy_for(sequence, route)
    let attempt = @planning.prepare_requirement_mock_query_attempt(
      requirement, strategy, rows, 2,
    ).unwrap()
    assert_true(
      @planning.execute_mock_query(attempt, mock_strategy_limits())
      is Err(GuardLimitsRequired),
    )
    assert_true(@planning.mock_query_computation(attempt) is Err(NotComputed))
    assert_true(
      @planning.execute_mock_query(
        attempt,
        mock_strategy_limits(),
        guard_measure=Some(query_guard_physical()),
      )
      is Err(Guard(OutputRows)),
    )
    assert_true(
      @planning.mock_query_computation(attempt) is Err(Guard(OutputRows)),
    )
    assert_true(
      @planning.execute_mock_query(
        attempt,
        mock_strategy_limits(),
        guard_measure=Some(query_guard_physical()),
      )
      is Err(AlreadyStarted),
    )
    let next = @planning.prepare_requirement_mock_query_attempt(
      requirement,
      strategy,
      [rows[0]],
      1,
    ).unwrap()
    let result = @planning.execute_mock_query(
      next,
      mock_strategy_limits(),
      guard_measure=Some(query_guard_physical()),
    ).unwrap()
    assert_eq(@planning.mock_query_output_rows(result), 1)
    assert_true(@planning.cancel_mock_query(next))
  }
  let foreign = strategy_for(strategy_test_owner(), @planning.NativeQuery)
  assert_true(
    @planning.prepare_requirement_mock_query_attempt(
      requirement, foreign, rows, 2,
    )
    is Err(ForeignRequirement),
  )
}
