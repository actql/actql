///|
test "GoogleSQL scalar nodes retain independent common wire operands" {
  let sign = expression_pipeline(
    ",{\"derive\":{\"value\":{\"sign\":{\"literal\":-4}}}}",
  )
  let lowered = @lowering_relation.lower_expression(
    sign,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.expression_body(lowered)
    is @lowering_relation.Unary(@lowering_relation.Sign, _),
  )
  assert_eq(
    expression_wire(lowered),
    "{\"body\":{\"body\":-4,\"op\":\"literal\"},\"op\":\"sign\"}",
  )
  for
    (name, op) in [
      ("starts_with", @lowering_relation.StartsWith),
      ("ends_with", @lowering_relation.EndsWith),
    ] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":{\"" +
      name +
      "\":[{\"literal\":\"猫abc\"},{\"literal\":\"猫\"}]}}}",
    )
    let lowered = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_true(
      @lowering_relation.expression_body(lowered)
      is @lowering_relation.Binary(actual, _, _) &&
      actual == op,
    )
    assert_eq(
      expression_wire(lowered),
      "{\"body\":[{\"body\":\"猫abc\",\"op\":\"literal\"},{\"body\":\"猫\",\"op\":\"literal\"}],\"op\":\"" +
      name +
      "\"}",
    )
  }
}
