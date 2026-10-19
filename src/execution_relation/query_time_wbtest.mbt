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

///|
test "query time dependency uses checked lazy expressions and not literal JSON keys" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"v\":\"if(false,current_timestamp(),CAST('2026-10-19T00:00:00.000Z' AS TIMESTAMP))\"}}]",
  )
  assert_true(
    @lower.bound_prepared_requires_query_time(
      owner,
      max_work=10000,
      max_expressions=100,
    )
    is Ok(true),
  )
  assert_true(
    @lower.bound_prepared_requires_query_time(
      owner,
      max_work=0,
      max_expressions=100,
    )
    is Err(_),
  )
  assert_true(
    @lower.bound_prepared_requires_query_time(
      owner,
      max_work=10000,
      max_expressions=0,
    )
    is Err(_),
  )
  let plain = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"v\":{\"literal\":{\"current_timestamp\":[]}}}}]",
  )
  assert_true(
    @lower.bound_prepared_requires_query_time(
      plain,
      max_work=10000,
      max_expressions=100,
    )
    is Ok(false),
  )
}
