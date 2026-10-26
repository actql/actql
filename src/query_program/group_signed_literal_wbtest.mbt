///|
test "signed literal comparison requires successful admission" {
  let limits = mapping_syntax_limits().expression
  for text in ["+9007199254740992"] {
    let expression = @query.parse_expression(text, limits).unwrap()
    assert_false(same_expression(expression, expression), msg=text)
  }
  for
    (left, right) in [
      ("+1", "1.0"),
      ("+(-1)", "-1"),
      ("-(-1)", "+1"),
      ("-0", "0"),
      ("-(-0)", "0"),
      ("+(-0)", "0"),
    ] {
    assert_true(
      same_expression(
        @query.parse_expression(left, limits).unwrap(),
        @query.parse_expression(right, limits).unwrap(),
      ),
    )
  }
  assert_false(
    same_expression(
      @query.parse_expression("x + 0", limits).unwrap(),
      @query.parse_expression("x", limits).unwrap(),
    ),
  )
  assert_false(
    same_expression(
      @query.parse_expression("+x", limits).unwrap(),
      @query.parse_expression("x", limits).unwrap(),
    ),
  )
}
