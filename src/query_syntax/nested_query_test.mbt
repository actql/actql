///|
test "derived sources share SELECT and Pipe query heads" {
  for
    text in [
      "SELECT a FROM (SELECT a FROM rows WHERE a > 0) AS selected", "SELECT a FROM (FROM rows |> WHERE a > 0 |> SELECT a) AS selected",
      "SELECT a FROM (SELECT a FROM rows |> WHERE a > 0) AS selected", "FROM (FROM rows |> SELECT a |> WHERE a > 0) AS selected |> SELECT a",
      "WITH chosen AS (SELECT a FROM rows ORDER BY a LIMIT 1) SELECT a FROM chosen",
    ] {
    let query = match parse_query(text, query_limits()) {
      Ok(query) => query
      Err(_) => fail(text)
    }
    assert_eq(cte_count(query), 1)
    assert_eq(
      operation_count(cte_at(query, 0).unwrap().query),
      if text.contains("LIMIT") {
        3
      } else {
        2
      },
    )
  }
}

///|
test "nested Pipe source uses the original query budgets and source origin" {
  let text = "SELECT a FROM (FROM rows |> WHERE a > 0 |> SELECT a) AS chosen"
  assert_true(
    parse_query(text, { ..query_limits(), max_cte_count: 1, }) is Ok(_),
  )
  assert_true(
    parse_query(text, { ..query_limits(), max_cte_count: 0, }) is Err(_),
  )
  assert_true(
    parse_query(text, { ..query_limits(), max_syntax_nodes: 1, }) is Err(_),
  )
  let query = parse_query(text, query_limits(), source_path="derived.pipe").unwrap()
  let inner = cte_at(query, 0).unwrap().query
  guard operation_at(inner, 0) is Some(Where(expression)) else {
    fail("WHERE is first")
  }
  let span = @origin.span(
    expression_origin(expression, expression_root(expression)).unwrap(),
  )
  assert_eq(span.source_path, "derived.pipe")
  assert_eq(span.start_line, 1)
  // Predicate `a` follows the 34-character authored prefix through WHERE.
  assert_eq(span.start_column, 35)
}

///|
test "nested relational query stops at its own boundary" {
  for
    text in [
      "SELECT a FROM (FROM rows |> SELECT a;) AS selected", "SELECT a FROM (FROM rows |> SELECT a AS selected",
      "SELECT a FROM (FROM rows |> INFER task ITEM KEY (a) INPUT (n = a) AS outcome) AS selected",
      "SELECT a FROM (FROM GRAPH g |> MATCH WALK (n) |> SELECT n.id) AS selected",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}
