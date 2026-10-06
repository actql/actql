///|
test "LIMIT Parameters preserve count offset and omitted offset" {
  for
    text in [
      "SELECT id FROM orders ORDER BY id LIMIT @count OFFSET @skip", "FROM orders |> ORDER BY id |> LIMIT @count OFFSET @skip",
      "SELECT id FROM orders UNION ALL SELECT id FROM orders ORDER BY id LIMIT @count OFFSET @skip",
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
  let query = parse_query("SELECT id FROM orders LIMIT @count", query_limits()).unwrap()
  assert_true(
    operation_at(query, operation_count(query) - 1)
    is Some(Limit(BoundParameter("count"), Integer(0L))),
  )
  let query = parse_query(
    "SELECT id FROM orders LIMIT 2 OFFSET @skip",
    query_limits(),
  ).unwrap()
  assert_true(
    operation_at(query, operation_count(query) - 1)
    is Some(Limit(Integer(2L), BoundParameter("skip"))),
  )
}

///|
test "LIMIT Parameters refuse row expressions and partial parameter operands" {
  for operand in ["@p + 1", "id", "NULL", "'1'", "(@p)", "-@p", "@p.id"] {
    for clause in ["LIMIT " + operand, "LIMIT 1 OFFSET " + operand] {
      assert_true(
        parse_query("SELECT id FROM orders " + clause, query_limits())
        is Err({ issue: Syntax(_), .. }),
        msg=clause,
      )
    }
  }
}
