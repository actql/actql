///|
fn query_guard_physical() -> @query.QueryGuardMeasureLimits {
  { max_work: 10000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, }
}

///|
test "acquisition guards include demanded intermediate roots without evaluating lazy branches" {
  // The admitted record is 8 bytes, predicate false is 5, and the demanded
  // numeric literal is exactly 9. A final-predicate-only guard misses this.
  for filter in ["id > 123456789", "id > (12345678 * 10)"] {
    let (query, bound) = query_sequence_fixture(filter~)
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
    assert_true(
      @query.execute_query_receipt_guarded(
        sequence,
        receipt,
        compute_test_limits(),
        max_output_rows=0,
        max_value_bytes=8,
        query_guard_physical(),
      )
      is Err(Execution(Execution(Rows(_, _)))),
    )
    // Equality succeeds on a new budget after failure; input/preparation survive.
    let (completed, _) = @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=0,
      max_value_bytes=9,
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
  let (query, bound) = query_sequence_fixture(
    filter="if(id > 0, true, id > 123456789)",
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
    max_value_bytes=8,
    query_guard_physical(),
  ).unwrap()
  assert_eq(
    @execution.completed_row_count(
      @execution.completed_output(completed, @pipeline.Step(1)).unwrap(),
    ),
    1,
  )
}

///|
test "bounded acquisition residual preserves demanded root ceilings" {
  for ceiling in [8, 9] {
    let (query, owner) = query_sequence_fixture(filter="id > 123456789")
    let sequence = @query.prepare_query_sequence(
      query,
      query_generated(owner),
      10000,
    ).unwrap()
    let receipt = @query.admit_query_receipt(
      sequence,
      [input_cursor("{\"id\":1}")],
      1,
      run_limits().input_values,
    ).unwrap()
    let limits = dispatch_test_limits()
    let active = match
      @client_local_host.start_client_query_residual(
        max_name_bytes=10000,
        sequence,
        receipt,
        fn() { true },
        limits.local_execution,
        limits.guards,
        100,
        ceiling,
      ) {
      Ok(value) => value
      Err(UnsupportedProgram) => fail("unsupported bounded query prefix")
      Err(Guard(_)) => fail("guard preparation failed")
      Err(Local(_)) => fail("bounded provider start failed")
      Err(_) => fail("bounded query input admission failed")
    }
    let mut terminal = false
    for _ in 0..<1000 {
      if terminal {
        break
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work~, ..) => assert_true(work <= 1L)
        @local_connector.Complete(output, ..) => {
          assert_eq(ceiling, 9)
          assert_eq(@execution.completed_row_count(output), 0)
          terminal = true
        }
        @local_connector.Failed(issue, ..) => {
          assert_eq(ceiling, 8)
          guard issue
            is @connector.Execution(@execution.Rows(0, Evaluation(0, _, cause))) else {
            fail(
              "expected the demanded predicate root to exceed its byte ceiling",
            )
          }
          assert_true(
            cause.kind is LogicalValue(ValueMeasure(WireMeasureFailure)),
          )
          terminal = true
        }
        _ => fail("unexpected bounded residual state")
      }
    }
    assert_true(terminal)
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  }
}

