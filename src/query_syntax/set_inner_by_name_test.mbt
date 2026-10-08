///|
test "INNER set prefix stays distinct from JOIN and positional set syntax" {
  for
    text in [
      "SELECT id FROM orders INNER UNION ALL SELECT id FROM orders", "FROM orders |> INNER UNION ALL (FROM orders |> SELECT id)",
      "SELECT id FROM orders INNER UNION ALL BY NAME SELECT id FROM orders UNION ALL BY NAME SELECT id FROM orders",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
  let query = parse_query(
    "SELECT l.id FROM orders l INNER JOIN orders r ON l.id = r.id",
    query_limits(),
  ).unwrap()
  assert_eq(join_part_count(query), 1)
  assert_eq(set_part_count(query), 0)
  let sql = parse_query(
    "SELECT id FROM orders INNER UNION ALL BY NAME SELECT id FROM orders",
    query_limits(),
  ).unwrap()
  assert_true(set_part_at(sql, 0).unwrap().inner_by_name)
  assert_true(set_part_at(sql, 0).unwrap().sql_chain)
  let pipe = parse_query(
    "FROM orders |> INNER UNION ALL BY NAME (FROM orders)",
    query_limits(),
  ).unwrap()
  assert_true(set_part_at(pipe, 0).unwrap().inner_by_name)
  assert_false(set_part_at(pipe, 0).unwrap().sql_chain)
}
