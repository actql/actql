///|
test "optional source AS retains quoted aliases on both JOIN inputs" {
  for
    text in [
      "SELECT `ORDER`.id FROM records `ORDER` JOIN keys `JOIN` ON `ORDER`.id = `JOIN`.key MAX_OUTPUT_ROWS 4",
      "FROM records `ORDER` |> JOIN keys `JOIN` ON `ORDER`.id = `JOIN`.key MAX_OUTPUT_ROWS 4 |> SELECT `ORDER`.id",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_eq(relation_alias(query), Some({ value: "ORDER", quoted: true, }))
    assert_eq(
      join_part_at(query, 0).unwrap().source_alias,
      Some({ value: "JOIN", quoted: true, }),
    )
  }
}

///|
test "optional quoted aliases do not consume unquoted clause starters" {
  let query = parse_query(
    "SELECT id FROM records WHERE id > 0 ORDER BY id",
    query_limits(),
  ).unwrap()
  assert_eq(relation_alias(query), None)
  assert_eq(operation_count(query), 3)
}
