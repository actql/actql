///|
test "positional Pipe ORDER window retains evaluated anonymous columns" {
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> ORDER BY ROW_NUMBER() OVER (ORDER BY kept DESC) |> LIMIT 1) ORDER BY a, b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("ORDER window lost positional projection: UnsupportedProjection")
    Err(_) => fail("unexpected ORDER window source refusal")
  }
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed positional ORDER control")
  }
}

///|
test "positional ORDER window has an independently checked JSON control" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_order_window\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1},{\"x\":2}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"x\"}}}},{\"select\":[{\"kept\":\"x\"},\"neg\"]},{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"field\":\"kept\",\"dir\":\"desc\",\"nulls\":\"last\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}},{\"sort\":[{\"field\":\"position\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"take\":{\"count\":1,\"offset\":0}},{\"select\":[{\"a\":\"kept\"},{\"b\":\"neg\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed independent ORDER control")
  }
}

///|
test "positional ORDER windows preserve current columns and immutable range receivers" {
  for
    source in [
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS r |> SET kept=-kept |> ORDER BY ROW_NUMBER() OVER (ORDER BY r.kept DESC) |> LIMIT 1) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> ORDER BY ROW_NUMBER() OVER (ORDER BY kept)+1 DESC |> LIMIT 1 OFFSET 1) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,x+10 AS kept |> ORDER BY ROW_NUMBER() OVER (ORDER BY kept DESC) |> LIMIT 1) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS aql_order_window_0,-x |> ORDER BY ROW_NUMBER() OVER (ORDER BY aql_order_window_0 DESC) |> LIMIT 1) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b WHERE FALSE UNION ALL (FROM t |> SELECT x AS kept,CAST(NULL AS FLOAT64) |> ORDER BY ROW_NUMBER() OVER (ORDER BY kept DESC) |> LIMIT 1) ORDER BY a,b NULLS LAST",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed positional window boundary")
    }
  }
}

///|
test "positional ORDER window cannot read private anonymous or ambiguous values" {
  let head = "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> ORDER BY ROW_NUMBER() OVER (ORDER BY "
  assert_true(
    compile(
      @query.parse_query(
        head + "aql_set_anonymous_4) |> LIMIT 1) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-x AS `V` |> ORDER BY ROW_NUMBER() OVER (ORDER BY v) |> LIMIT 1) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
  for
    (source, expression_failure) in [
      (head + "x) |> LIMIT 1) ORDER BY a,b", false),
      (
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS before |> AS current |> ORDER BY ROW_NUMBER() OVER (ORDER BY before.kept) |> LIMIT 1) ORDER BY a,b",
        false,
      ),
      (
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> ORDER BY ROW_NUMBER() OVER (ORDER BY kept) |> WHERE aql_order_window_0>0) ORDER BY a,b",
        true,
      ),
      (
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS r |> ORDER BY ROW_NUMBER() OVER (ORDER BY r.aql_set_anonymous_4) |> LIMIT 1) ORDER BY a,b",
        false,
      ),
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    if expression_failure {
      assert_true(
        actual is Err(Expression({ issue: @expression.UnknownReference, .. })),
        msg=source,
      )
    } else {
      // A missing plain OVER key uses the existing direct-key refusal.
      assert_true(actual is Err(UnknownColumn), msg=source)
    }
  }
}
