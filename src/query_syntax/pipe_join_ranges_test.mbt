///|
test "Pipe JOIN accepts changed current rows while retaining immutable ranges" {
  for prefix in ["SET a = a + 10", "DROP a", "RENAME a AS current"] {
    let query = parse_query(
      "FROM left_rows |> AS l |> " +
      prefix +
      " |> JOIN right_rows AS r ON l.a = r.c MAX_OUTPUT_ROWS 10 |> SELECT l.a AS original",
      query_limits(),
    ).unwrap()
    assert_eq(cte_count(query), 1)
    assert_true(cte_at(query, 0).unwrap().carry_ranges)
    assert_eq(join_part_count(query), 1)
  }
}

///|
test "authored CTEs export a row rather than the producer's old ranges" {
  let query = parse_query(
    "WITH chosen AS (FROM left_rows |> AS l |> SET a = 2) FROM chosen",
    query_limits(),
  ).unwrap()
  assert_false(cte_at(query, 0).unwrap().carry_ranges)
}
