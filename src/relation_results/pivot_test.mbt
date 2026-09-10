///|
test "pivot preserves qualified index provenance through Result projection" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"pivot\":{\"index\":[\"left.id\"],\"column\":\"right.id\",\"values\":[\"b\",\"a\"],\"value\":\"right.score\",\"aggregate\":\"sum\",\"fill\":0},\"as\":\"wide\"}",
  )
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"wide\",\"fields\":[\"b\",\"left.id\",\"a\"]}}"),
    limits(),
  ).unwrap()
  let result = @relation_results.lookup(results, "out").unwrap()
  let c = @schema.lookup(
    @relation_results.output_schema(result),
    Unqualified("b"),
  ).unwrap()
  assert_true(!c.nullable && c.shape is @contract.Number)
  assert_eq(@relation_results.target(result), @pipeline.Step(1))
  assert_true(!@relation_results.pending_validations(result).is_empty())
}
