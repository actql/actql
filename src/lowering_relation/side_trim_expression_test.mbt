///|
test "side trim retains unary operators and independent canonical wires in both syntax forms" {
  for
    (tag, operator) in [
      ("ltrim", @lowering_relation.LTrim),
      ("rtrim", @lowering_relation.RTrim),
    ] {
    for
      source in [
        "{\"" + tag + "\":{\"literal\":\"　é😀 \"}}",
        "\"" + tag + "('　é😀 ')\"",
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
      guard @lowering_relation.expression_body(expression)
        is @lowering_relation.Unary(actual, child) else {
        fail("side trim must remain a unary lowering node")
      }
      assert_eq(actual, operator)
      assert_true(
        @lowering_relation.expression_body(child)
        is @lowering_relation.Literal(_),
      )
      assert_eq(
        expression_wire(expression),
        "{\"body\":{\"body\":\"　é😀 \",\"op\":\"literal\"},\"op\":\"" +
        tag +
        "\"}",
      )
    }
  }
}

///|
test "side trim lowering retains typed NULL and its checked string contract" {
  for
    (tag, operator) in [
      ("ltrim", @lowering_relation.LTrim),
      ("rtrim", @lowering_relation.RTrim),
    ] {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":{\"" + tag + "\":{\"literal\":null}}}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    guard @lowering_relation.expression_body(expression)
      is @lowering_relation.Unary(actual, child) else {
      fail("NULL side trim must retain its unary node")
    }
    assert_eq(actual, operator)
    assert_true(
      @lowering_relation.expression_body(child) is @lowering_relation.TypedNull,
    )
    assert_eq(
      expression_wire(expression),
      "{\"body\":{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"string\"}},\"op\":\"typed_null\"},\"op\":\"" +
      tag +
      "\"}",
    )
  }
}
