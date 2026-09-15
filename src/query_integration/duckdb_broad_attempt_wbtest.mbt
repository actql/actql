///|
fn broad_attempt_fixture(
  max_rows? : Int = 2,
) -> @duckdb_query.DuckDBBroadAttempt raise {
  let checked = query_checked_program_fixture()
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(
      query_checked_sequence(checked),
      query_material_limits(),
    ).unwrap(),
    @program_check.source_identity(checked),
    { max_rows, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  @duckdb_query.prepare_duckdb_broad_attempt(
    @duckdb_query.prepare_duckdb_query(
      requirement,
      "main",
      "records",
      10,
      native_compile_limits(),
    ).unwrap(),
  )
}

///|
fn broad_attempt_receive(attempt : @duckdb_query.DuckDBBroadAttempt) -> Unit {
  @duckdb_query.admit_duckdb_broad_metadata(
    attempt,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  @duckdb_query.begin_duckdb_broad_receipt(
    attempt,
    [("id", @duckdb.Float64)],
    { max_rows: 3, max_cells: 3, max_nodes: 3, max_text_bytes: 0, },
    100,
    run_limits().input_values,
  ).unwrap()
  @duckdb_query.accept_duckdb_broad_chunk(attempt, 3, [
    input_cursor(
      "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
    ),
  ]).unwrap()
  @duckdb_query.finish_duckdb_broad_receipt(attempt).unwrap()
}

///|
test "broad attempt cannot run residual before transport settlement" {
  let measurement : @query.QueryGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let early = broad_attempt_fixture()
  broad_attempt_receive(early)
  assert_true(@duckdb_query.duckdb_broad_attempt_row_count(early) is None)
  assert_true(
    @duckdb_query.execute_duckdb_broad_attempt(
      early,
      compute_test_limits(),
      measurement,
    )
    is Err(InvalidState),
  )
  assert_true(
    @duckdb_query.settle_duckdb_broad_transport(early) is Err(InvalidState),
  )
  assert_true(@duckdb_query.duckdb_broad_attempt_row_count(early) is None)
  let success = broad_attempt_fixture()
  broad_attempt_receive(success)
  @duckdb_query.settle_duckdb_broad_transport(success).unwrap()
  assert_true(@duckdb_query.duckdb_broad_attempt_row_count(success) is None)
  @duckdb_query.execute_duckdb_broad_attempt(
    success,
    compute_test_limits(),
    measurement,
  ).unwrap()
  assert_eq(@duckdb_query.duckdb_broad_attempt_row_count(success), Some(2))
  let failure = broad_attempt_fixture(max_rows=1)
  broad_attempt_receive(failure)
  @duckdb_query.settle_duckdb_broad_transport(failure).unwrap()
  assert_true(
    @duckdb_query.execute_duckdb_broad_attempt(
      failure,
      compute_test_limits(),
      measurement,
    )
    is Err(Residual(OutputRows)),
  )
  assert_true(@duckdb_query.duckdb_broad_attempt_row_count(failure) is None)
  assert_true(
    @duckdb_query.execute_duckdb_broad_attempt(
      failure,
      compute_test_limits(),
      measurement,
    )
    is Err(InvalidState),
  )
}

///|
test "cancelled or invalid broad attempts cannot be revived by metadata or settlement" {
  for received in [false, true] {
    let attempt = broad_attempt_fixture()
    if received {
      broad_attempt_receive(attempt)
    }
    @duckdb_query.abort_duckdb_broad_attempt(attempt)
    assert_true(@duckdb_query.duckdb_broad_attempt_row_count(attempt) is None)
    assert_true(
      @duckdb_query.settle_duckdb_broad_transport(attempt) is Err(InvalidState),
    )
    assert_true(
      @duckdb_query.admit_duckdb_broad_metadata(
        attempt,
        1,
        [("table_type", @duckdb.Varchar)],
        [input_cursor("[\"BASE TABLE\"]")],
      )
      is Err(InvalidState),
    )
  }
  let invalid = broad_attempt_fixture()
  assert_true(
    @duckdb_query.admit_duckdb_broad_metadata(
      invalid,
      1,
      [("table_type", @duckdb.Varchar)],
      [input_cursor("[\"VIEW\"]")],
    )
    is Err(Metadata(NotBaseTable)),
  )
  assert_true(
    @duckdb_query.finish_duckdb_broad_receipt(invalid) is Err(InvalidState),
  )
}
