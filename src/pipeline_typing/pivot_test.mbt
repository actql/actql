///|
test "pivot connects generated fields to later expressions" {
  let p = join_pipeline(
    "[{\"pivot\":{\"index\":[],\"column\":\"id\",\"values\":[\"b\",\"a\"],\"value\":\"amount\",\"aggregate\":\"sum\",\"fill\":0},\"from\":\"l\",\"as\":\"wide\"},{\"derive\":{\"total\":\"a + b\"}}]",
  ).unwrap()
  assert_eq(@pipeline_typing.step_at(p, 1).unwrap().input.unwrap(), Step(0))
  let total = @schema.lookup(
    @pipeline_typing.output_schema(p).unwrap(),
    Unqualified("total"),
  ).unwrap()
  assert_true(total.shape is @contract.Number && !total.nullable)
  assert_true(
    @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("amount"),
    )
    is None,
  )
}
