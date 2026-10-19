///|
test "query time dependency usage carries the exact finite work boundary" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"v\":\"current_timestamp()\"}}]",
  )
  let (required, spent) = @lower.bound_prepared_query_time_requirement_usage(
    owner,
    max_work=10000,
    max_expressions=100,
  ).unwrap()
  assert_true(required)
  assert_true(spent > 0)
  assert_true(
    @lower.bound_prepared_query_time_requirement_usage(
      owner,
      max_work=spent,
      max_expressions=100,
    )
    is Ok((true, actual)) &&
    actual == spent,
  )
  assert_true(
    @lower.bound_prepared_query_time_requirement_usage(
      owner,
      max_work=spent - 1,
      max_expressions=100,
    )
    is Err(_),
  )
}
