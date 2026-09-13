///|
// The Node conformance harness runs this test to obtain actual MoonBit-generated
// commands. Only a test fixture serializes the whole tiny input. Expected native
// rows are fixed independently in the Node test, never derived from this output.
test "registered DuckDB transport command fixture from completed capture" {
  let input = duckdb_captured_input(filter="id > 2")
  let registry = @planning.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, },
      { name: "duckdb", acquisition: true, fixed_compute: true, },
    ],
    2,
    11,
  ).unwrap()
  let request = @planning.prepare_fixed_compute_request(input, {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  let quantities : @planning.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let local_binding = @planning.local_fixed_compute_candidate(
    @planning.capability_registration_at(registry, 0).unwrap(),
    request,
    query_generated(@execution.producer_read_receiver(input)),
    [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(20L), }],
    quantities,
    100,
  ).unwrap()
  let native_binding = @planning.duckdb_fixed_compute_candidate(
    @planning.capability_registration_at(registry, 1).unwrap(),
    request,
    "owned_input",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
    quantities,
    100,
  ).unwrap()
  guard @planning.choose_fixed_compute_candidate(
      registry,
      request,
      [
        @planning.prepared_compute_candidate(local_binding),
        @planning.prepared_compute_candidate(native_binding),
      ],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("expected native proposal")
  }
  assert_true(
    @planning.fixed_compute_choice_reason(choice) is EstimatedFastest(1, 10L),
  )
  let compute = @planning.fixed_compute_choice_payload(choice, native_binding).unwrap()
  let imported = @duckdb.fixed_compute_import(compute)
  let query = @duckdb.fixed_compute_query(compute)
  assert_true(
    physical_equal(
      @duckdb.native_query_owner(query),
      @execution.producer_read_receiver(input),
    ),
  )
  let writer = @encode.writer(10000, 1000, 10)
  @encode.begin_object(writer)
  @encode.key(writer, "create")
  @encode.string_value(writer, @duckdb.fixed_import_create_sql(imported))
  @encode.key(writer, "insert")
  @encode.string_value(writer, @duckdb.fixed_import_insert_sql(imported))
  @encode.key(writer, "query")
  @encode.string_value(writer, @duckdb.native_query_sql(query))
  @encode.key(writer, "parameters")
  @encode.begin_array(writer)
  @duckdb.emit_physical_parameter(@duckdb.native_query_parameter(query), writer)
  @encode.end_array(writer)
  @encode.key(writer, "rows")
  @encode.begin_array(writer)
  for row in 0..<@execution.producer_read_row_count(input) {
    @encode.begin_array(writer)
    for column in 0..<@duckdb.fixed_import_column_count(imported) {
      @duckdb.emit_physical_parameter(
        @duckdb.fixed_import_parameter(imported, row, column).unwrap(),
        writer,
      )
    }
    @encode.end_array(writer)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  println("ACTQL_DUCKDB_FIXTURE " + @encode.finish(writer))
}
