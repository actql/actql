///|
test "global and partitioned top-k connect through unchanged qualified schemas" {
  let p = join_pipeline(
    "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"}},{\"top_k_by\":{\"partition_by\":[\"left.id\",\"left.id\"],\"k\":3,\"by\":[{\"right.amount\":\"desc\"}]},\"as\":\"best\"},{\"top_k\":{\"k\":1,\"by\":[{\"left.id\":\"asc\"}]}},{\"derive\":{\"value\":\"right.amount\"}}]",
  ).unwrap()
  assert_eq(@pipeline_typing.step_at(p, 1).unwrap().input, Step(0))
  assert_eq(@pipeline_typing.step_at(p, 2).unwrap().input, Step(1))
  assert_true(
    @schema.lookup(@pipeline_typing.output_schema(p), Unqualified("value")).unwrap().nullable,
  )
  assert_true(
    @schema.lookup(@pipeline_typing.output_schema(p), Qualified(Left, "id"))
    is Some(_),
  )
}
