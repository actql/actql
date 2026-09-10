///|
test "analytic fields connect without changing the main input or source fields" {
  let p = join_pipeline(
    "[{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"r\":{\"fn\":\"rank\"},\"n\":{\"fn\":\"lag\",\"expr\":\"amount\"}}},\"from\":\"l\",\"as\":\"ranked\"},{\"derive\":{\"x\":\"r + amount\"}}]",
  ).unwrap()
  assert_eq(@pipeline_typing.step_at(p, 1).unwrap().input, Step(0))
  assert_true(
    @schema.lookup(@pipeline_typing.output_schema(p), Unqualified("x"))
    is Some(_),
  )
  assert_true(
    @schema.lookup(@pipeline_typing.output_schema(p), Unqualified("id"))
    is Some(_),
  )
}
