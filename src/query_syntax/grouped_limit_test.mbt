///|
test "grouped LIMIT and OFFSET retain distinct integer and Parameter roles" {
  for
    text in [
      "SELECT id FROM orders ORDER BY id LIMIT ((@count)) OFFSET (@skip)", "FROM orders |> ORDER BY id |> LIMIT (@count) OFFSET ((@skip))",
      "SELECT id FROM orders UNION ALL SELECT id FROM orders ORDER BY id LIMIT ((@count)) OFFSET (@skip)",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    let last = if set_part_count(query) == 0 {
      operation_at(query, operation_count(query) - 1)
    } else {
      final_operation_at(query, final_operation_count(query) - 1)
    }
    assert_true(
      last is Some(Limit(BoundParameter("count"), BoundParameter("skip"))),
    )
  }
  for
    (text, expected) in [
      ("LIMIT ((2)) OFFSET (0)", Limit(Integer(2L), Integer(0L))),
      (
        "LIMIT (@`COUNT`) OFFSET ((1))",
        Limit(BoundParameter("COUNT"), Integer(1L)),
      ),
      (
        "LIMIT (9007199254740991)",
        Limit(Integer(9007199254740991L), Integer(0L)),
      ),
    ] {
    let query = parse_query("SELECT id FROM orders " + text, query_limits()).unwrap()
    assert_eq(operation_at(query, operation_count(query) - 1), Some(expected))
  }
}

///|
test "grouped LIMIT does not fold expressions or weaken the integer domain" {
  for
    operand in [
      "(id)", "(@p + 1)", "((2 + 1))", "(NULL)", "('2')", "(-2)", "(+2)", "(@p.id)",
    ] {
    for clause in ["LIMIT " + operand, "LIMIT 1 OFFSET " + operand] {
      assert_true(
        parse_query("SELECT id FROM orders " + clause, query_limits())
        is Err({ issue: Syntax("Expected integer literal or parameter"), .. }),
        msg=clause,
      )
    }
  }
  assert_true(
    parse_query("SELECT id FROM orders LIMIT (0)", query_limits())
    is Err({ issue: Syntax("Expected positive integer literal"), .. }),
  )
  for operand in ["(1.5)", "(9007199254740992)"] {
    assert_true(
      parse_query("SELECT id FROM orders LIMIT " + operand, query_limits())
      is Err({ issue: Syntax("Integer literal exceeds safe range"), .. }),
    )
  }
}

///|
test "grouped LIMIT uses existing expression depth and node budgets" {
  let limits = query_limits()
  assert_true(
    parse_query("SELECT id FROM orders LIMIT (((2)))", {
      ..limits,
      expression: { ..limits.expression, max_depth: 3, },
    })
    is Err({ issue: Syntax("Expression depth limit"), .. }),
  )
  assert_true(
    parse_query("SELECT id FROM orders LIMIT ((2))", {
      ..limits,
      expression: { ..limits.expression, max_nodes: 3, },
    })
    is Err({ issue: Syntax("Expression node limit"), .. }),
  )
}
