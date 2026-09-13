///|
// Test-only command export. Native execution expectations are independently
// specified by the real Node transport test, not inferred from these commands.
test "DuckDB native two receipt transport fixture" {
  let (_, owner) = query_sequence_fixture(
    catalog=Some(query_amount_nullable_catalog()),
  )
  let query = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "records",
    native_compile_limits(),
  ).unwrap()
  let scan = @duckdb.prepare_native_scan(query, 2, 1000).unwrap()
  let writer = @encode.writer(10000, 1000, 10)
  @encode.begin_object(writer)
  for
    (name, value) in [
      ("metadata", @duckdb.native_scan_metadata_sql(scan)),
      ("validation", @duckdb.native_scan_sql(scan)),
      ("native", @duckdb.native_query_sql(query)),
    ] {
    @encode.key(writer, name)
    @encode.string_value(writer, value)
  }
  @encode.key(writer, "metadataParameters")
  @encode.begin_array(writer)
  for index in 0..<2 {
    @duckdb.emit_physical_parameter(
      @duckdb.native_scan_metadata_parameter(scan, index).unwrap(),
      writer,
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "nativeParameters")
  @encode.begin_array(writer)
  @duckdb.emit_physical_parameter(@duckdb.native_query_parameter(query), writer)
  @encode.end_array(writer)
  @encode.end_object(writer)
  println("ACTQL_DUCKDB_NATIVE_FIXTURE " + @encode.finish(writer))
}
