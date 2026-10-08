///|
test "SQL GROUP BY ALL survives operation snapshots and aggregate ORDER" {
  let query = parse_query(
    "SELECT x FROM t GROUP BY ALL ORDER BY COUNT(*)",
    query_limits(),
  ).unwrap()
  for _ in 0..<2 {
    guard operation_at(query, 0) is Some(Group(keys, projections, SqlSelectAll)) else {
      fail("inferred keys retain their SQL input scope")
    }
    assert_eq(keys.length(), 0)
    assert_true(projections.any(item => item.aggregate is Some(_)))
    keys.push(parse_expression("x", expression_limits()).unwrap())
  }
}

///|
test "a quoted ALL remains an explicit GROUP key" {
  let query = parse_query("SELECT `ALL` FROM t GROUP BY `ALL`", query_limits()).unwrap()
  assert_true(operation_at(query, 0) is Some(Group([_], _, SqlSelect)))
}
