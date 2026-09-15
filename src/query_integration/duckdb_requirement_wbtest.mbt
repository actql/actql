///|
test "DuckDB preparations retain canonical requirement and enforce its residual guards" {
  let checked = query_checked_program_fixture()
  let sequence = query_checked_sequence(checked)
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let requirement = @planning.prepare_query_requirement(
    material,
    @program_check.source_identity(checked),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let prepared = @duckdb_query.prepare_duckdb_query(
    requirement,
    "main",
    "records",
    10,
    native_compile_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      @duckdb_query.duckdb_query_requirement(prepared),
      requirement,
    ),
  )
  let (native, witness) = @duckdb_query.duckdb_query_native_preparation(
    prepared,
  ).unwrap()
  assert_true(
    @duckdb.native_root_guard_matches(
      witness,
      @duckdb.native_scan_query(native),
      100,
    ),
  )
  let broad = @duckdb_query.duckdb_query_broad_scan(prepared)
  let table = @duckdb.admit_broad_table(
    broad,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  let receiver = @duckdb.prepare_broad_receiving(
    table,
    [("id", @duckdb.Float64)],
    { max_rows: 3, max_cells: 3, max_nodes: 3, max_text_bytes: 0, },
    100,
    run_limits().input_values,
  ).unwrap()
  @duckdb.accept_broad_chunk(receiver, 3, [
    input_cursor(
      "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
    ),
  ]).unwrap()
  let input = @duckdb.finish_broad_receiving(receiver).unwrap()
  let measurement : @query.QueryGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let too_few = @planning.prepare_query_requirement(
    material,
    @program_check.source_identity(checked),
    { max_rows: 1, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let limited = @duckdb_query.prepare_duckdb_query(
    too_few,
    "main",
    "records",
    10,
    native_compile_limits(),
  ).unwrap()
  assert_true(
    @duckdb_query.execute_duckdb_broad_residual(
      limited,
      input,
      compute_test_limits(),
      measurement,
    )
    is Err(OutputRows),
  )
  let (completed, _) = @duckdb_query.execute_duckdb_broad_residual(
    prepared,
    input,
    compute_test_limits(),
    measurement,
  ).unwrap()
  let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
  let tiny = @planning.prepare_query_requirement(
    material,
    @program_check.source_identity(checked),
    { max_rows: 2, max_value_bytes: 4, },
    query_material_limits(),
  ).unwrap()
  let tiny = @duckdb_query.prepare_duckdb_query(
    tiny,
    "main",
    "records",
    10,
    native_compile_limits(),
  ).unwrap()
  assert_true(
    @duckdb_query.duckdb_query_native_preparation(tiny)
    is Err(RootGuard(UnsupportedCeiling)),
  )
  let other = query_checked_program_fixture()
  let other_requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(
      query_checked_sequence(other),
      query_material_limits(),
    ).unwrap(),
    @program_check.source_identity(other),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let foreign = @duckdb_query.prepare_duckdb_query(
    other_requirement,
    "main",
    "records",
    10,
    native_compile_limits(),
  ).unwrap()
  assert_true(
    @duckdb_query.execute_duckdb_broad_residual(
      foreign,
      input,
      compute_test_limits(),
      measurement,
    )
    is Err(Execution(ForeignReceipt)),
  )
  assert_eq(
    @planning.query_requirement_cid(requirement),
    @planning.query_requirement_cid(other_requirement),
  )
}
