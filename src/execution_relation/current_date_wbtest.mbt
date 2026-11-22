///|
test "current date projects the exact UTC day of the admitted query invocation" {
  let expression = lowered("{\"current_date\":[]}")
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"date\":{\"current_date\":[]}}}]",
  )
  assert_true(
    @lower.bound_prepared_requires_query_time(
      owner,
      max_work=10000,
      max_expressions=100,
    )
    is Ok(true),
  )
  let time = query_frame_time()
  for _ in 0..<2 {
    assert_true(
      evaluate_expression_with_workspace(
        expression,
        {},
        [],
        { remaining: 1000, max_frames: 100, },
        row_workspace(1000),
        query_time=Some(time),
      )
      is Ok(Captured(@admitted.Date("2026-09-18"))),
    )
  }
  let writer = @encode.writer(1000, 20, 20)
  @lower.emit_expression(expression, writer)
  assert_eq(@encode.finish(writer), "{\"body\":[],\"op\":\"current_date\"}")
}

///|
test "current date keeps missing-original and lazy query-time behavior" {
  assert_true(
    run_expr("{\"current_date\":[]}")
    is Err({ kind: QueryEvaluationTimeUnavailable, .. }),
  )
  assert_true(
    run_expr(
      "{\"if\":[{\"literal\":false},{\"current_date\":[]},{\"date_literal\":\"2000-02-29\"}]}",
    )
    is Ok(Captured(@admitted.Date("2000-02-29"))),
  )
}
