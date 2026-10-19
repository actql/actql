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
