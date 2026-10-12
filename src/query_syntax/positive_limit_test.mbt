///|
test "positive LIMIT and OFFSET keep exact integer or whole parameter slots" {
  for
    (text, expected_count, expected_offset) in [
      ("LIMIT +2 OFFSET +0", 2L, 0L),
      ("LIMIT +((0x2)) OFFSET ++(0X1)", 2L, 1L),
      ("LIMIT (+((2))) OFFSET (++1)", 2L, 1L),
      ("LIMIT +9007199254740991", 9007199254740991L, 0L),
    ] {
    let query = parse_query("SELECT id FROM orders " + text, query_limits()).unwrap()
    guard operation_at(query, operation_count(query) - 1)
      is Some(Limit(Integer(count), Integer(offset))) else {
      fail("Positive literal must retain its integer role")
    }
    assert_eq(count, expected_count)
    assert_eq(offset, expected_offset)
  }
  for
    text in [
      "SELECT id FROM orders ORDER BY id LIMIT +@count OFFSET +(@skip)", "FROM orders |> ORDER BY id |> LIMIT (+@count) OFFSET ++((@skip))",
      "SELECT id FROM orders UNION ALL SELECT id FROM orders ORDER BY id LIMIT +(@count) OFFSET (+@skip)",
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
}

///|
test "positive LIMIT never folds an expression or bypasses integer admission" {
  for
    operand in ["+id", "+(@p + 1)", "+NULL", "+'2'", "+TRUE", "+(-1)", "+@p.id"] {
    for clause in ["LIMIT " + operand, "LIMIT 1 OFFSET " + operand] {
      assert_true(
        parse_query("SELECT id FROM orders " + clause, query_limits())
        is Err({ issue: Syntax("Expected integer literal or parameter"), .. }),
        msg=clause,
      )
    }
  }
  assert_true(
    parse_query("SELECT id FROM orders LIMIT +0", query_limits())
    is Err({ issue: Syntax("Expected positive integer literal"), .. }),
  )
  for operand in ["+1.5", "+9007199254740992"] {
    assert_true(
      parse_query("SELECT id FROM orders LIMIT " + operand, query_limits())
      is Err({ issue: Syntax("Integer literal exceeds safe range"), .. }),
      msg=operand,
    )
  }
}

///|
test "positive LIMIT uses the existing expression depth and node limits" {
  let limits = query_limits()
  assert_true(
    parse_query("SELECT id FROM orders LIMIT +++2", {
      ..limits,
      expression: { ..limits.expression, max_depth: 3, },
    })
    is Err({ issue: Syntax("Expression depth limit"), .. }),
  )
  assert_true(
    parse_query("SELECT id FROM orders LIMIT ++2", {
      ..limits,
      expression: { ..limits.expression, max_nodes: 2, },
    })
    is Err({ issue: Syntax("Expression node limit"), .. }),
  )
}
