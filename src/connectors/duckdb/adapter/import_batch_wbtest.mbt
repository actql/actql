///|
test "shared import batch SQL keeps exact tuple and parameter limits" {
  let sql = "INSERT INTO main.\"owned\" VALUES (?, ?)"
  assert_eq(
    compile_import_batch_sql(sql, 2, 3, 6, 1000).unwrap(),
    (3, sql + ", (?, ?), (?, ?)"),
  )
  assert_eq(
    compile_import_batch_sql(sql, 2, 3, 5, 1000).unwrap(),
    (2, sql + ", (?, ?)"),
  )
  assert_eq(
    compile_import_batch_sql(sql, 2, 3, 6, sql.length() + 7).unwrap(),
    (1, sql),
  )
  assert_eq(
    compile_import_batch_sql(sql, 2, 2147483647, 2147483647, sql.length() + 8).unwrap(),
    (2, sql + ", (?, ?)"),
  )
  assert_true(
    compile_import_batch_sql(sql, 2, 0, 6, 1000) is Err(InvalidLimits),
  )
  assert_true(
    compile_import_batch_sql(sql, 0, 3, 6, 1000) is Err(InvalidLimits),
  )
  assert_true(compile_import_batch_sql(sql, 2, 3, 1, 1000) is Err(Limit))
  assert_true(
    compile_import_batch_sql(sql, 2, 3, 6, sql.length() - 1) is Err(Limit),
  )
}
