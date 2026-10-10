///|
test "ROUND and TRUNC lower through the existing unary owner and wire" {
  for
    (name, op) in [
      ("round", @lowering_relation.Round),
      ("trunc", @lowering_relation.Trunc),
    ] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":{\"" + name + "\":{\"literal\":-2.5}}}}",
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
      "{\"body\":{\"body\":-2.5,\"op\":\"literal\"},\"op\":\"" + name + "\"}",
    )
  }
}

///|
test "unary rounding wire retains the demanded division child" {
  for name in ["round", "trunc"] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":{\"" +
      name +
      "\":{\"divide\":[{\"literal\":1},{\"literal\":0}]}}}}",
    )
    let lowered = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(lowered),
      "{\"body\":{\"body\":[{\"body\":1,\"op\":\"literal\"},{\"body\":0,\"op\":\"literal\"}],\"op\":\"divide\"},\"op\":\"" +
      name +
      "\"}",
    )
  }
}
