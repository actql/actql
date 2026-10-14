///|
test "initial FROM and SELECT share attached JOINs without an implicit projection" {
  let head = "FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 10"
  for text in ["SELECT l.id AS id " + head, head + " |> SELECT l.id AS id"] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_eq(join_part_count(query), 1)
    let part = join_part_at(query, 0).unwrap()
    assert_eq(part.kind, "inner")
    assert_eq(part.source_alias.unwrap().value, "r")
    assert_eq(part.max_output_rows, Some(10L))
    assert_true(part.on is Some(_))
  }
  let from_only = parse_query(head, query_limits()).unwrap()
  assert_eq(join_part_count(from_only), 1)
  assert_eq(operation_count(from_only), 0)
}

///|
test "initial JOIN sequence stops at the first explicit Pipe" {
  let query = parse_query(
    "FROM a AS aa JOIN b AS bb ON aa.id = bb.id MAX_OUTPUT_ROWS 7 CROSS JOIN c AS cc MAX_OUTPUT_ROWS 8 |> WHERE aa.id > 0 |> JOIN d AS dd ON aa.id = dd.id MAX_OUTPUT_ROWS 9 |> SELECT aa.id",
    query_limits(),
  ).unwrap()
  assert_eq(join_part_count(query), 3)
  assert_eq(join_part_at(query, 0).unwrap().max_output_rows, Some(7L))
  assert_eq(join_part_at(query, 1).unwrap().max_output_rows, Some(8L))
  assert_eq(join_part_at(query, 2).unwrap().max_output_rows, Some(9L))
  assert_true(join_part_at(query, 2).unwrap().pre_join_filter is Some(_))
}

///|
test "initial FROM retains correlated expansion before an ordinary JOIN" {
  for
    text in [
      "FROM UNNEST(@items) e WITH OFFSET position JOIN rights r ON e = r.id MAX_OUTPUT_ROWS 10 |> SELECT e, position",
      "FROM parents p JOIN rights r ON p.id = r.id CROSS JOIN UNNEST(p.items) e JOIN others o ON e = o.id MAX_OUTPUT_ROWS 10 |> SELECT p.id",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_eq(query_binding_count(query), 1)
    let expanded = query_binding_at(query, 0).unwrap()
    assert_true(expanded.carry_ranges)
    assert_true(
      operation_at(expanded.query, operation_count(expanded.query) - 1)
      is Some(UnnestSource(_, _, _)),
    )
    assert_eq(join_part_count(query), 1)
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
test "JOIN-only prefix is retained before a typed Carrier call" {
  let query = parse_query(
    "FROM candidates AS c CROSS JOIN labels AS l MAX_OUTPUT_ROWS 10 |> to_vectors(id: c.id, vector: c.embedding) |> vectors() |> SELECT id",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(query), 1)
  let prefix = query_binding_at(query, 0).unwrap()
  assert_eq(join_part_count(prefix.query), 1)
  assert_eq(operation_count(prefix.query), 0)
  assert_true(prefix.carry_ranges)
}

///|
test "initial Graph JOIN keeps the authored Graph expectation" {
  let query = parse_query(
    "FROM GRAPH g CROSS JOIN rows AS r MAX_OUTPUT_ROWS 10 |> node_rows()",
    query_limits(),
  ).unwrap()
  assert_eq(join_part_count(query), 1)
  assert_true(graph_query(query).unwrap().expectation is Some(_))
}

///|
test "subsequent operations still require each explicit Pipe delimiter" {
  for
    text in [
      "FROM left_rows l JOIN right_rows r ON l.id = r.id WHERE l.id > 0", "FROM left_rows l |> WHERE l.id > 0 JOIN right_rows r ON l.id = r.id",
      "FROM left_rows l |> JOIN right_rows r ON l.id = r.id JOIN other_rows o ON r.id = o.id",
      "FROM left_rows |> ORDER BY id LIMIT 1", "FROM left_rows |> SELECT id ORDER BY id",
      "FROM left_rows |> GROUP BY id",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
  assert_true(
    parse_query(
      "SELECT id FROM left_rows WHERE id > 0 ORDER BY id LIMIT 1 OFFSET 0",
      query_limits(),
    )
    is Ok(_),
  )
  assert_true(
    parse_query(
      "FROM left_rows |> ORDER BY id |> LIMIT 1 OFFSET 0",
      query_limits(),
    )
    is Ok(_),
  )
}

///|
test "initial FROM preserves continuation budgets and quoted keyword names" {
  let text = "FROM UNNEST(@items) e JOIN rights r ON e = r.id CROSS JOIN UNNEST(@items) second JOIN others o ON second = o.id"
  assert_true(
    parse_query(text, { ..query_limits(), max_cte_count: 1, }) is Err(_),
  )
  assert_true(
    parse_query(
      "FROM `WHERE` AS `INFER` -- JOIN is a comment\n CROSS JOIN rights r MAX_OUTPUT_ROWS 10 |> SELECT 'INFER WHERE JOIN' AS `GRAPH`",
      query_limits(),
    )
    is Ok(_),
  )
}
