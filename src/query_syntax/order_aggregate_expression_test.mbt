///|
test "ORDER aggregate expression keeps calls private to its SQL Group" {
  let query = parse_query(
    "SELECT x FROM t GROUP BY x ORDER BY COUNT(*) + COUNT(*) DESC, x",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Group(_, projections, SqlSelect)) else {
    fail("expected SQL Group")
  }
  assert_eq(projections.length(), 3)
  assert_true(projections[1].aggregate is Some(_))
  assert_true(projections[2].aggregate is Some(_))
  guard operation_at(query, 1) is Some(Select(selected, false)) else {
    fail("expected authored SELECT")
  }
  assert_eq(selected.length(), 1)
  guard operation_at(query, 2) is Some(Order(terms)) else {
    fail("expected ORDER")
  }
  assert_eq(terms.length(), 2)
  assert_eq(terms[0].direction, "desc")
  assert_eq(terms[0].nulls, "last")
  assert_true(
    expression_origin(terms[0].expression, expression_root(terms[0].expression))
    is Some(_),
  )
}

///|
test "ORDER aggregate expression retains placement and resource boundaries" {
  let global = parse_query(
    "SELECT ROW_NUMBER() OVER (ORDER BY id) AS n FROM t ORDER BY COUNT(*)",
    query_limits(),
  ).unwrap()
  assert_true(operation_at(global, 0) is Some(Group(_, _, SqlSelect)))
  assert_true(operation_at(global, 1) is Some(Analytic(_)))
  assert_true(operation_at(global, 2) is Some(Select(_, _)))
  for
    source in [
      "FROM t |> ORDER BY COUNT(*)", "SELECT x FROM t UNION ALL SELECT x FROM t ORDER BY COUNT(*)",
      "SELECT x FROM t GROUP BY x ORDER BY COUNT(*) OVER ()",
    ] {
    assert_true(parse_query(source, query_limits()) is Err(_), msg=source)
  }
  let source = "SELECT x FROM t GROUP BY x ORDER BY COUNT(*) + SUM(y + 1)"
  let limits = query_limits()
  assert_true(parse_query(source, { ..limits, max_work: 30, }) is Err(_))
  assert_true(
    parse_query(source, {
      ..limits,
      expression: { ..limits.expression, max_nodes: 3, },
    })
    is Err(_),
  )
}
