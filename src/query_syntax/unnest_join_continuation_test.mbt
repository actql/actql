///|
test "SQL and Pipe bind expansion before a subsequent ordinary JOIN" {
  for
    text in [
      "SELECT e, position FROM UNNEST(@items) e WITH OFFSET position JOIN rights r ON e = r.id MAX_OUTPUT_ROWS 10 ORDER BY position",
      "FROM UNNEST(@items) e WITH OFFSET position |> JOIN rights r ON e = r.id MAX_OUTPUT_ROWS 10 |> SELECT e, position |> ORDER BY position",
      "SELECT p.id FROM parents p JOIN rights r ON p.id = r.id CROSS JOIN UNNEST(p.items) e JOIN others o ON e = o.id MAX_OUTPUT_ROWS 10",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_eq(query_binding_count(query), 1)
    let expanded = query_binding_at(query, 0).unwrap()
    assert_true(expanded.carry_ranges)
    assert_eq(join_part_count(query), 1)
    assert_eq(join_part_at(query, 0).unwrap().max_output_rows, Some(10L))
    assert_true(
      operation_at(expanded.query, operation_count(expanded.query) - 1)
      is Some(UnnestSource(_, _, _)),
    )
    assert_eq(
      join_part_count(expanded.query),
      if text.contains("parents") {
        1
      } else {
        0
      },
    )
  }
}

///|
test "UNNEST JOIN continuations retain the existing producer budget" {
  assert_true(
    parse_query(
      "SELECT e FROM UNNEST(@items) e JOIN rights r ON e = r.id CROSS JOIN UNNEST(@items) second JOIN others o ON second = o.id",
      { ..query_limits(), max_cte_count: 1, },
    )
    is Err(_),
  )
}
