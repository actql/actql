///|
test "WITH selects either query head and keeps Pipe CTE operations" {
  for
    text in [
      "WITH chosen AS (SELECT id FROM orders WHERE id > 1) FROM chosen |> SELECT id;",
      "WITH chosen AS (FROM orders |> WHERE id > 1 |> SELECT id) SELECT id FROM chosen;",
      "WITH chosen AS (FROM orders |> WHERE id > 1 |> SELECT id) FROM chosen |> SELECT id;",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_eq(cte_count(query), 1)
    let body = cte_at(query, 0).unwrap().query
    assert_eq(cte_count(body), 0)
    assert_eq(relation(body), [{ value: "orders", quoted: false, }])
    assert_eq(operation_count(body), 2)
    assert_true(operation_at(body, 0) is Some(Where(_)))
    assert_true(operation_at(body, 1) is Some(Select(_, false)))
    assert_eq(relation(query), [{ value: "chosen", quoted: false, }])
    assert_eq(operation_count(query), 1)
  }
}

///|
test "Pipe CTE count and work are charged once in the original source" {
  let text = "WITH first AS (FROM orders |> SELECT id), second AS (FROM first |> WHERE id > 1) FROM second |> SELECT id"
  let query = parse_query(text, { ..query_limits(), max_cte_count: 2, }).unwrap()
  assert_eq(cte_count(query), 2)
  assert_true(
    parse_query(text, { ..query_limits(), max_cte_count: 1, }) is Err(_),
  )
  let work = query_work(query)
  assert_true(parse_query(text, { ..query_limits(), max_work: work, }) is Ok(_))
  assert_true(
    parse_query(text, { ..query_limits(), max_work: work - 1, }) is Err(_),
  )
  assert_true(
    parse_query(text, { ..query_limits(), max_syntax_nodes: 1, }) is Err(_),
  )
}

///|
test "Pipe CTE stops at its own delimiter and excludes INFER" {
  for
    text in [
      "WITH c AS (FROM orders |> SELECT id; ) FROM c |> SELECT id", "WITH c AS (FROM orders |> SELECT id) FROM c |> SELECT id; SELECT id FROM c",
      "WITH c AS (FROM orders |> SELECT id FROM c |> SELECT id", "WITH c AS (FROM orders |> INFER risk ITEM KEY (id) INPUT (n = id) AS assessment) FROM c |> SELECT assessment",
      "WITH RECURSIVE c AS (FROM orders |> SELECT id) FROM c |> SELECT id",
    ] {
    match parse_query(text, query_limits(), source_path="cte.pipe") {
      Err({ span: Some(span), .. }) => assert_eq(span.source_path, "cte.pipe")
      _ => fail("invalid CTE must retain an original-source diagnostic")
    }
  }
  let query = parse_query(
    "WITH c AS (FROM orders |> SELECT id |> ORDER BY id DESC |> LIMIT 2) FROM c |> SELECT id",
    query_limits(),
  ).unwrap()
  assert_eq(operation_count(cte_at(query, 0).unwrap().query), 3)
}
