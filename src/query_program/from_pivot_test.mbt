///|
test "FROM PIVOT has an independent checked existing Program" {
  let expected = pipe_pivot_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed existing pivot control")
  }
}

///|
test "SELECT FROM PIVOT preserves its projected columns and ordering" {
  let query = match
    @query.parse_query(
      "SELECT id,customer_id,opened,closed FROM orders PIVOT(COUNT(amount) FOR status IN ('open' AS opened,'closed')) ORDER BY id",
      syntax_limits(),
    ) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) =>
      fail("FROM PIVOT syntax refusal: " + reason)
    Err(_) => fail("unexpected FROM PIVOT parse error")
  }
  let program = compile(query, values_context(), construction_limits()).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed FROM PIVOT")
  }
}

///|
test "FROM PIVOT matches independently authored producer stages" {
  let staged_control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"aql_cte_0","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","pivot":{"index":["id","customer_id"],"column":"status","values":["open","closed"],"value":"amount","aggregate":"count"}},{"select":["id","customer_id",{"opened":"open"},"closed"],"as":"aql_cte_final"}],"results":{"rows":{"from":"aql_cte_final","fields":["id","customer_id","opened","closed"]}}},{"id":"main","inputs":{"aql_query_source_0":{"result":{"stage":"aql_cte_0","result":"rows"}}},"steps":[{"from":"aql_query_source_0","select":["id","customer_id","opened","closed"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","customer_id","opened","closed"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(
      staged_control,
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
  // The same original postfix/projection/order bodies compose in one pipeline.
  // Naming the projected FROM producer does not require a Stage boundary.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","pivot":{"index":["id","customer_id"],"column":"status","values":["open","closed"],"value":"amount","aggregate":"count"}},{"select":["id","customer_id",{"opened":"open"},"closed"],"as":"aql_script_cte_1"},{"from":"aql_script_cte_1","select":["id","customer_id","opened","closed"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id","customer_id","opened","closed"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    source in [
      "SELECT id,customer_id,opened,closed FROM orders PIVOT(COUNT(amount) FOR status IN ('open' AS opened,'closed')) ORDER BY id",
      "SELECT id,customer_id,opened,closed FROM orders PIVOT(COUNT(amount) FOR status IN ((('open')) AS opened,('closed'))) ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("grouped FROM PIVOT must check as a closed Program")
    }
  }
}

///|
test "FROM PIVOT supports aliases derived tables Pipe heads and both JOIN sides" {
  for
    source in [
      "SELECT shaped.id,shaped.opened FROM orders AS original PIVOT(COUNT(original.amount) FOR original.status IN ('open' AS opened)) AS shaped WHERE shaped.opened > 0 ORDER BY shaped.id",
      "FROM orders PIVOT(COUNT(amount) FOR status IN ('open' AS opened)) AS shaped |> SELECT shaped.id,shaped.opened |> ORDER BY id",
      "SELECT * FROM (SELECT 1 AS amount,'A' AS axis) PIVOT(SUM(amount) FOR axis IN('A'))",
      "SELECT shaped.A FROM (SELECT 1 AS amount,'A' AS axis) before PIVOT(SUM(before.amount) FOR before.axis IN('A')) shaped",
      "WITH sales AS (SELECT 1 AS product,2 AS amount,'A' AS axis UNION ALL SELECT 1,3,'A'), products AS (SELECT 1 AS product,100 AS marker) SELECT p.product,p.marker,s.A FROM products p JOIN sales PIVOT(SUM(amount) FOR axis IN('A')) s ON p.product=s.product MAX_OUTPUT_ROWS 10 ORDER BY p.product",
      "WITH sales AS (SELECT 1 AS product,2 AS amount,'A' AS axis UNION ALL SELECT 1,3,'A'), products AS (SELECT 1 AS product,100 AS marker) SELECT s.product,p.marker,s.A FROM sales PIVOT(SUM(amount) FOR axis IN('A')) s JOIN products p ON p.product=s.product MAX_OUTPUT_ROWS 10 ORDER BY s.product",
    ] {
    let query = match @query.parse_query(source, syntax_limits()) {
      Ok(q) => q
      Err({ issue: @query.Syntax(reason), .. }) => fail(source + ": " + reason)
      Err(_) => fail("unexpected syntax error")
    }
    let actual = match compile(query, values_context(), construction_limits()) {
      Ok(p) => p
      Err(_) => fail(source + ": lowering refusal")
    }
    if source.contains("MAX_OUTPUT_ROWS 10") {
      assert_true(
        semantic(actual).contains("\"max_output_rows\":10"),
        msg=source,
      )
    }
    match
      @check.check_parsed(
        actual,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed FROM pivot scope")
    }
  }
}

///|
test "FROM PIVOT does not restore input ranges or consumed columns" {
  for
    source in [
      "SELECT old.id FROM orders old PIVOT(COUNT(old.amount) FOR old.status IN('open'))",
      "SELECT amount FROM orders PIVOT(COUNT(amount) FOR status IN('open'))", "SELECT current.amount FROM orders PIVOT(COUNT(amount) FOR status IN('open')) `current`",
    ] {
    let result = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    )
    assert_true(
      result is Err(UnknownColumn) ||
      result is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "FROM PIVOT qualifies a column shadowed by its CTE range" {
  let head = "WITH sales AS (SELECT 'kale' AS product,51 AS sales,'Q1' AS quarter UNION ALL SELECT 'kale',51,'Q1' UNION ALL SELECT 'kale',CAST(NULL AS FLOAT64),'Q2') SELECT product,second,first FROM sales PIVOT(COUNT("
  let tail = ") FOR quarter IN('Q2' AS second,'Q1' AS first)) ORDER BY product"
  for (argument, valid) in [("sales.sales", true), ("sales", false)] {
    let query = @query.parse_query(head + argument + tail, syntax_limits()).unwrap()
    match compile(query, values_context(), construction_limits()) {
      Err(_) => assert_false(valid)
      Ok(program) => {
        let checked = @check.check_parsed(
          program,
          check_environment(numeric=true),
          None,
          check_limits(),
        )
        if valid {
          match checked {
            Checked(_) => ()
            Rejected(issue) => raise @check.diagnostic_cause(issue)
            NeedsInputs(_) => fail("closed qualified CTE pivot")
          }
        } else {
          // A bare surviving range is the row object, not its same-named column.
          assert_true(checked is Rejected(_))
        }
      }
    }
  }
}
