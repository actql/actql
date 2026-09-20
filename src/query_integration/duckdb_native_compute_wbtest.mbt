///|
fn native_compute_transport_limits() -> @duckdb.TransportColumnLimits {
  {
    max_bytes: 4096,
    max_nodes: 128,
    max_columns: 8,
    max_rows: 2,
    max_text_bytes: 512,
  }
}

///|
fn native_compute_import_limits() -> @native_host.NativeComputeImportLimits {
  {
    max_rows: 10,
    max_cells: 40,
    max_parameters: 8,
    max_sql_bytes: 10000,
    max_batch_rows: 2,
  }
}

///|
fn native_compute_setup(
  input : @execution.ProducerRead,
  transport? : @duckdb.TransportColumnLimits = native_compute_transport_limits(),
) -> @duckdb_driver.ComputeHostConfiguration raise {
  let request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 2,
    max_value_bytes: 5,
    common_fragment: None,
  }).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "duckdb", acquisition: false, fixed_compute: true, }],
    1,
    6,
  ).unwrap()
  let prepared = @duckdb_compute.duckdb_fixed_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    "fixed",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("fixed proposal")
  }
  @duckdb_driver.configure_compute_host(
    choice,
    prepared,
    @execution.generated_completion_preparation(
      query_generated(@execution.producer_read_receiver(input)),
    ),
    fixed_compute_attempt_limits(),
    transport,
  )
}

///|
test "native fixed Compute rolls back a failed physical transaction" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let input = duckdb_captured_input(filter="id > 2")
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database()
    .unwrap()
  let runtime = @native_host.start_native_compute_runtime(
    native_compute_setup(input, transport={
      ..native_compute_transport_limits(),
      max_bytes: 1,
    }),
    database,
    native_compute_import_limits(),
  ).unwrap()
  assert_true(@native_host.execute_native_compute_runtime(runtime) is Err(_))
  assert_true(
    @native_host.execute_native_compute_runtime(runtime)
    is Err({ primary: RuntimeState, rollback: None, }),
  )
  database.begin_transaction().unwrap()
  database.rollback_transaction().unwrap()
  assert_true(@native_host.native_compute_runtime_output(runtime) is Err(_))
  @native_host.close_native_compute_runtime(runtime)
}

///|
test "native DuckDB executes portable fixed Compute without Node" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let input = duckdb_captured_input(filter="id > 2")
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database()
    .unwrap()
  let runtime = @native_host.start_native_compute_runtime(
    native_compute_setup(input),
    database,
    native_compute_import_limits(),
  ).unwrap()
  let output = @native_host.execute_native_compute_runtime(runtime).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(
    physical_equal(
      @native_host.native_compute_runtime_output(runtime).unwrap(),
      output,
    ),
  )
  @native_host.close_native_compute_runtime(runtime)
  @native_host.close_native_compute_runtime(runtime)
  assert_true(@native_host.native_compute_runtime_output(runtime) is Err(_))
}

///|
test "native fixed Compute rejects import capacity before execution" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let input = duckdb_captured_input(filter="id > 2")
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database()
    .unwrap()
  assert_true(
    @native_host.start_native_compute_runtime(
      native_compute_setup(input),
      database,
      { ..native_compute_import_limits(), max_cells: 1, },
    )
    is Err(ImportCells),
  )
  assert_true(database.begin_transaction() is Err(_))
}
