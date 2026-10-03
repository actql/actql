///|
fn broad_host_completion_limits() -> @duckdb_query.DuckDBBroadCompletionLimits {
  {
    execution: compute_test_limits(),
    guards: query_guard_physical(),
    retention: {
      received_wire_bytes: 28,
      retained_wire_bytes: 47,
      measurement: {
        max_columns: 10,
        max_order_work: 1000,
        max_bytes: 47,
        max_nodes: 12,
        max_depth: 10,
      },
    },
    records: query_material_limits(),
    capture: query_capture_limits(),
  }
}

///|
test "broad capture orchestration preserves exact authority, independent wire and duplicate success" {
  let f = broad_issuer_fixture()
  let foreign = broad_issuer_fixture()
  let attempt = broad_issued_attempt(f)
  broad_attempt_receive(attempt)
  f.transport.push(attempt)
  let limits = broad_host_completion_limits()
  assert_true(
    @duckdb_query.complete_duckdb_broad_capture(foreign.issuer, attempt, limits)
    is Err(UnauthorizedAttempt),
  )
  let observation = @duckdb_query.complete_duckdb_broad_capture(
    f.issuer,
    attempt,
    limits,
  ).unwrap()
  let (expected, _) = query_observation_oracle(
    f.requirement,
    @duckdb_query.duckdb_broad_attempt_identity(attempt).unwrap(),
    "[{\"id\":3},{\"id\":1},{\"id\":2}]",
    3,
    "[\"id\"]",
    "[{\"id\":3},{\"id\":2}]",
    2,
  )
  assert_eq(
    @encode.document_text(
      @duckdb_query.duckdb_broad_observation_document(observation),
    ),
    expected,
  )
  assert_true(
    @duckdb_query.complete_duckdb_broad_capture(f.issuer, attempt, limits)
    is Err(AlreadyCaptured),
  )
  let owner = @query.query_sequence_owner(f.sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  assert_true(
    @duckdb_query.bind_captured_duckdb_broad_input(
      f.issuer,
      attempt,
      observation,
      receiver,
      0,
      owner,
    )
    is Ok(_),
  )
  @duckdb_query.close_duckdb_query_issuer(f.issuer)
  assert_true(
    @duckdb_query.complete_duckdb_broad_capture(f.issuer, attempt, limits)
    is Err(IssuerClosed),
  )
}

///|
test "broad capture orchestration fails closed for incomplete transport and exhausted artifacts" {
  let f = broad_issuer_fixture()
  let early = broad_issued_attempt(f)
  broad_attempt_receive(early)
  let limits = broad_host_completion_limits()
  assert_true(
    @duckdb_query.complete_duckdb_broad_capture(f.issuer, early, limits)
    is Err(UnverifiedTransport),
  )
  f.transport.push(early)
  assert_true(
    @duckdb_query.complete_duckdb_broad_capture(f.issuer, early, limits)
    is Err(BroadAttempt(InvalidState)),
  )
  let exhausted = broad_issued_attempt(f)
  broad_attempt_receive(exhausted)
  f.transport.push(exhausted)
  assert_true(
    @duckdb_query.complete_duckdb_broad_capture(f.issuer, exhausted, {
      ..limits,
      capture: { ..limits.capture, max_bytes: 0, },
    })
    is Err(Encoding(_)),
  )
  assert_true(
    @duckdb_query.complete_duckdb_broad_capture(f.issuer, exhausted, limits)
    is Err(BroadAttempt(InvalidState)),
  )
  let unfinished = broad_issued_attempt(f)
  f.transport.push(unfinished) // transport alone never completes the row lifecycle
  assert_true(
    @duckdb_query.complete_duckdb_broad_capture(f.issuer, unfinished, limits)
    is Err(BroadAttempt(InvalidState)),
  )
}

///|
test "broad bounded residual handoff preserves exact authority and scan custody" {
  for revoke in 0..<3 {
    let f = broad_issuer_fixture()
    let foreign = broad_issuer_fixture()
    let attempt = broad_issued_attempt(f)
    broad_attempt_receive(attempt)
    f.transport.push(attempt)
    assert_true(
      @duckdb_query.prepare_duckdb_broad_capture_input(foreign.issuer, attempt)
      is Err(UnauthorizedAttempt),
    )
    let receipt = @duckdb_query.prepare_duckdb_broad_capture_input(
      f.issuer,
      attempt,
    ).unwrap()
    assert_true(
      @duckdb_query.duckdb_broad_capture_input_live(f.issuer, attempt, receipt),
    )
    assert_false(
      @duckdb_query.duckdb_broad_capture_input_live(
        foreign.issuer,
        attempt,
        receipt,
      ),
    )
    assert_eq(
      @execution.captured_row_count(@query.query_receipt_rows(receipt)),
      3,
    )
    // Admission has not executed a filter, produced an output or issued records.
    assert_true(@duckdb_query.duckdb_broad_attempt_row_count(attempt) is None)
    if revoke == 0 {
      @duckdb_query.close_duckdb_query_issuer(f.issuer)
    } else if revoke == 1 {
      f.transport.clear()
    } else {
      @duckdb_query.abort_duckdb_broad_attempt(attempt)
    }
    assert_false(
      @duckdb_query.duckdb_broad_capture_input_live(f.issuer, attempt, receipt),
    )
  }
  let f = broad_issuer_fixture()
  let unverified = broad_issued_attempt(f)
  broad_attempt_receive(unverified)
  assert_true(
    @duckdb_query.prepare_duckdb_broad_capture_input(f.issuer, unverified)
    is Err(UnverifiedTransport),
  )
  let unfinished = broad_issued_attempt(f)
  f.transport.push(unfinished)
  assert_true(
    @duckdb_query.prepare_duckdb_broad_capture_input(f.issuer, unfinished)
    is Err(BroadAttempt(InvalidState)),
  )
}

///|
test "settled broad scan runs through bounded Local without granting capture" {
  for cancel in [false, true] {
    let f = broad_issuer_fixture()
    let attempt = broad_issued_attempt(f)
    broad_attempt_receive(attempt)
    f.transport.push(attempt)
    let receipt = @duckdb_query.prepare_duckdb_broad_capture_input(
      f.issuer,
      attempt,
    ).unwrap()
    let live = fn() {
      @duckdb_query.duckdb_broad_capture_input_live(f.issuer, attempt, receipt)
    }
    let limits = dispatch_test_limits()
    let residual = @client_local_host.prepare_client_query_residual(
      max_name_bytes=10000,
      f.sequence,
      receipt,
      live,
      limits.local_execution,
      limits.guards,
      100,
      10000,
    ).unwrap()
    let active = @client_local_host.client_query_residual_execution(residual)
    let mut terminal = false
    let mut requested = false
    let mut used = 0L
    for _ in 0..<1000 {
      if terminal {
        break
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work~, ..) => {
          assert_true(work <= 1L)
          used += work
          if cancel && !requested && used > 0L {
            assert_true(@local_connector.cancel_managed_provider(active))
            requested = true
            // A stop request does not revoke the attempt's borrowed input.
            assert_true(live())
          }
        }
        @local_connector.Complete(output, work~, ..) => {
          assert_false(cancel)
          assert_true(work <= 1L)
          assert_eq(@execution.completed_row_count(output), 2)
          assert_true(
            @execution.completed_cell(output, 0, 0) is Some(Number(3)),
          )
          assert_true(
            @execution.completed_cell(output, 1, 0) is Some(Number(2)),
          )
          assert_true(
            @execution.completed_output_matches_captured_inputs(output, [
              @query.query_receipt_rows(receipt),
            ]),
          )
          let other = @query.admit_query_receipt(
            f.sequence,
            [
              input_cursor("{\"id\":3}"),
              input_cursor("{\"id\":1}"),
              input_cursor("{\"id\":2}"),
            ],
            3,
            run_limits().input_values,
          ).unwrap()
          assert_false(
            @execution.completed_output_matches_captured_inputs(output, [
              @query.query_receipt_rows(other),
            ]),
          )
          terminal = true
        }
        @local_connector.Stopped(..) => {
          assert_true(requested)
          assert_true(
            @client_local_host.client_query_residual_output(
              residual,
              f.sequence,
              receipt,
              100,
              10000,
            )
            is None,
          )
          terminal = true
        }
        _ => fail("bounded acquisition residual failed")
      }
    }
    assert_true(terminal)
    assert_true(@local_connector.managed_provider_stopped(active))
    assert_true(@duckdb_query.duckdb_broad_attempt_row_count(attempt) is None)
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(
      @client_local_host.client_query_residual_output(
        residual,
        f.sequence,
        receipt,
        100,
        10000,
      )
      is None,
    )
    @duckdb_query.abort_duckdb_broad_attempt(attempt)
    assert_false(live())
  }
}

