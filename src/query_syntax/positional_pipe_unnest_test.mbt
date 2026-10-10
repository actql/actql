///|
test "correlated Pipe UNNEST consumes the current projection without an ordinary JOIN capture" {
  let query = parse_query(
    "FROM t |> SELECT x AS kept,-y |> CROSS JOIN UNNEST([10,20]) AS element |> SELECT *",
    query_limits(),
  ).unwrap()
  assert_eq(cte_count(query), 0)
  assert_eq(operation_count(query), 3)
  assert_true(operation_at(query, 0) is Some(Select(_, _)))
  assert_true(operation_at(query, 1) is Some(UnnestSource(_, _, _)))
  assert_true(operation_at(query, 2) is Some(Select(_, _)))
}
