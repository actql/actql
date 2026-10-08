///|
test "computed star syntax retains ordinary receiver trees and shared modifiers" {
  for
    text in [
      "SELECT COALESCE(payload, other).* FROM objects", "SELECT (CASE WHEN id = 2 THEN other ELSE payload END).* FROM objects",
      "SELECT (payload).`nested`.* EXCEPT (score) REPLACE (1 AS value) FROM objects",
      "FROM objects |> SELECT (@value).*",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    guard operation_at(query, 0) is Some(Select(projections, false)) else {
      fail("expected receiver-star projection")
    }
    assert_eq(projections[0].star, Some("*"))
    let receiver = projections[0].expression.unwrap()
    assert_false(
      expression_node(receiver, expression_root(receiver)).unwrap().kind
      is Reference(_),
    )
    assert_true(expression_node_count(receiver) > 0)
  }
  let query = parse_query(
    "SELECT (payload).`nested`.* EXCEPT (score) REPLACE (1 AS value) FROM objects",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Select(projections, false)) else {
    fail("expected receiver-star projection")
  }
  let receiver = projections[0].expression.unwrap()
  assert_true(
    expression_node(receiver, expression_root(receiver)).unwrap().kind
    is Property(_, { value: "nested", quoted: true, }),
  )
  assert_eq(projections[0].except_columns, [{ value: "score", quoted: false, }])
  assert_eq(projections[0].replacements[0].name, {
    value: "value",
    quoted: false,
  })
  let field = star_column_projection(query, projections[0], "other")
  let expression = field.expression.unwrap()
  assert_true(
    expression_node(expression, expression_root(expression)).unwrap().kind
    is Property(_, { value: "other", quoted: true, }),
  )
}

///|
test "computed star suffix stays query-owned and preserves syntax limits" {
  assert_true(
    parse_expression("COALESCE(payload, other).*", expression_limits())
    is Err(_),
  )
  for
    text in [
      "SELECT (payload).", "SELECT (payload).* AS expanded FROM objects", "SELECT COALESCE(payload, other).* EXCEPT () FROM objects",
      "SELECT (payload).* REPLACE (1 AS value).* FROM objects",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
  let limits = query_limits()
  assert_true(
    parse_query("SELECT COALESCE(payload, other).* FROM objects", {
      ..limits,
      expression: { ..limits.expression, max_nodes: 2, },
    })
    is Err(_),
  )
  assert_true(
    parse_query("SELECT (((payload))).* FROM objects", {
      ..limits,
      expression: { ..limits.expression, max_depth: 2, },
    })
    is Err(_),
  )
}
