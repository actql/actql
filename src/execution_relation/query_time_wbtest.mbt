///|
test "query time is unavailable when demanded without its original Run context" {
  assert_true(
    run_expr("\"current_timestamp()\"")
    is Err({ kind: QueryEvaluationTimeUnavailable, .. }),
  )
}

///|
test "query time retains ordinary lazy surrounding demand without sampling" {
  assert_true(
    run_expr(
      "\"if(false,current_timestamp(),CAST('2026-10-19T00:00:00.000Z' AS TIMESTAMP))\"",
    )
    is Ok(Captured(@admitted.Timestamp(value))) &&
    value == "2026-10-19T00:00:00.000Z",
  )
}
