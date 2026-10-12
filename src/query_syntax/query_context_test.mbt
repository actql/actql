///|
test "CTAS whole wrapper preserves Compute Result before filtered write" {
  let query = parse_query(
    "CREATE TABLE output AS (SELECT 1 AS id |> RESULT before_write |> WHERE id = 2)",
    query_limits(),
    source_path="with-context.sql",
  ).unwrap()
  assert_eq(terminal_table_effect(query).unwrap().target[0].value, "output")
  match operation_at(query, 1) {
    Some(RetainResult(name)) => assert_eq(name.value, "before_write")
    _ => fail("the earlier Result is still a real publication obligation")
  }
  assert_true(operation_at(query, 2) is Some(Where(_)))
}

///|
test "CTAS nonwrapper keeps set ORDER LIMIT and Pipe continuations" {
  let set = parse_query(
    "CREATE TABLE output AS (SELECT 2 AS id) UNION ALL (SELECT 1 AS id) ORDER BY id LIMIT 1",
    query_limits(),
  ).unwrap()
  assert_eq(set_part_count(set), 1)
  let right = set_part_at(set, 0).unwrap()
  assert_eq(right.kind, "union")
  assert_eq(right.duplicates, "all")
  assert_true(final_operation_at(set, 0) is Some(Order(_)))
  assert_true(
    final_operation_at(set, 1) is Some(Limit(Integer(1L), Integer(0L))),
  )
  let filtered = parse_query(
    "CREATE TABLE output AS (SELECT 1 AS id /* ) */) |> WHERE id = 2;",
    query_limits(),
  ).unwrap()
  assert_true(operation_at(filtered, 0) is Some(Where(_)))
  let result = parse_query(
    "CREATE TABLE output AS (SELECT 1 AS id) |> RESULT before_write",
    query_limits(),
  ).unwrap()
  assert_true(operation_at(result, 0) is Some(RetainResult(_)))
  // A ')' in a string is not the wrapper's closing token.
  ignore(
    parse_query("CREATE TABLE output AS (SELECT ')' AS value);", query_limits()).unwrap(),
  )
}

///|
test "Pure producer placement refuses Result at the original source token" {
  for
    (text, offset) in [
      ("WITH unused AS (SELECT 1 AS id |> RESULT forbidden) SELECT 2 AS id", 34),
      (
        "CREATE TABLE output AS (SELECT 1 AS id |> RESULT forbidden) |> WHERE id > 0",
        42,
      ),
      ("CREATE TABLE output AS ((SELECT 1 AS id |> RESULT forbidden))", 43),
      ("SELECT 1 AS id |> UNION ALL (SELECT 2 AS id |> RESULT forbidden)", 47),
    ] {
    match parse_query(text, query_limits(), source_path="placement.sql") {
      Err({ issue: Syntax(message), span: Some(span), }) => {
        assert_eq(message, "RESULT is not allowed in a producer body")
        assert_eq(span.source_path, "placement.sql")
        assert_eq(span.start_byte, offset)
      }
      _ => fail(text)
    }
  }
}

///|
test "Compute accepts INFER but never a nested terminal write" {
  let query = parse_query(
    "CREATE TABLE output AS (FROM tickets |> INFER constant ITEM KEY (id) INPUT () AS assessment |> RESULT inferred)",
    query_limits(),
  ).unwrap()
  assert_true(operation_at(query, 0) is Some(Infer(_)))
  assert_true(operation_at(query, 1) is Some(RetainResult(_)))
  for
    text in [
      "CREATE TABLE output AS SELECT 1 AS id |> CREATE TABLE other", "CREATE TABLE output AS (SELECT 1 AS id |> EFFECT save CREATE TABLE other)",
    ] {
    match parse_query(text, query_limits()) {
      Err({ issue: Syntax(message), .. }) =>
        assert_true(
          message == "Table write is not allowed in a declaration body" ||
          message == "EFFECT is not allowed in a declaration body",
        )
      _ => fail(text)
    }
  }
}

///|
test "Pipe set retains Statement INFER on its left and Pure on its right" {
  let query = parse_query(
    "FROM tickets |> INFER constant ITEM KEY (id) INPUT () AS assessment |> UNION ALL (SELECT NULL AS assessment)",
    query_limits(),
  ).unwrap()
  assert_true(operation_at(query, 0) is Some(Infer(_)))
  assert_eq(set_part_count(query), 1)
  match
    parse_query(
      "SELECT NULL AS assessment |> UNION ALL (FROM tickets |> INFER constant ITEM KEY (id) INPUT () AS assessment)",
      query_limits(),
    ) {
    Err({ issue: Syntax(message), .. }) =>
      assert_eq(message, "INFER is not allowed in a CTE body")
    _ => fail("the right set operand retains Pure placement")
  }
}
