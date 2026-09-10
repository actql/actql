///|
test "unpivot preserves qualified kept fields and feeds Result schemas" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"unpivot\":{\"columns\":[\"right.score\",\"right.score\"],\"keep\":[\"left.id\"],\"name_column\":\"key\",\"value_column\":\"value\"},\"as\":\"expanded\"}",
  )
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"expanded\",\"fields\":[\"left.id\",\"key\",\"value\"]}}",
    ),
    limits(),
  ).unwrap()
  let result = @relation_results.lookup(results, "out").unwrap()
  assert_true(
    @schema.lookup(
      @relation_results.output_schema(result),
      Unqualified("value"),
    ).unwrap().nullable,
  )
  assert_true(
    @schema.lookup(
      @relation_results.output_schema(result),
      Qualified(Left, "id"),
    )
    is Some(_),
  )
  assert_eq(@relation_results.fields(result), ["left.id", "key", "value"])
  assert_eq(@relation_results.target(result), @pipeline.Step(1))
}
