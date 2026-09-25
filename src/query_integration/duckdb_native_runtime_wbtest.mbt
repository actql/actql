///|
fn native_runtime_command(
  database : @native_duckdb.Database,
  sql : String,
) -> Unit raise {
  let query = database.stream_query(sql, 1, 1L, 1, 256).unwrap()
  while query.next().unwrap() is Some(_) {

  }
  assert_true(query.close())
}

///|
fn native_runtime_limits() -> @acquisition_host.NativeHostLimits {
  {
    physical: { max_rows: 5, max_cells: 5, max_nodes: 5, max_text_bytes: 0, },
    metadata_work: 100,
    measurement: native_demand_physical(),
    completion: native_completion_limits(),
    retention: { max_nodes: 8, max_text_bytes: 8, max_depth: 2, max_work: 32, },
    output_rows: 2,
    output_entries: 100,
    output_name_bytes: 10000,
    transport: {
      max_bytes: 1024,
      max_nodes: 32,
      max_columns: 4,
      max_rows: 2,
      max_text_bytes: 128,
    },
  }
}

///|
fn native_runtime_setup(
  limits : @acquisition_host.NativeHostLimits,
) -> @acquisition_host.NativeHostConfiguration raise {
  let fixture = native_issuer_fixture()
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
  @duckdb_query.close_duckdb_native_issuer(fixture.issuer)
  @acquisition_host.configure_native_host(
    contract,
    fixture.requirement,
    fixture.choice,
    fixture.candidate,
    limits,
  )
}

///|
test "native DuckDB executes the portable acquisition Host without Node" {
  guard native_duckdb_test_library() is Some(path) else { return }
  let library = @native_duckdb.load_library(path).unwrap()
  let database = library
    .open_database(@native_duckdb.restricted_open_limits(134217728L))
    .unwrap()
  native_runtime_command(database, "CREATE TABLE records(id DOUBLE)")
  native_runtime_command(
    database, "INSERT INTO records VALUES (3.0), (1.0), (2.0)",
  )
  let limits = native_runtime_limits()
  let runtime = @native_host.start_native_acquisition_runtime(
    native_runtime_setup(limits),
    "native-runtime",
    database,
  ).unwrap()
  @native_host.execute_native_acquisition_runtime(runtime).unwrap() |> ignore
  let output = @native_host.native_acquisition_runtime_output(runtime).unwrap()
  assert_eq(
    @execution.admitted_output_row_count(
      @duckdb_query.duckdb_native_output_rows(output).unwrap(),
    ),
    2,
  )
  @native_host.close_native_acquisition_runtime(runtime)
  @native_host.close_native_acquisition_runtime(runtime)
}

///|
test "native acquisition failure rolls back before releasing its Host attempt" {
  guard native_duckdb_test_library() is Some(path) else { return }
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database(@native_duckdb.restricted_open_limits(134217728L))
    .unwrap()
  let limits = native_runtime_limits()
  let runtime = @native_host.start_native_acquisition_runtime(
    native_runtime_setup(limits),
    "native-runtime-failure",
    database,
  ).unwrap()
  assert_true(
    @native_host.execute_native_acquisition_runtime(runtime) is Err(_),
  )
  database.begin_transaction().unwrap()
  database.rollback_transaction().unwrap()
  assert_true(@native_host.native_acquisition_runtime_output(runtime) is Err(_))
  @native_host.close_native_acquisition_runtime(runtime)
}
