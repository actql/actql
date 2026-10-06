///|
test "star REPLACE records original expressions targets and unchanged receiver" {
  let parsed = parse_query(
    "SELECT q.* EXCEPT (gone) REPLACE (y AS `X`, x AS y) FROM rows AS q",
    query_limits(),
  ).unwrap()
  guard operation_at(parsed, 0) is Some(Select(projections, false)) else {
    fail("expected SELECT")
  }
  assert_eq(projections[0].replacements[0].name, { value: "X", quoted: true, })
  let expression = projections[0].replacements[0].expression.unwrap()
  assert_eq(
    expression_node(expression, expression_root(expression)).unwrap().kind,
    Reference([{ value: "y", quoted: false, }]),
  )
  assert_eq(projections[0].replacements[1].name, { value: "y", quoted: false, })
  projections[0].replacements.clear()
  guard operation_at(parsed, 0) is Some(Select(original, _)) else {
    fail("expected retained SELECT")
  }
  assert_eq(original[0].replacements.length(), 2)
}

///|
test "star REPLACE keeps explicit AS and normal expression query budgets" {
  for
    source in [
      "SELECT * REPLACE () FROM t", "SELECT * REPLACE (x y) FROM t", "SELECT * REPLACE (x AS y,) FROM t",
      "SELECT * REPLACE (x AS y FROM t",
    ] {
    assert_true(parse_query(source, query_limits()) is Err(_), msg=source)
  }
  let limits = query_limits()
  assert_true(
    parse_query("SELECT * REPLACE (x + y AS x) FROM t", {
      ..limits,
      expression: { ..limits.expression, max_nodes: 1, },
    })
    is Err(_),
  )
}
