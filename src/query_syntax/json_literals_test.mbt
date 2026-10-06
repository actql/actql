///|
test "JSON literal preserves decoded text without guessing a scalar value" {
  for
    (text, expected) in [
      ("JSON '{\"a\":null}'", "{\"a\":null}"),
      ("json 'null'", "null"),
      ("JSON \"123\"", "123"),
      ("JSON '''[true,false]'''", "[true,false]"),
      ("JSON r'{\"s\":\"\\n\"}'", "{\"s\":\"\\n\"}"),
      ("JSON '{' /* separate */ '\"a\":1}'", "{\"a\":1}"),
    ] {
    let expression = parse_expression(text, expression_limits()).unwrap()
    assert_eq(
      kind(expression, expression_root(expression)),
      JsonLiteral(expected),
    )
    assert_eq(
      expression_node(expression, expression_root(expression)).unwrap().start,
      0,
    )
    assert_eq(
      expression_node(expression, expression_root(expression)).unwrap().end,
      text.length(),
    )
  }
}

///|
test "JSON literal type prefix does not turn identifiers or parameters into JSON" {
  let ordinary = parse_expression("JSON", expression_limits()).unwrap()
  assert_eq(
    kind(ordinary, expression_root(ordinary)),
    Reference([{ value: "JSON", quoted: false, }]),
  )
  let quoted = parse_expression("`JSON`", expression_limits()).unwrap()
  assert_eq(
    kind(quoted, expression_root(quoted)),
    Reference([{ value: "JSON", quoted: true, }]),
  )
  for text in ["JSON '{' '\"a\":1}' 'extra'", "JSON '{}' '{}'"] {
    // Syntax owns the typed string. JSON admission owns trailing JSON data.
    let expression = parse_expression(text, expression_limits()).unwrap()
    assert_true(kind(expression, expression_root(expression)) is JsonLiteral(_))
  }
  assert_true(
    parse_expression("JSON '{}'\"{}\"", expression_limits()) is Err(_),
  )
}