///|
test "bounded residual capture retains cleanup custody without repeating Compute" {
  for retention_failure in [false, true] {
    let f = broad_issuer_fixture()
    let attempt = broad_issued_attempt(f)
    broad_attempt_receive(attempt)
    f.transport.push(attempt)
    let receipt = @duckdb_query.prepare_duckdb_broad_capture_input(
      f.issuer,
      attempt,
    ).unwrap()
    let base = broad_host_completion_limits()
    let limits = if retention_failure {
      { ..base, retention: { ..base.retention, received_wire_bytes: 0, }, }
    } else {
      base
    }
    let guards = @planning.query_requirement_guards(f.requirement)
    let residual = @client_local_host.prepare_client_query_residual(
      f.sequence,
      receipt,
      fn() {
        @duckdb_query.duckdb_broad_capture_input_live(
          f.issuer,
          attempt,
          receipt,
        )
      },
      limits.execution,
      {
        max_work: limits.guards.max_work,
        max_bytes: limits.guards.max_bytes,
        max_nodes: limits.guards.max_nodes,
        max_depth: limits.guards.max_depth,
      },
      guards.max_rows,
      guards.max_value_bytes,
      max_name_bytes=10000,
    ).unwrap()
    let active = @client_local_host.client_query_residual_execution(residual)
    assert_true(
      @client_local_host.complete_client_broad_query_residual(
        residual,
        f.issuer,
        attempt,
        limits,
      )
      is Err(BroadAttempt(InvalidState)),
    )
    let mut done = false
    for _ in 0..<1000 {
      if done {
        break
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work~, ..) => assert_true(work <= 1L)
        @local_connector.Complete(_, ..) => done = true
        _ => fail("bounded residual did not complete")
      }
    }
    assert_true(done)
    let work = @local_connector.managed_provider_cumulative_work(active).unwrap()
    assert_true(
      @client_local_host.complete_client_broad_query_residual(
        residual,
        f.issuer,
        attempt,
        {
          ..limits,
          guards: { ..limits.guards, max_work: limits.guards.max_work + 1, },
        },
      )
      is Err(BroadAttempt(InvalidState)),
    )
    let cleanup_calls = Ref(0)
    let result = if retention_failure {
      // Inject a transient cleanup failure at the trusted composition boundary.
      @duckdb_query.complete_duckdb_broad_bounded_capture(
        f.issuer,
        attempt,
        receipt,
        fn(query, input, guards, _) {
          @client_local_host.client_query_residual_output(
            residual,
            query,
            input,
            guards.max_rows,
            guards.max_value_bytes,
          )
        },
        fn() {
          cleanup_calls.val += 1
          if cleanup_calls.val == 1 {
            return Err(@connector.InvalidLimits)
          }
          @local_connector.cleanup_managed_provider(active)
        },
        limits,
      )
    } else {
      @client_local_host.complete_client_broad_query_residual(
        residual,
        f.issuer,
        attempt,
        limits,
      )
    }
    if retention_failure {
      assert_true(result is Err(BroadAttempt(Retention(_))))
      assert_true(@duckdb_query.duckdb_broad_attempt_row_count(attempt) is None)
      assert_true(
        @duckdb_query.cleanup_duckdb_broad_residual(attempt)
        is Err(@connector.InvalidLimits),
      )
      assert_eq(cleanup_calls.val, 1)
      assert_true(
        @client_local_host.client_query_residual_output(
          residual,
          f.sequence,
          receipt,
          guards.max_rows,
          guards.max_value_bytes,
        )
        is Some(_),
      )
    } else {
      let observation = result.unwrap()
      let (expected, _) = query_observation_oracle(
        f.requirement,
        @duckdb_query.duckdb_broad_attempt_identity(attempt).unwrap(),
        "[{\"id\":3},{\"id\":1},{\"id\":2}]",
        3,
        "[\"id\"]",
        "[{\"id\":3},{\"id\":2}]",
        2,
      )
      assert_eq(
        @encode.document_text(
          @duckdb_query.duckdb_broad_observation_document(observation),
        ),
        expected,
      )
      // Successful capture owns the residual until issuer revocation.
      assert_false(
        @duckdb_query.cleanup_duckdb_broad_residual(attempt).unwrap(),
      )
      assert_true(
        @client_local_host.client_query_residual_output(
          residual,
          f.sequence,
          receipt,
          guards.max_rows,
          guards.max_value_bytes,
        )
        is Some(_),
      )
      @duckdb_query.close_duckdb_query_issuer(f.issuer)
    }
    assert_true(@duckdb_query.cleanup_duckdb_broad_residual(attempt).unwrap())
    assert_true(@duckdb_query.cleanup_duckdb_broad_residual(attempt).unwrap())
    if retention_failure {
      assert_eq(cleanup_calls.val, 2)
    }
    assert_true(
      @client_local_host.client_query_residual_output(
        residual,
        f.sequence,
        receipt,
        guards.max_rows,
        guards.max_value_bytes,
      )
      is None,
    )
    assert_eq(
      @local_connector.managed_provider_cumulative_work(active),
      Ok(work),
    )
  }
}

