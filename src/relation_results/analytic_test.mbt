///|
test "analytic Result projection keeps join nullability and publication obligations" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"analytic\":{\"partition_by\":[\"left.id\"],\"order_by\":[{\"left.id\":\"asc\"}],\"functions\":{\"previous\":{\"fn\":\"lag\",\"expr\":\"right.score\"}}},\"as\":\"a\"}",
  )
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"a\",\"fields\":[\"previous\",\"left.id\"]}}"),
    limits(),
  ).unwrap()
  let r = @relation_results.lookup(results, "out").unwrap()
  assert_true(
    @schema.lookup(@relation_results.output_schema(r), Unqualified("previous")).unwrap().nullable,
  )
  assert_true(!@relation_results.pending_validations(r).is_empty())
  assert_eq(@relation_results.target(r), @pipeline.Step(1))
}
