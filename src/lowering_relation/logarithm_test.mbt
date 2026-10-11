///|
test "Exponential and logarithmic machine nodes preserve their canonical shapes" {
  for
    (name, op) in [
      ("exp", @lowering_relation.Exp),
      ("ln", @lowering_relation.Ln),
      ("log10", @lowering_relation.Log10),
    ] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":{\"" + name + "\":{\"literal\":1}}}}",
    )
    let lowered = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_true(
      @lowering_relation.expression_body(lowered)
      is @lowering_relation.Unary(actual, _) &&
      actual == op,
    )
    assert_eq(
      expression_wire(lowered),
      "{\"body\":{\"body\":1,\"op\":\"literal\"},\"op\":\"" + name + "\"}",
    )
  }
  let owner = expression_pipeline(
    ",{\"derive\":{\"value\":{\"log\":[{\"literal\":8},{\"literal\":2}]}}}",
  )
  let lowered = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.expression_body(lowered)
    is @lowering_relation.Binary(@lowering_relation.Log, _, _),
  )
  assert_eq(
    expression_wire(lowered),
    "{\"body\":[{\"body\":8,\"op\":\"literal\"},{\"body\":2,\"op\":\"literal\"}],\"op\":\"log\"}",
  )
}
