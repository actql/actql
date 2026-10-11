///|
test "independent joined row objects use the existing checked object Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.join_row_ranges","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"left"},{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2}]},"as":"right"},{"from":"left","cross_join":{"with":"right","max_output_rows":10,"select":{"left_id":"left.id","right_id":"right.id"}},"as":"joined"},{"from":"joined","derive":{"left_row":{"object":{"id":{"field":"left_id"}}},"right_row":{"object":{"id":{"field":"right_id"}}}}},{"select":["left_row","right_row"],"as":"out"}],"results":{"rows":{"from":"out","fields":["left_row","right_row"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed joined object control")
  }
}

///|
test "joined ranges are row expressions in the public query script" {
  let query = @query.parse_query_script(
    "SELECT l AS left_row,r AS right_row FROM (SELECT 1 AS id) l CROSS JOIN (SELECT 2 AS id) r MAX_OUTPUT_ROWS 10",
    syntax_limits(),
  ).unwrap()
  let p = match
    compile_query_script(
      query,
      { ..values_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(p) => p
    Err(UnknownColumn) => fail("joined row: UnknownColumn")
    Err(Expression(issue)) =>
      fail("joined row expression: " + @debug.to_string(issue.issue))
    Err(UnsupportedProjection) => fail("joined row: UnsupportedProjection")
    Err(UnsupportedCte) => fail("joined row: UnsupportedCte")
    Err(_) => fail("joined row: other lowering refusal")
  }
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed joined source")
  }
}

///|
test "joined range outranks its same-named input column" {
  let source = "SELECT l AS row FROM (SELECT 7 AS l,9 AS id) l CROSS JOIN (SELECT 2 AS id) r MAX_OUTPUT_ROWS 10"
  let p = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..values_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(p).contains("\"l\":{\"field\":") &&
    semantic(p).contains("\"id\":{\"field\":"),
    msg="the selected range is the complete row, not the scalar l column",
  )
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed joined range-shadow source")
  }
}

///|
test "joined row scopes preserve outer JOIN, USING and quoted receivers" {
  for
    source in [
      "SELECT l AS left_row,r AS right_row FROM (SELECT 1 AS id) l LEFT JOIN (SELECT 2 AS id) r ON l.id=r.id MAX_OUTPUT_ROWS 10 ORDER BY l.id",
      "SELECT l AS left_row,r AS right_row FROM (SELECT 1 AS id) l RIGHT JOIN (SELECT 2 AS id) r ON l.id=r.id MAX_OUTPUT_ROWS 10 ORDER BY r.id",
      "DATA lefts = FROM (SELECT 1 AS id) |> ASSERT UNIQUE BY (id); DATA rights = FROM (SELECT 2 AS id) |> ASSERT UNIQUE BY (id); SELECT l AS left_row,r AS right_row FROM lefts l FULL JOIN rights r USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id",
      "SELECT `ORDER` AS left_row,r AS right_row FROM (SELECT 1 AS id) `ORDER` CROSS JOIN (SELECT 2 AS id) r MAX_OUTPUT_ROWS 10",
      "WITH a AS (SELECT 1 AS id),b AS (SELECT 2 AS id) SELECT a AS left_row,b AS right_row FROM a CROSS JOIN b MAX_OUTPUT_ROWS 10",
    ] {
    let p = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    match @check.check_parsed(p, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail(source + ": closed joined row scope")
    }
  }
}

///|
test "bare row in a pre-JOIN WHERE keeps its original evaluation point" {
  let source = "FROM (SELECT 1 AS id UNION ALL SELECT 2) l |> WHERE COALESCE(l,NULL).id=1 |> CROSS JOIN (SELECT 3 AS id) r MAX_OUTPUT_ROWS 10 |> SELECT l AS left_row,r AS right_row"
  let p = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..values_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed pre-JOIN row WHERE")
  }
  let body = semantic(p)
  assert_true(body.contains("\"filter\":{\"eq\":"))
  assert_true(body.contains("\"literal\":1"))
}

///|
test "joined ORDER row alias prevents reuse of an input row expression" {
  let source = "SELECT COALESCE(l,NULL).amount AS original,r AS l,l.id AS id FROM (SELECT 1 AS id,20 AS amount) l JOIN (SELECT 1 AS id,10 AS amount) r ON l.id=r.id MAX_OUTPUT_ROWS 10 ORDER BY COALESCE(l,NULL).amount"
  let p = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..values_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed joined row alias ORDER")
  }
  assert_false(
    semantic(p).contains("\"sort\":[{\"dir\":\"asc\",\"field\":\"original\""),
    msg="ORDER receiver l means the output r row, not the selected input l row",
  )
}

///|
test "PIVOT row argument keeps range precedence over a same-named scalar column" {
  for
    source in [
      "FROM (SELECT 7 AS l,9 AS id,'A' AS axis) l |> PIVOT(COUNT(l) FOR axis IN('A')) |> SELECT *",
      "FROM (SELECT 7 AS l,9 AS id,'A' AS axis) l |> PIVOT(COUNT(COALESCE(l,NULL)) FOR axis IN('A')) |> SELECT *",
    ] {
    let p = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    let text = semantic(p)
    assert_true(text.contains("\"object\""))
    assert_true(text.contains("\"index\":[]"))
    match @check.check_parsed(p, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("closed PIVOT row source")
    }
  }
}
