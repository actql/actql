///|
test "nested payloads remain typed and available to Results" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"nest\":{\"with\":\"joined\",\"on\":[{\"left\":\"left.id\",\"right\":\"left.id\"}],\"into\":\"items\",\"fields\":[{\"score\":\"right.score\"}]},\"as\":\"nested\"}",
  )
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"nested\",\"fields\":[\"left.id\",\"items\"]}}"),
    limits(),
  ).unwrap()
  let result = @relation_results.lookup(results, "out").unwrap()
  let items = @schema.lookup(
    @relation_results.output_schema(result),
    Unqualified("items"),
  ).unwrap()
  assert_true(!items.nullable)
  assert_true(items.shape is @contract.Array(_, ..))
  assert_eq(@relation_results.target(result), @pipeline.Step(1))
  assert_true(!@relation_results.pending_validations(result).is_empty())
}