///|
test "configured broad Host uses owned consumer binding with no acquisition data copies" {
  let f = broad_issuer_fixture()
  let (query, evidence) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query,
    evidence,
    query_capture_limits(),
  ).unwrap()
  let configuration = @acquisition_host.configure_broad_host(
    contracts,
    f.requirement,
    f.choice,
    f.prepared,
    {
      physical: { max_rows: 3, max_cells: 3, max_nodes: 3, max_text_bytes: 0, },
      metadata_work: 100,
      retention: run_limits().input_values,
      completion: broad_host_completion_limits(),
      transport: {
        max_bytes: 10000,
        max_nodes: 100,
        max_columns: 10,
        max_rows: 3,
        max_text_bytes: 1000,
      },
    },
  )
  @duckdb_query.close_duckdb_query_issuer(f.issuer)
  let run = @acquisition_host.start_configured_broad_host(
    configuration,
    "configured-broad",
    attempt => f.transport.any(value => physical_equal(value, attempt)),
  ).unwrap()
  @acquisition_host.broad_host_metadata(
    run,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  @acquisition_host.begin_broad_host_receipt(run, [("id", @duckdb.Float64)]).unwrap()
  @acquisition_host.accept_broad_host_chunk(run, 3, [
    input_cursor(
      "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
    ),
  ]).unwrap()
  @acquisition_host.finish_broad_host_receipt(run).unwrap()
  f.transport.push(@acquisition_host.broad_host_attempt(run))
  let observation = @acquisition_host.complete_broad_host(run).unwrap()
  let capture = @acquisition_host.capture_broad_host_source(run, observation).unwrap()
  let source = @acquisition_host.broad_host_source_capture_source(capture).unwrap()
  assert_true(@query.captured_source_available(source))
  assert_eq(
    @acquisition_host.broad_host_source_capture_observation_cid(capture),
    Some(@duckdb_query.duckdb_broad_observation_cid(observation)),
  )
  assert_true(
    physical_equal(
      source,
      @acquisition_host.broad_host_source_capture_source(capture).unwrap(),
    ),
  )
  let foreign_run = @acquisition_host.start_configured_broad_host(
    configuration,
    "foreign-broad",
    _ => true,
  ).unwrap()
  assert_true(
    @acquisition_host.capture_broad_host_source(foreign_run, observation)
    is Err(Unavailable),
  )
  @acquisition_host.close_broad_host(foreign_run)
  let owner = @query.query_sequence_owner(f.sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let bound = @acquisition_host.bind_broad_host_input(
    run, observation, receiver, 0,
  ).unwrap()
  let completed = @execution.execute_generated_sequence(
    compute_test_sequence(receiver),
    [],
    compute_test_limits(),
    produced=[bound],
  ).unwrap()
  let output = @execution.completed_output(completed, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
  @acquisition_host.abort_broad_host(run)
  assert_true(
    @acquisition_host.bind_broad_host_input(run, observation, receiver, 0)
    is Ok(_),
  )
  @acquisition_host.close_broad_host(run)
  @acquisition_host.close_broad_host(run)
  assert_true(
    @acquisition_host.broad_host_source_capture_source(capture)
    is Err(Unavailable),
  )
  assert_false(@query.captured_source_available(source))
  assert_eq(
    @acquisition_host.broad_host_source_capture_observation_cid(capture),
    None,
  )
  assert_true(
    @acquisition_host.bind_broad_host_input(run, observation, receiver, 0)
    is Err(InvalidState),
  )
  assert_true(@acquisition_host.complete_broad_host(run) is Err(InvalidState))
}
