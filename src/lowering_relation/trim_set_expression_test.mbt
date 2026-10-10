///|
test "explicit trim sets retain ordered binary operators and canonical wires" {
  for
    (tag, op) in [
      ("trim", @lowering_relation.TrimSet),
      ("ltrim", @lowering_relation.LTrimSet),
      ("rtrim", @lowering_relation.RTrimSet),
    ] {
    for
      source in [
        "{\"" + tag + "\":[{\"literal\":\"x😀x\"},{\"literal\":\"x\"}]}",
        "\"" + tag + "('x😀x', 'x')\"",
      ] {
      let owner = expression_pipeline(
        ",{\"derive\":{\"value\":" + source + "}}",
      )
      let expression = @lowering_relation.lower_expression(
        owner,
        1,
        0,
        expression_limits(),
      ).unwrap()
      assert_true(
        @lowering_relation.expression_body(expression)
        is @lowering_relation.Binary(actual, _, _) &&
        actual == op,
      )
      assert_eq(
        expression_wire(expression),
        "{\"body\":[{\"body\":\"x😀x\",\"op\":\"literal\"},{\"body\":\"x\",\"op\":\"literal\"}],\"op\":\"" +
        tag +
        "\"}",
      )
    }
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":{\"" +
      tag +
      "\":[{\"literal\":null},{\"literal\":null}]}}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(expression),
      "{\"body\":[{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"string\"}},\"op\":\"typed_null\"},{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"string\"}},\"op\":\"typed_null\"}],\"op\":\"" +
      tag +
      "\"}",
    )
  }
}
