///|
test "public consumer receives only bounded immutable projections" {
  let body =
    #|{"statementHandle":"opaque-handle","sqlState":"00000","resultSetMetaData":{"format":"jsonv2","numRows":1,"rowType":[{"name":"NAME","type":"text","nullable":false}],"partitionInfo":[{"rowCount":1}]},"data":[["same original"]]}
  let result = @catalog.project_result_set(@utf8.encode(body), {
    max_bytes: 1000,
    max_nodes: 100,
    max_depth: 8,
    max_columns: 2,
    max_name_units: 32,
    max_handle_units: 32,
    max_partitions: 2,
    max_rows: 2,
    max_total_rows: 2L,
  }).unwrap()
  assert_eq(@catalog.result_set_handle(result), "opaque-handle")
  assert_eq(@catalog.result_set_column_name(result, 0), Some("NAME"))
  assert_eq(@catalog.result_set_column_name(result, 1), None)
  assert_true(@catalog.result_set_cell(result, -1, 0) is None)
  assert_true(@catalog.result_set_cell(result, 0, 1) is None)
  assert_eq(@catalog.result_set_partition_rows(result, 0), Some(1L))
  assert_eq(@catalog.result_set_partition_count(result), 1)
  assert_true(
    @catalog.result_set_cell(result, 0, 0).unwrap().value
    is @admitted.Text("same original"),
  )
}
