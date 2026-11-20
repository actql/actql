///|
test "SQL CAST INT64 retains the exact signed domain through original compilation and execution" {
  for
    (source, expected) in [
      ("'12'", 12L),
      ("'9007199254740993'", 9007199254740993L),
      ("'9223372036854775807'", 9223372036854775807L),
      ("'-9223372036854775808'", -9223372036854775807L - 1L),
      ("'0x123'", 291L),
      ("'-0x123'", -291L),
      ("TRUE", 1L),
      ("FALSE", 0L),
      ("1.5", 2L),
      ("-0.5", -1L),
    ] {
    let sql = "SELECT CAST(" + source + " AS INT64) AS value"
    let output = timestamp_sql_output(timestamp_sql_original(sql))
    assert_eq(@execution.completed_row_count(output), 1)
    assert_eq(@execution.completed_column_count(output), 1)
    assert_eq(@execution.completed_column_name(output, 0), Some("value"))
    assert_true(
      @execution.completed_cell(output, 0, 0)
      is Some(Captured(@values.Signed64(value))) &&
      value == expected,
      msg=sql,
    )
  }
  let null = timestamp_sql_output(
    timestamp_sql_original("SELECT CAST(NULL AS INT64) AS value"),
  )
  assert_true(@execution.completed_cell(null, 0, 0) is Some(Null))
}
