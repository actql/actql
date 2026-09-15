///|
fn host_native_fixture() -> (
  @acquisition_host.NativeHostRun,
  Array[@duckdb_query.DuckDBNativeAttempt],
) raise {
  let f = native_issuer_fixture()
  let (query, evidence) = query_evidence_test_bodies()
  let dependencies = @planning.admit_query_evidence_contracts(
    query,
    evidence,
    query_capture_limits(),
  ).unwrap()
  let contract = @planning.admit_query_two_receipt_contract(
    dependencies,
    query_two_receipt_test_body(),
    query_capture_limits(),
  ).unwrap()
  @duckdb_query.close_duckdb_native_issuer(f.issuer)
  let transport : Array[@duckdb_query.DuckDBNativeAttempt] = []
  let run = @acquisition_host.start_native_host(
    contract,
    f.requirement,
    f.choice,
    f.candidate,
    "portable-host",
    100,
    { max_rows: 5, max_cells: 5, max_nodes: 5, max_text_bytes: 0, },
    100,
    native_demand_physical(),
    attempt => transport.any(value => physical_equal(value, attempt)),
  ).unwrap()
  (run, transport)
}

///|
fn receive_host_native_fixture(run : @acquisition_host.NativeHostRun) -> Unit {
  @acquisition_host.native_host_metadata(
    run,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  for
    (role, rows, cells) in [
      (
        @duckdb.ValidationScan,
        3,
        "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
      ),
      (@duckdb.NativeResult, 2, "[\"4008000000000000\",\"4000000000000000\"]"),
    ] {
    @acquisition_host.begin_native_host_receipt(run, role, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    @acquisition_host.accept_native_host_chunk(run, rows, [input_cursor(cells)]).unwrap()
    @acquisition_host.finish_native_host_receipt(run).unwrap()
  }
}

///|
test "product native Host binds exact capture to consumer without fixed setup or source replay" {
  let (run, transport) = host_native_fixture()
  receive_host_native_fixture(run)
  transport.push(@acquisition_host.native_host_attempt(run))
  let observation = @acquisition_host.complete_native_host(
    run,
    native_completion_limits(),
  ).unwrap()
  assert_true(@acquisition_host.verify_native_host(run, observation))
  assert_true(
    @acquisition_host.complete_native_host(run, native_completion_limits())
    is Err(Evidence(AlreadyCaptured)),
  )
  let owner = @duckdb.native_query_owner(
    @duckdb.native_scan_query(@acquisition_host.native_host_scan(run)),
  )
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let limits : @execution.ValueLimits = {
    max_nodes: 4,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 8,
  }
  assert_true(
    @acquisition_host.bind_native_host_input(
      run, observation, receiver, 0, 1, limits, 100, 10000,
    )
    is Err(Evidence(_)),
  )
  assert_true(@acquisition_host.verify_native_host(run, observation))
  let bound = @acquisition_host.bind_native_host_input(
    run, observation, receiver, 0, 2, limits, 100, 10000,
  ).unwrap()
  let completed = @execution.execute_generated_sequence(
    compute_test_sequence(receiver),
    [],
    compute_test_limits(),
    produced=[bound],
  ).unwrap()
  let output = @execution.completed_output(completed, @pipeline.Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
  let (other, _) = host_native_fixture()
  assert_false(@acquisition_host.verify_native_host(other, observation))
  @acquisition_host.close_native_host(other)
  @acquisition_host.abort_native_host(run)
  assert_true(@acquisition_host.verify_native_host(run, observation))
  @acquisition_host.close_native_host(run)
  @acquisition_host.close_native_host(run)
  assert_false(@acquisition_host.verify_native_host(run, observation))
  assert_true(
    @acquisition_host.bind_native_host_input(
      run, observation, receiver, 0, 2, limits, 100, 10000,
    )
    is Err(InvalidState),
  )
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
}

///|
test "product native Host rejects unverified transport and unfinished or replaced receipt" {
  let (run, _) = host_native_fixture()
  receive_host_native_fixture(run)
  assert_true(
    @acquisition_host.complete_native_host(run, native_completion_limits())
    is Err(Evidence(UnverifiedTransport)),
  )
  @acquisition_host.close_native_host(run)
  let (early, transport) = host_native_fixture()
  transport.push(@acquisition_host.native_host_attempt(early))
  assert_true(
    @acquisition_host.complete_native_host(early, native_completion_limits())
    is Err(Evidence(_)),
  )
  @acquisition_host.close_native_host(early)
  let (replaced, _) = host_native_fixture()
  @acquisition_host.native_host_metadata(
    replaced,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  @acquisition_host.begin_native_host_receipt(
    replaced,
    @duckdb.ValidationScan,
    [("id", @duckdb.Float64)],
  ).unwrap()
  assert_true(
    @acquisition_host.begin_native_host_receipt(
      replaced,
      @duckdb.ValidationScan,
      [("id", @duckdb.Float64)],
    )
    is Err(InvalidState),
  )
  assert_true(
    @acquisition_host.finish_native_host_receipt(replaced) is Err(InvalidState),
  )
  @acquisition_host.close_native_host(replaced)
}