///|
test "bounded query guards share input output allowances and reject unpublished output" {
  let (query, owner) = query_sequence_fixture()
  let sequence = @query.prepare_query_sequence(
    query,
    query_generated(owner),
    10000,
  ).unwrap()
  let receipt = @query.admit_query_receipt(
    sequence,
    [input_cursor("{\"id\":3}")],
    1,
    run_limits().input_values,
  ).unwrap()
  let limits = dispatch_test_limits()
  // Each {"id":3} is eight bytes and two nodes. Each guard takes six
  // frames; two setup steps and one context binding give fifteen guard work.
  for mode in 0..<5 {
    let residual = @client_local_host.prepare_client_query_residual(
      max_name_bytes=10000,
      sequence,
      receipt,
      fn() { true },
      limits.local_execution,
      {
        max_work: if mode == 4 {
          14
        } else {
          15
        },
        max_bytes: if mode == 1 {
          15
        } else {
          16
        },
        max_nodes: 4,
        max_depth: 10,
      },
      if mode == 2 {
        0
      } else {
        1
      },
      if mode == 3 {
        7
      } else {
        8
      },
    ).unwrap()
    let active = @client_local_host.client_query_residual_execution(residual)
    let rows = if mode == 2 { 0 } else { 1 }
    let bytes = if mode == 3 { 7 } else { 8 }
    assert_true(
      @client_local_host.client_query_residual_output(
        residual, sequence, receipt, rows, bytes,
      )
      is None,
    )
    let mut terminal = false
    for _ in 0..<1000 {
      if terminal {
        break
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work~, ..) => assert_true(work <= 1L)
        @local_connector.Complete(output, ..) => {
          assert_eq(mode, 0)
          assert_eq(@execution.completed_row_count(output), 1)
          assert_true(
            @execution.completed_cell(output, 0, 0) is Some(Number(3)),
          )
          let checked = @client_local_host.client_query_residual_output(
            residual, sequence, receipt, rows, bytes,
          ).unwrap()
          assert_true(physical_equal(checked, output))
          let other = @query.admit_query_receipt(
            sequence,
            [input_cursor("{\"id\":3}")],
            1,
            run_limits().input_values,
          ).unwrap()
          assert_true(
            @client_local_host.client_query_residual_output(
              residual, sequence, other, rows, bytes,
            )
            is None,
          )
          assert_true(
            @client_local_host.client_query_residual_output(
              residual,
              sequence,
              receipt,
              rows + 1,
              bytes,
            )
            is None,
          )
          assert_true(
            @client_local_host.client_query_residual_output(
              residual,
              sequence,
              receipt,
              rows,
              bytes + 1,
            )
            is None,
          )
          terminal = true
        }
        @local_connector.Failed(issue, ..) => {
          assert_true(
            @client_local_host.client_query_residual_output(
              residual, sequence, receipt, rows, bytes,
            )
            is None,
          )
          match mode {
            1 =>
              assert_true(
                issue
                is @connector.Guard(
                  @execution.Measurement(Output, 0, -1, OutputLimit)
                ),
              )
            2 => assert_true(issue is @connector.Guard(@execution.OutputRows))
            3 =>
              assert_true(
                issue
                is @connector.Guard(@execution.ValueBytes(InputValues, 0, -1)),
              )
            4 =>
              assert_true(issue is @connector.Guard(@execution.MeasurementWork))
            _ =>
              match issue {
                @connector.Guard(@execution.MeasurementWork) =>
                  fail("exact guard work rejected")
                @connector.Guard(@execution.Measurement(_, _, _, _)) =>
                  fail("exact wire measurement rejected")
                @connector.Execution(_) => fail("exact Compute budget rejected")
                _ => fail("exact acquisition guard budget rejected")
              }
          }
          terminal = true
        }
        _ => fail("unexpected acquisition guard stop")
      }
    }
    assert_true(terminal)
    assert_true(@local_connector.managed_provider_stopped(active))
    let used = @local_connector.managed_provider_cumulative_work(active).unwrap()
    assert_true(used > 0L)
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(
      @client_local_host.client_query_residual_output(
        residual, sequence, receipt, rows, bytes,
      )
      is None,
    )
    assert_eq(
      @local_connector.managed_provider_cumulative_work(active),
      Ok(used),
    )
  }
}

