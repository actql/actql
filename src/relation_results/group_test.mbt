///|
test "group consumes qualified fields and publishes typed aggregate results" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"group\":{\"by\":[\"left.id\",\"left.id\"],\"aggregates\":{\"total\":{\"fn\":\"sum\",\"expr\":\"right.score\"},\"rows\":{\"fn\":\"count\"}}},\"as\":\"grouped\"}",
  )
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"grouped\",\"fields\":[\"total\",\"left.id\",\"rows\"]}}",
    ),
    limits(),
  ).unwrap()
  let result = @relation_results.lookup(results, "out").unwrap()
  let total = @schema.lookup(
    @relation_results.output_schema(result),
    Unqualified("total"),
  ).unwrap()
  assert_true(total.nullable && total.shape is @contract.Number)
  assert_eq(@relation_results.target(result), @pipeline.Step(1))
  assert_true(!@relation_results.pending_validations(result).is_empty())
}
