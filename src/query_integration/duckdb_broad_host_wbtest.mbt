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
    @acquisition_host.bind_broad_host_input(run, observation, receiver, 0)
    is Err(InvalidState),
  )
  assert_true(@acquisition_host.complete_broad_host(run) is Err(InvalidState))
}
