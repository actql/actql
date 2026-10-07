///|
test "Pipe JOIN consumes the projected left producer and its current alias" {
  let query = parse_query(
    "FROM left_rows AS old |> SELECT a AS id |> AS l |> WHERE l.id > 0 |> ORDER BY id |> LIMIT 1 |> JOIN right_rows AS r ON l.id = r.c MAX_OUTPUT_ROWS 10 |> SELECT l.id, r.d",
    query_limits(),
  ).unwrap()
  assert_eq(cte_count(query), 1)
  assert_eq(relation_alias(query), Some({ value: "l", quoted: false, }))
  let input = cte_at(query, 0).unwrap().query
  assert_eq(relation(input), [{ value: "left_rows", quoted: false, }])
  assert_eq(operation_count(input), 5)
  assert_eq(join_part_count(query), 1)
  assert_eq(join_part_at(query, 0).unwrap().max_output_rows, Some(10L))
  assert_eq(operation_count(query), 1)
}

///|
test "Pipe JOIN preserves a pre-join WHERE between fused joins" {
  let query = parse_query(
    "FROM left_rows AS l |> JOIN right_rows AS r ON l.a = r.c |> WHERE r.d = 'keep' |> JOIN left_rows AS s ON r.c = s.a |> SELECT l.a",
    query_limits(),
  ).unwrap()
  assert_eq(cte_count(query), 0)
  assert_eq(join_part_count(query), 2)
  assert_true(join_part_at(query, 1).unwrap().pre_join_filter is Some(_))
}

///|
test "Pipe JOIN producer composition respects the existing CTE budget" {
  assert_true(
    parse_query(
      "FROM left_rows |> SELECT a AS id |> CROSS JOIN right_rows AS r |> SELECT id |> CROSS JOIN right_rows AS s |> SELECT id",
      { ..query_limits(), max_cte_count: 1, },
    )
    is Err(_),
  )
}
