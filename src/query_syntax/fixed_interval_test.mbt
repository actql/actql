///|
test "fixed SQL intervals retain full signed integer spelling without Number conversion" {
  for
    (text, expected) in [
      ("TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)", "1"),
      (
        "TIMESTAMP_ADD(stamp, INTERVAL 9007199254740993 MICROSECOND)", "9007199254740993",
      ),
      (
        "stamp - INTERVAL -9223372036854775808 NANOSECOND", "-9223372036854775808",
      ),
    ] {
    let expression = parse_expression(text, expression_limits()).unwrap()
    let mut found = false
    for index in 0..<expression_node_count(expression) {
      if expression_node(expression, index)
        is Some({ kind: Interval(child, _), .. }) {
        assert_true(
          expression_node(expression, child)
          is Some({ kind: StringLiteral(value), .. }) &&
          value == expected,
        )
        found = true
      }
    }
    assert_true(found)
  }
}

///|
test "Gmail unchanged public thread query admits its original fixed interval syntax" {
  let text = "FROM gmail.threads\n|> WHERE 'INBOX' IN UNNEST(labels) AND message_count = 1\n     AND last_message_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)\n|> SELECT id, subject, last_message_date\n|> ORDER BY last_message_date;\n"
  assert_true(parse_query(text, query_limits()) is Ok(_))
}

///|
test "fixed interval exact decimal and hexadecimal lexical boundaries retain the selected integer domain" {
  for
    (token, negative, expected) in [
      ("1", false, 1L),
      ("0001", false, 1L),
      ("0x20000000000001", false, 9007199254740993L),
      ("0X7fffffffffffffff", false, 9223372036854775807L),
      ("0x8000000000000000", true, -9223372036854775808L),
      ("9223372036854775808", true, -9223372036854775808L),
    ] {
    // Observe through the public AST, not a private numeric helper.
    let text = "stamp + INTERVAL " +
      (if negative { "-" } else { "" }) +
      token +
      " NANOSECOND"
    let expression = parse_expression(text, expression_limits()).unwrap()
    let root = expression_node(expression, expression_root(expression)).unwrap()
    guard root.kind is Binary(_, _, right) else { fail("interval receiver") }
    guard expression_node(expression, right)
      is Some({ kind: Interval(child, _), .. }) else {
      fail("interval role")
    }
    assert_true(
      expression_node(expression, child)
      is Some({ kind: StringLiteral(value), .. }) &&
      value == expected.to_string(),
    )
  }
  for
    token in [
      "9223372036854775808", "-9223372036854775809", "0x8000000000000000", "-0x8000000000000001",
      "1.5", "1e2", "-0",
    ] {
    assert_true(
      parse_expression(
        "stamp + INTERVAL " + token + " SECOND",
        expression_limits(),
      )
      is Err(_),
      msg=token,
    )
  }
}
