///|
test "ROWS wrappers retain integer parameter and direction roles" {
  for
    (operand, expected) in [
      ("(+0)", FrameBoundary::Preceding(0L)),
      ("++((2))", FrameBoundary::Preceding(2L)),
      ("++((0x2))", FrameBoundary::Preceding(2L)),
      ("((@before))", FrameBoundary::PrecedingParameter("before")),
      ("+(+@before)", FrameBoundary::PrecedingParameter("before")),
    ] {
    let parsed = parse_query(
      "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS BETWEEN " +
      operand +
      " PRECEDING AND (+@after) FOLLOWING) AS first FROM orders",
      query_limits(),
    ).unwrap()
    guard operation_at(parsed, 0) is Some(Analytic(projections)) else {
      fail("expected analytic operation")
    }
    let frame = projections[0].analytic.unwrap().window.frame.unwrap()
    assert_eq(frame.start, expected)
    assert_eq(frame.end, FrameBoundary::FollowingParameter("after"))
  }
  let parsed = parse_query(
    "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS (+0) PRECEDING) AS first FROM orders",
    query_limits(),
  ).unwrap()
  guard operation_at(parsed, 0) is Some(Analytic(projections)) else {
    fail("expected analytic operation")
  }
  let frame = projections[0].analytic.unwrap().window.frame.unwrap()
  assert_eq(frame.start, FrameBoundary::Preceding(0L))
  assert_eq(frame.end, FrameBoundary::CurrentRow)
}

///|
test "ROWS wrappers refuse arbitrary expressions and unsafe integers" {
  for operand in ["(id)", "+(@before + 1)", "+(-1)", "(+NULL)"] {
    let text = "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS " +
      operand +
      " PRECEDING) AS first FROM orders"
    assert_true(
      parse_query(text, query_limits())
      is Err({ issue: Syntax("Expected integer literal or parameter"), .. }),
      msg=operand,
    )
  }
  for operand in ["(+1.5)", "(9007199254740992)"] {
    let text = "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS " +
      operand +
      " PRECEDING) AS first FROM orders"
    assert_true(
      parse_query(text, query_limits())
      is Err({ issue: Syntax("Integer literal exceeds safe range"), .. }),
      msg=operand,
    )
  }
}

///|
test "ROWS wrappers spend the existing expression node and depth budgets" {
  let limits = query_limits()
  let plain = "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS 2 PRECEDING) AS first FROM orders"
  let text = "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS (((2))) PRECEDING) AS first FROM orders"
  assert_true(
    parse_query(plain, {
      ..limits,
      expression: { ..limits.expression, max_nodes: 5, },
    })
    is Ok(_),
  )
  assert_true(
    parse_query(text, {
      ..limits,
      expression: { ..limits.expression, max_nodes: 5, },
    })
    is Err({ issue: Syntax("Expression node limit"), .. }),
  )
  assert_true(
    parse_query(plain, {
      ..limits,
      expression: { ..limits.expression, max_depth: 3, },
    })
    is Ok(_),
  )
  assert_true(
    parse_query(text, {
      ..limits,
      expression: { ..limits.expression, max_depth: 3, },
    })
    is Err({ issue: Syntax("Expression depth limit"), .. }),
  )
}
