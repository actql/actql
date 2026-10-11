///|
test "hex integer tokens retain spelling spans and separate unary signs" {
  assert_eq(values("-0x10 + 0XfF 0x20000000000000"), [
    Symbol(45),
    Numeric("0x10"),
    Symbol(43),
    Numeric("0XfF"),
    Numeric("0x20000000000000"),
    End,
  ])
  let tokens = tokenize("`é` 0XfF", limits()).unwrap()
  let token = token_at(tokens, 1).unwrap()
  assert_eq(token.start, 5)
  assert_eq(token.end, 9)
  let expression = parse_expression("0XfF", expression_limits()).unwrap()
  assert_true(kind(expression, expression_root(expression)) is Number("0XfF"))
}

///|
test "hex integer decoder checks exact magnitude before floating conversion" {
  for
    (text, value) in [
      ("0x0", 0L),
      ("0X00", 0L),
      ("0x10", 16L),
      ("0XaF", 175L),
      ("0x1fffffffffffff", 9007199254740991L),
      ("0X0001FFFFFFFFFFFFF", 9007199254740991L),
      ("9007199254740991", 9007199254740991L),
      ("0002", 2L),
    ] {
    assert_eq(exact_integer_literal(text), Some(value), msg=text)
  }
  for
    text in [
      "", "0x", "0xg", "0x1.0", "0x20000000000000", "0xffffffffffffffffffff", "9007199254740992",
      "1e1", "-1", "+1",
    ] {
    assert_true(exact_integer_literal(text) is None, msg=text)
  }
}

///|
test "malformed hex syntax is refused without reclassifying a partial token" {
  for text in ["0x", "0X", "0xG", "0x1.0", "0x1p1", "0x1g", "0x1_0"] {
    assert_true(
      tokenize(text, limits()) is Err({ issue: Lexical(InvalidNumber), .. }),
      msg=text,
    )
  }
  assert_true(tokenize("0x10", { ..limits(), max_literal_bytes: 3, }) is Err(_))
  assert_true(tokenize("0x10", { ..limits(), max_work: 3, }) is Err(_))
}

///|
test "hex LIMIT and OFFSET use the same exact integer domain" {
  for
    text in [
      "SELECT id FROM orders LIMIT 0x2 OFFSET 0X1", "FROM orders |> LIMIT 0x2 OFFSET 0X1",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_true(
      operation_at(query, operation_count(query) - 1)
      is Some(Limit(Integer(2L), Integer(1L))),
    )
  }
  for operand in ["0x0", "0x20000000000000"] {
    assert_true(
      parse_query("SELECT id FROM orders LIMIT " + operand, query_limits())
      is Err({ issue: Syntax(_), .. }),
    )
  }
}

///|
test "hex bounded type arguments preserve precision scale and their limits" {
  let expression = parse_expression(
    "CAST(1 AS DECIMAL(0xA, 0X2))",
    expression_limits(),
  ).unwrap()
  assert_true(
    kind(expression, expression_root(expression)) is Cast(_, Decimal(10, 2)),
  )
  for text in ["CAST(1 AS DECIMAL(0x27, 0x2))", "CAST(1 AS DECIMAL(0xA, 0xb))"] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
}
