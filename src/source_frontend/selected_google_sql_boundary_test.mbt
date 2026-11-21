///|
test "unselected GoogleSQL scalar families retain a named checked lowering refusal" {
  let context = bind_query_context([], "fixture.environment").unwrap()
  for
    expression in [
      "REGEXP_CONTAINS('abc', 'a')", "REGEXP_EXTRACT('abc', 'a')", "REGEXP_REPLACE('abc', 'a', 'b')",
      "ARRAY_LENGTH([1, 2])", "UNIX_SECONDS(1)", "SHA256('a')",
    ] {
    assert_true(
      lower("SELECT " + expression + " AS result", Sql, Some(context))
      is Err(QueryLowering(Expression({ issue: UnsupportedFunction, .. }))),
      msg=expression,
    )
  }
}

///|
test "current date retains the SQL query-time boundary without selecting timezone arguments" {
  let context = bind_query_context([], "fixture.environment").unwrap()
  for source in ["SELECT CURRENT_DATE AS x", "SELECT CURRENT_DATE() AS x"] {
    assert_true(lower(source, Sql, Some(context)) is Ok(_), msg=source)
  }
  assert_true(
    lower("SELECT CURRENT_DATE('UTC') AS x", Sql, Some(context))
    is Err(QueryLowering(Expression({ issue: InvalidArguments, .. }))),
  )
}

///|
test "aggregate window defaults keep missing frame and order as authored" {
  for expression in ["SUM(id) OVER ()", "COUNT(*) OVER (ORDER BY id)"] {
    let lowered = lower(
      "SELECT " + expression + " AS result FROM records",
      Sql,
      Some(test_context()),
    ).unwrap()
    assert_true(lowered.document.contains("\"analytic\":"), msg=expression)
    assert_true(!lowered.document.contains("\"frame\":"), msg=expression)
  }
}

///|
test "original unkeyed ARRAY_AGG queries preserve separate syntax and candidate key refusals" {
  let context = bind_query_context([], "fixture.environment").unwrap()
  let fixture = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) "
  assert_true(
    lower(fixture + "SELECT ARRAY_AGG(n) AS x FROM t", Sql, Some(context))
    is Err(QuerySyntax({ issue: AggregateOrderRequired, .. })),
  )
  assert_true(
    lower(
      fixture + "SELECT ARRAY_AGG(n ORDER BY n) AS x FROM t",
      Sql,
      Some(context),
    )
    is Err(
      QueryLowering(
        BindingPreparation(
          LocalProgram(Order(_, PipelineOrder({ kind: UnresolvedOrder, .. })))
        )
      )
    ),
  )
}
