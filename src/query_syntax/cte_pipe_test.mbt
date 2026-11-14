///|
test "WITH selects either query head and keeps Pipe CTE operations" {
  for
    text in [
      "WITH chosen AS (SELECT id FROM orders WHERE id > 1) FROM chosen |> SELECT id;",
      "WITH chosen AS (FROM orders |> WHERE id > 1 |> SELECT id) SELECT id FROM chosen;",
      "WITH chosen AS (FROM orders |> WHERE id > 1 |> SELECT id) FROM chosen |> SELECT id;",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_eq(query_binding_count(query), 1)
    let body = query_binding_at(query, 0).unwrap().query
    assert_eq(query_binding_count(body), 0)
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
  assert_eq(query_binding_count(query), 2)
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
  assert_eq(operation_count(query_binding_at(query, 0).unwrap().query), 3)
}

///|
test "CTE name processing spends the original parser work before folding" {
  let short = "WITH a AS (SELECT 1 AS n),b AS (SELECT 2 AS n) SELECT n FROM a"
  let left = "a" + "x".repeat(256)
  let right = "b" + "y".repeat(256)
  let long = "WITH " +
    left +
    " AS (SELECT 1 AS n)," +
    right +
    " AS (SELECT 2 AS n) SELECT n FROM " +
    left
  let short_work = query_work(parse_query(short, query_limits()).unwrap())
  let long_query = parse_query(long, query_limits()).unwrap()
  let long_work = query_work(long_query)
  assert_true(
    long_work > short_work,
    msg="original CTE name comparisons/folds must consume the SAME parser work",
  )
  match parse_query(long, { ..query_limits(), max_work: short_work, }) {
    Err({ issue: Syntax(message), .. }) =>
      assert_eq(message, "Query work limit")
    _ => fail("long original names must refuse before uncharged processing")
  }
  assert_true(
    parse_query(long, { ..query_limits(), max_work: long_work, }) is Ok(_),
  )
  assert_true(
    parse_query(long, { ..query_limits(), max_work: long_work - 1, }) is Err(_),
  )
  assert_true(
    parse_query(long, { ..query_limits(), max_cte_count: 1, }) is Err(_),
  )
  match
    parse_query(
      "WITH foo AS (SELECT 1 AS n),fOo AS (SELECT 2 AS n) SELECT n FROM foo",
      query_limits(),
    ) {
    Err({ issue: Syntax(message), .. }) =>
      assert_eq(message, "Duplicate CTE name")
    _ => fail("same original case-insensitive duplicate rule must refuse")
  }
}
