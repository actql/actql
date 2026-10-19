///|
test "NUMBER cast uses the original numeric target and authored span" {
  for target in ["NUMBER", "number", "NuMbEr", "FLOAT64", "DOUBLE"] {
    let text = "CAST('1.25' AS " + target + ")"
    let expression = parse_expression(text, expression_limits()).unwrap()
    let root = expression_node(expression, expression_root(expression)).unwrap()
    assert_eq(root.start, 0)
    assert_eq(root.end, text.length())
    guard root.kind is Cast(value, CastType::Number) else {
      fail("the existing Number cast target must be retained")
    }
    assert_eq(kind(expression, value), StringLiteral("1.25"))
  }
}

///|
test "NUMBER cast alias keeps quoted and unknown target refusals" {
  for target in ["`NUMBER`", "NUMBERISH", "NUMERIC", "INT64", "FLOAT32"] {
    assert_true(
      parse_expression("CAST('1.25' AS " + target + ")", expression_limits())
      is Err(_),
      msg=target,
    )
  }
}
