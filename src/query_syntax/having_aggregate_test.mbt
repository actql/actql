///|
test "HAVING aggregate primaries preserve arguments and owned observations" {
  let query = parse_query(
    "SELECT id FROM records GROUP BY id HAVING COUNT(*) > 1 AND COUNT(DISTINCT amount) > 0",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 1) is Some(Having(expression, calls)) else {
    fail("expected an aggregate-bearing HAVING")
  }
  assert_eq(calls.length(), 2)
  assert_eq(calls[0].1.function_name, "COUNT")
  assert_true(calls[0].1.argument is None)
  assert_true(calls[1].1.distinct)
  assert_true(calls[1].1.argument is Some(_))
  assert_true(
    expression_origin(expression, expression_root(expression)) is Some(_),
  )
  calls.clear()
  guard operation_at(query, 1) is Some(Having(_, fresh)) else {
    fail("expected owned HAVING observation")
  }
  assert_eq(fresh.length(), 2)
}

///|
test "HAVING aggregate parsing retains clause placement and finite budgets" {
  for
    text in [
      "SELECT id FROM records WHERE COUNT(*) > 0", "SELECT id FROM records HAVING id > 0",
      "SELECT id FROM records GROUP BY id HAVING COUNT() > 0", "SELECT id FROM records GROUP BY id HAVING COUNT(DISTINCT *) > 0",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
  let text = "SELECT id FROM records GROUP BY id HAVING SUM(id + 1) > 0"
  let limits = query_limits()
  assert_true(
    parse_query(text, {
      ..limits,
      expression: { ..limits.expression, max_nodes: 4, },
    })
    is Err(_),
  )
  assert_true(
    parse_query(text, {
      ..limits,
      expression: { ..limits.expression, max_depth: 1, },
    })
    is Err(_),
  )
  assert_true(parse_query(text, { ..limits, max_work: 30, }) is Err(_))
}
