///|
test "SELECT aggregate expression uses private calls without changing whole-call projections" {
  let query = parse_query(
    "SELECT COUNT(*) AS n, COUNT(*) + COUNT(*) AS twice FROM t",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Group(_, projections, SqlSelect)) else {
    fail("expected GROUP")
  }
  assert_eq(projections.length(), 4)
  assert_true(projections[0].aggregate is Some(_))
  assert_true(projections[1].expression is Some(_))
  assert_true(projections[2].aggregate is Some(_))
  assert_true(projections[3].aggregate is Some(_))
  guard operation_at(query, 1) is Some(Select(selected, false)) else {
    fail("expected SELECT")
  }
  assert_eq(selected.length(), 2)
  assert_true(selected[1].aggregate is None)
  assert_true(
    expression_origin(
      selected[1].expression.unwrap(),
      expression_root(selected[1].expression.unwrap()),
    )
    is Some(_),
  )
}

///|
test "SELECT aggregate expression retains analytic and placement boundaries" {
  let analytic = parse_query(
    "SELECT SUM(x) OVER (ORDER BY x) AS total FROM t",
    query_limits(),
  ).unwrap()
  assert_true(operation_at(analytic, 0) is Some(Analytic(_)))
  for
    source in [
      "SELECT COUNT(*) + 1 AS n FROM t WHERE COUNT(*) > 0", "FROM t |> EXTEND COUNT(*) + 1 AS n",
      "FROM t |> AGGREGATE COUNT(*) + 1 AS n",
    ] {
    assert_true(parse_query(source, query_limits()) is Err(_), msg=source)
  }
  let source = "SELECT COUNT(*) + SUM(x + 1) AS total FROM t"
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
