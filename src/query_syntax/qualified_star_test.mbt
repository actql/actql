///|
test "range-star syntax retains receiver names quotation and source range" {
  let source = "SELECT `a.b`.* EXCEPT (`Mixed`) FROM rows AS `a.b`"
  let parsed = parse_query(source, query_limits()).unwrap()
  guard operation_at(parsed, 0) is Some(Select(projections, false)) else {
    fail("expected star projection")
  }
  assert_eq(projections[0].star, Some("*"))
  let receiver = projections[0].expression.unwrap()
  let node = expression_node(receiver, expression_root(receiver)).unwrap()
  assert_eq(node.kind, Reference([{ value: "a.b", quoted: true, }]))
  assert_eq(node.start, 7)
  assert_eq(node.end, 12)
  assert_eq(projections[0].except_columns, [{ value: "Mixed", quoted: true, }])
}

///|
test "range-star lookahead retains malformed input and expression budgets" {
  for
    source in [
      "SELECT a. FROM rows", "SELECT a..* FROM rows", "SELECT a.* EXCEPT () FROM rows",
    ] {
    assert_true(parse_query(source, query_limits()) is Err(_), msg=source)
  }
  let limits = query_limits()
  assert_true(
    parse_query("SELECT a.* FROM rows AS a", {
      ..limits,
      expression: { ..limits.expression, max_nodes: 0, },
    })
    is Err(_),
  )
  assert_true(
    parse_query("SELECT a.b.c.* FROM rows", { ..limits, max_work: 2, })
    is Err(_),
  )
}
