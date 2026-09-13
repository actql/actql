///|
test "broad receiver executes non-native predicate through owned Local residual" {
  let (query, owner) = query_sequence_fixture(filter="id + 1 > 2")
  assert_true(
    @duckdb.compile_native_filter_select(
      owner,
      "main",
      "records",
      native_compile_limits(),
    )
    is Err(UnsupportedPredicate),
  )
  let scan = @duckdb.prepare_broad_scan(owner, 0, "main", "records", 10, 10000).unwrap()
  assert_eq(
    @duckdb.broad_scan_sql(scan),
    "SELECT \"id\" FROM \"main\".\"records\"",
  )
  let table = @duckdb.admit_broad_table(
    scan,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  let prepared = @query.prepare_query_sequence(
    query,
    query_generated(owner),
    10000,
  ).unwrap()
  for width in [1, 7, 1000] {
    let receiving = @duckdb.prepare_broad_receiving(
      table,
      [("id", @duckdb.Float64)],
      { max_rows: 3, max_cells: 3, max_nodes: 3, max_text_bytes: 0, },
      100,
      { max_nodes: 6, max_text_bytes: 6, max_depth: 2, max_work: 12, },
    ).unwrap()
    if width == 1 {
      for value in ["4008000000000000", "3ff0000000000000", "4000000000000000"] {
        @duckdb.accept_broad_chunk(receiving, 1, [
          input_cursor("[\"" + value + "\"]"),
        ]).unwrap()
      }
    } else {
      @duckdb.accept_broad_chunk(receiving, 3, [
        input_cursor(
          "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
        ),
      ]).unwrap()
    }
    let rows = @duckdb.finish_broad_receiving(receiving).unwrap()
    assert_eq(@execution.captured_row_count(rows), 3)
    assert_true(@duckdb.finish_broad_receiving(receiving) is Err(InvalidState))
    @duckdb.abort_broad_receiving(receiving)
    let receipt = @query.bind_query_receipt(prepared, rows).unwrap()
    let (completed, _) = @query.execute_query_receipt_guarded(
      prepared,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=100,
      { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    ).unwrap()
    let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
  }
}

///|
test "broad metadata and failed retention never produce sealed input" {
  let (_, owner) = query_sequence_fixture()
  let scan = @duckdb.prepare_broad_scan(owner, 0, "main", "records", 10, 10000).unwrap()
  assert_true(
    @duckdb.admit_broad_table(scan, 1, [("table_type", @duckdb.Varchar)], [
      input_cursor("[\"VIEW\"]"),
    ])
    is Err(NotBaseTable),
  )
  let table = @duckdb.admit_broad_table(
    scan,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  let receiving = @duckdb.prepare_broad_receiving(
    table,
    [("id", @duckdb.Float64)],
    { max_rows: 3, max_cells: 3, max_nodes: 3, max_text_bytes: 0, },
    100,
    { max_nodes: 3, max_text_bytes: 6, max_depth: 2, max_work: 12, },
  ).unwrap()
  @duckdb.accept_broad_chunk(receiving, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  assert_true(
    @duckdb.accept_broad_chunk(receiving, 1, [
      input_cursor("[\"4000000000000000\"]"),
    ])
    is Err(Retention(CaptureLimit)),
  )
  assert_true(@duckdb.finish_broad_receiving(receiving) is Err(InvalidState))
  assert_true(
    @duckdb.accept_broad_chunk(receiving, 0, [input_cursor("[]")])
    is Err(InvalidState),
  )
}
