///|
// The Node conformance harness runs this test to obtain actual MoonBit-generated
// commands. Only a test fixture serializes the whole tiny input. Expected native
// rows are fixed independently in the Node test, never derived from this output.
test "DuckDB transport command fixture from completed capture" {
  let input = duckdb_captured_input(filter="id > 2")
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "owned_input",
    native_compile_limits(),
  ).unwrap()
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