///|
test "query record guard includes field names and preserves lazy branch demand" {
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
    max_value_bytes=8,
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
      max_value_bytes=7,
      query_guard_physical(),
    )
    is Err(ValueBytes(Scan, 0, -1)),
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
      max_value_bytes=12,
      query_guard_physical(),
    )
    is Err(ValueBytes(Scan, 1, -1)),
  )
  // Raising the value ceiling exposes the demanded expression failure, before
  // the output-row ceiling. Neither failed run changes the checked preparation.
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=0,
      max_value_bytes=13,
      query_guard_physical(),
    )
    is Err(Execution(Execution(Rows(_, _)))),
  )
}

///|
test "query record guard precedes false predicate and empty input has no record" {
  let sequence = strategy_test_owner()
  let receipt = @query.admit_query_receipt(
    sequence,
    [input_cursor("{\"id\":1}")],
    1,
    run_limits().input_values,
  ).unwrap()
  // The record is eight bytes although its only scalar is one byte. It must
  // pass before the false predicate; no output does not waive scan validation.
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=0,
      max_value_bytes=7,
      query_guard_physical(),
    )
    is Err(ValueBytes(Scan, 0, -1)),
  )
  let (completed, _) = @query.execute_query_receipt_guarded(
    sequence,
    receipt,
    compute_test_limits(),
    max_output_rows=0,
    max_value_bytes=8,
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
    max_value_bytes=8,
    limits,
  ).unwrap()
  assert_eq(usage, (11, 40, 10)) // five rows + five cells + one context copy
  assert_true(
    @execution.completed_cell(
      @execution.completed_output(completed, @pipeline.Step(1)).unwrap(),
      0,
      0,
    )
    is Some(Number(3)),
  )
  let exact = { ..limits, max_work: 11, max_bytes: 40, max_nodes: 10, }
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=8,
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
      max_value_bytes=8,
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
      max_value_bytes=8,
      { ..exact, max_bytes: 39, },
    )
    is Err(Measurement(Output, 1, -1, _)),
  )
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=8,
      { ..exact, max_nodes: 9, },
    )
    is Err(Measurement(Output, 1, -1, _)),
  )
  assert_true(
    @query.execute_query_receipt_guarded(
      sequence,
      receipt,
      compute_test_limits(),
      max_output_rows=1,
      max_value_bytes=8,
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
      max_value_bytes=8,
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
    { max_rows: 1, max_value_bytes: 8, },
    query_material_limits(),
  ).unwrap()
  let rows = [input_cursor("{\"id\":3}"), input_cursor("{\"id\":2}")]
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let strategy = strategy_for(sequence, route)
    let attempt = @mock.prepare_requirement_mock_query_attempt(
      requirement, strategy, rows, 2,
    ).unwrap()
    assert_true(
      @mock.execute_mock_query(attempt, mock_strategy_limits())
      is Err(GuardLimitsRequired),
    )
    assert_true(@mock.mock_query_computation(attempt) is Err(NotComputed))
    assert_true(
      @mock.execute_mock_query(
        attempt,
        mock_strategy_limits(),
        guard_measure=Some(query_guard_physical()),
      )
      is Err(Guard(OutputRows)),
    )
    assert_true(@mock.mock_query_computation(attempt) is Err(Guard(OutputRows)))
    assert_true(
      @mock.execute_mock_query(
        attempt,
        mock_strategy_limits(),
        guard_measure=Some(query_guard_physical()),
      )
      is Err(AlreadyStarted),
    )
    let next = @mock.prepare_requirement_mock_query_attempt(
      requirement,
      strategy,
      [rows[0]],
      1,
    ).unwrap()
    let result = @mock.execute_mock_query(
      next,
      mock_strategy_limits(),
      guard_measure=Some(query_guard_physical()),
    ).unwrap()
    assert_eq(@mock.mock_query_output_rows(result), 1)
    assert_true(@mock.cancel_mock_query(next))
  }
  let foreign = strategy_for(strategy_test_owner(), @mock.NativeQuery)
  assert_true(
    @mock.prepare_requirement_mock_query_attempt(requirement, foreign, rows, 2)
    is Err(ForeignRequirement),
  )
}
