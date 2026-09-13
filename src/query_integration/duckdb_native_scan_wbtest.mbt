///|
test "native scan covers unused columns and shares exact checked query address" {
  let (_, owner) = query_sequence_fixture(
    catalog=Some(query_amount_nullable_catalog()),
  )
  let query = @duckdb.compile_native_filter_select(
    owner,
    "odd\"schema",
    "source",
    native_compile_limits(),
  ).unwrap()
  let sql = "SELECT \"amount\", \"id\" FROM \"odd\"\"schema\".\"source\""
  let scan = @duckdb.prepare_native_scan(query, 2, sql.length()).unwrap()
  assert_true(physical_equal(@duckdb.native_scan_query(scan), query))
  assert_eq(@duckdb.native_scan_sql(scan), sql)
  assert_eq(
    @duckdb.native_query_sql(query),
    "SELECT \"id\" AS \"id\" FROM \"odd\"\"schema\".\"source\" WHERE CAST(\"id\" AS DOUBLE) > ?",
  )
  assert_true(@duckdb.prepare_native_scan(query, 1, 1000) is Err(Limit))
  assert_true(
    @duckdb.prepare_native_scan(query, 2, sql.length() - 1) is Err(Limit),
  )
  let limits : @duckdb.PhysicalResultLimits = {
    max_rows: 10,
    max_cells: 100,
    max_nodes: 100,
    max_text_bytes: 1000,
  }
  assert_true(
    @duckdb.prepare_scan_validation_receiver(
      scan,
      [("id", @duckdb.Float64)],
      limits,
      1000,
    )
    is Err(SchemaMismatch),
  )
  let validation = @duckdb.prepare_scan_validation_receiver(
    scan,
    [("id", @duckdb.Float64), ("amount", @duckdb.Float64)],
    limits,
    1000,
  ).unwrap()
  let batch = @duckdb.admit_physical_chunk(validation, 1, [
    input_cursor("[\"3ff0000000000000\"]"),
    input_cursor("[null]"),
  ]).unwrap()
  assert_true(
    @duckdb.physical_batch_cell(batch, 0, 0).unwrap().value is @admitted.Null,
  )
  let output = @duckdb.prepare_scan_output_receiver(
    scan,
    [("id", @duckdb.Float64)],
    limits,
    1000,
  ).unwrap()
  assert_eq(@schema.field_count(@duckdb.physical_result_schema(output)), 1)
  assert_true(
    @duckdb.prepare_scan_output_receiver(
      scan,
      [("id", @duckdb.Float64), ("amount", @duckdb.Float64)],
      limits,
      1000,
    )
    is Err(SchemaMismatch),
  )
}
