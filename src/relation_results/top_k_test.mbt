///|
test "top-k Results retain publication obligations without assuming completed order" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"top_k_by\":{\"partition_by\":[],\"k\":1,\"by\":[{\"right.score\":\"desc\"}]},\"as\":\"best\"}",
  )
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"best\",\"fields\":[\"right.score\",\"left.id\"]}}",
    ),
    limits(),
  ).unwrap()
  let r = @relation_results.lookup(results, "out").unwrap()
  assert_true(
    @schema.lookup(
      @relation_results.output_schema(r),
      Qualified(Right, "score"),
    ).unwrap().nullable,
  )
  assert_true(!@relation_results.pending_validations(r).is_empty())
  assert_eq(@relation_results.target(r), @pipeline.Step(1))
}
