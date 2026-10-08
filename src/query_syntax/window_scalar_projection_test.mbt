///|
test "window expression operands retain source spans and private output ownership" {
  let text = "SELECT id, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM orders"
  let parsed = parse_query(text, query_limits(), source_path="operand.sql").unwrap()
  guard operation_at(parsed, 0) is Some(AnalyticExpressions(projections, names)) else {
    fail("embedded windows require explicit private bindings")
  }
  assert_eq(names.length(), 1)
  assert_eq(names[0].value, "aql_select_window_0")
  assert_eq(projections.length(), 3)
  guard operation_at(parsed, 1) is Some(Select(selected, false)) else {
    fail("ordinary projection is required")
  }
  let expression = selected[1].expression.unwrap()
  assert_true(
    expression_node(expression, expression_root(expression)).unwrap().kind
    is Binary("+", _, _),
  )
  for index in 0..<expression_node_count(expression) {
    if expression_node(expression, index).unwrap().kind is Reference(path) &&
      path == [names[0]] {
      let span = @origin.span(expression_origin(expression, index).unwrap())
      assert_eq(span.source_path, "operand.sql")
      assert_eq(span.start_column, 12)
      assert_eq(span.end_column, 43)
    }
  }
}

///|
test "window expression extraction retains ordinary parser budgets and invalid placement" {
  let text = "SELECT ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM orders"
  let limits = query_limits()
  assert_true(
    parse_query(text, {
      ..limits,
      expression: { ..limits.expression, max_nodes: 1, },
    })
    is Err(_),
  )
  assert_true(parse_query(text, { ..limits, max_syntax_nodes: 1, }) is Err(_))
  assert_true(parse_query(text, { ..limits, max_work: 1, }) is Err(_))
  for
    invalid in [
      "SELECT ROW_NUMBER() OVER (ORDER BY id) + AS pos FROM orders", "SELECT id FROM orders WHERE ROW_NUMBER() OVER (ORDER BY id) > 1",
      "FROM orders |> EXTEND ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos",
    ] {
    assert_true(
      parse_query(invalid, limits) is Err({ issue: Syntax(_), .. }),
      msg=invalid,
    )
  }
}
