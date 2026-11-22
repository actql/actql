///|
test "SQL ROLLUP retains original grouping item boundaries and aggregate ORDER" {
  let query = parse_query(
    "SELECT x, (y) + 1 AS k FROM t GROUP BY ROLLUP(x, (y, (z) + 1), (y) + 1) ORDER BY COUNT(*)",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0)
    is Some(Group(keys, projections, SqlRollup(ends))) else {
    fail("expected one SQL ROLLUP operation")
  }
  assert_eq(ends, [1, 3, 4])
  assert_eq(rollup_item_count(query), 3)
  assert_eq(keys.length(), 4)
  assert_true(projections.any(projection => projection.aggregate is Some(_)))
  ends[0] = 4
  guard operation_at(query, 0) is Some(Group(_, _, SqlRollup(original))) else {
    fail("expected the same SQL ROLLUP operation")
  }
  assert_eq(original, [1, 3, 4])
}

///|
test "SQL ROLLUP rejects an empty item list and keeps a quoted ordinary key" {
  assert_true(
    parse_query("SELECT x FROM t GROUP BY ROLLUP()", query_limits()) is Err(_),
  )
  let query = parse_query(
    "SELECT `ROLLUP` FROM t GROUP BY `ROLLUP`",
    query_limits(),
  ).unwrap()
  assert_true(operation_at(query, 0) is Some(Group([_], _, SqlSelect)))
}
