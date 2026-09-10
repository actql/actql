///|
test "group output connects to later expressions and removes nongrouped fields" {
  let p = join_pipeline(
    "[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}},\"from\":\"l\",\"as\":\"g\"},{\"filter\":\"n > 1\"},{\"derive\":{\"doubled\":\"n * 2\"}}]",
  ).unwrap()
  assert_true(
    @schema.lookup(@pipeline_typing.output_schema(p), Unqualified("doubled"))
    is Some(_),
  )
  assert_true(
    @schema.lookup(@pipeline_typing.output_schema(p), Unqualified("amount"))
    is None,
  )
  assert_eq(@pipeline_typing.step_at(p, 1).unwrap().input, Step(0))
  assert_true(
    join_pipeline(
      "[{\"group\":{\"by\":[],\"aggregates\":{}},\"from\":\"l\"},{\"filter\":\"amount > 1\"}]",
    )
    is Err(_),
  )
}
