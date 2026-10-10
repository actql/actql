///|
test "name admission canonicalizes identifiers without changing decoded lexemes or STRING values" {
  let source = "`e\\u0301` `line\\rname` 'e\\u0301\\r'"
  let tokens = tokenize(source, limits()).unwrap()
  assert_eq(token_at(tokens, 0).unwrap().value, QuotedName("e\u{301}"))
  assert_eq(token_at(tokens, 1).unwrap().value, QuotedName("line\rname"))
  assert_eq(token_at(tokens, 2).unwrap().value, Text("e\u{301}\r"))
  let span = @origin.span(token_origin(tokens, 0).unwrap())
  assert_eq(span.start_column, 1)
  assert_eq(span.end_column, 10)
}

///|
test "expression references properties and parameters share admitted identifier spelling" {
  let cases : Array[(String, ExpressionKind)] = [
    ("`e\\u0301`", Reference([{ value: "é", quoted: true, }])),
    ("@`e\\u0301`", ParameterReference("é")),
  ]
  for (source, expected) in cases {
    let expression = parse_expression(source, expression_limits()).unwrap()
    assert_eq(kind(expression, expression_root(expression)), expected)
  }
  let expression = parse_expression("(payload).`e\\u0301`", expression_limits()).unwrap()
  assert_true(
    kind(expression, expression_root(expression))
    is Property(_, { value: "é", quoted: true, }),
  )
  assert_eq(
    parse_relation_path("`e\\u0301`.`line\\rname`", limits()).unwrap(),
    [{ value: "é", quoted: true, }, { value: "line\nname", quoted: true, }],
  )
}

///|
test "identifier normalization remains subject to original source work and expanded bytes limits" {
  // Unicode 16.0 NFC decomposes U+0344 to U+0308 U+0301: two bytes become four.
  let source = "`\\u0344`"
  let tokens = tokenize(source, limits()).unwrap()
  let expression = parse_expression(source, expression_limits()).unwrap()
  assert_eq(
    kind(expression, expression_root(expression)),
    Reference([{ value: "\u{308}\u{301}", quoted: true, }]),
  )
  assert_eq(usage(tokens, LiteralBytes), 4)
  assert_true(tokenize(source, { ..limits(), max_literal_bytes: 4, }) is Ok(_))
  assert_true(
    tokenize(source, { ..limits(), max_literal_bytes: 3, })
    is Err({ issue: Limit(LiteralBytes), .. }),
  )
  assert_true(
    tokenize(source, { ..limits(), max_work: usage(tokens, Work) - 1, })
    is Err({ issue: Limit(Work), .. }),
  )
}
