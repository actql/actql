///|
test "direct trig lowering retains distinct unary enums and authored wire bodies" {
  for
    (name, op) in [
      ("sin", @lowering_relation.Sin),
      ("cos", @lowering_relation.Cos),
      ("tan", @lowering_relation.Tan),
      ("asin", @lowering_relation.Asin),
      ("acos", @lowering_relation.Acos),
      ("atan", @lowering_relation.Atan),
      ("sinh", @lowering_relation.Sinh),
      ("cosh", @lowering_relation.Cosh),
      ("tanh", @lowering_relation.Tanh),
      ("asinh", @lowering_relation.Asinh),
      ("acosh", @lowering_relation.Acosh),
      ("atanh", @lowering_relation.Atanh),
    ] {
    for
      (child, body) in [
        ("{\"literal\":0.5}", "{\"body\":0.5,\"op\":\"literal\"}"),
        (
          "{\"divide\":[{\"literal\":1},{\"literal\":0}]}", "{\"body\":[{\"body\":1,\"op\":\"literal\"},{\"body\":0,\"op\":\"literal\"}],\"op\":\"divide\"}",
        ),
      ] {
      let owner = expression_pipeline(
        ",{\"derive\":{\"value\":{\"" + name + "\":" + child + "}}}",
      )
      let expression = @lowering_relation.lower_expression(
        owner,
        1,
        0,
        expression_limits(),
      ).unwrap()
      assert_true(
        @lowering_relation.expression_body(expression)
        is @lowering_relation.Unary(actual, _) &&
        actual == op,
      )
      assert_eq(
        expression_wire(expression),
        "{\"body\":" + body + ",\"op\":\"" + name + "\"}",
      )
    }
  }
}

///|
test "atan2 lowering retains first second order without folding or division rewrites" {
  for
    (children, bodies) in [
      (
        "[{\"literal\":1},{\"literal\":2}]", "[{\"body\":1,\"op\":\"literal\"},{\"body\":2,\"op\":\"literal\"}]",
      ),
      (
        "[{\"literal\":2},{\"literal\":1}]", "[{\"body\":2,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}]",
      ),
      (
        "[{\"sin\":{\"literal\":0.5}},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]",
        "[{\"body\":{\"body\":0.5,\"op\":\"literal\"},\"op\":\"sin\"},{\"body\":[{\"body\":1,\"op\":\"literal\"},{\"body\":0,\"op\":\"literal\"}],\"op\":\"divide\"}]",
      ),
    ] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":{\"atan2\":" + children + "}}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_true(
      @lowering_relation.expression_body(expression)
      is @lowering_relation.Binary(@lowering_relation.Atan2, _, _),
    )
    assert_eq(
      expression_wire(expression),
      "{\"body\":" + bodies + ",\"op\":\"atan2\"}",
    )
  }
}
