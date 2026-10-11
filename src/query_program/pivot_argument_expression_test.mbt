///|
test "PIVOT aggregate expression preserves referenced-column consumption" {
  let source = "(SELECT 1 AS product,1 AS amount,'A' AS axis UNION ALL SELECT 1,2,'A') |> PIVOT(SUM(amount + 1) FOR axis IN('A')) |> ORDER BY product"
  let query = match @query.parse_query(source, syntax_limits()) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) =>
      fail("PIVOT argument expression syntax refusal: " + reason)
    Err(_) => fail("unexpected PIVOT expression syntax failure")
  }
  let program = compile(
    query,
    { ..values_context(), inputs: [], },
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
    NeedsInputs(_) => fail("closed aggregate expression")
  }
}

///|
test "PIVOT aggregate expression has an independent existing Program control" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pivot_argument_expression\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"product\":{\"type\":\"number\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":false},\"axis\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"product\":1,\"amount\":1,\"axis\":\"A\"},{\"product\":1,\"amount\":2,\"axis\":\"A\"}]},\"as\":\"rows\"},{\"from\":\"rows\",\"derive\":{\"adjusted\":{\"add\":[{\"field\":\"amount\"},{\"literal\":1}]}}},{\"pivot\":{\"index\":[\"product\"],\"column\":\"axis\",\"value\":\"adjusted\",\"values\":[\"A\"],\"aggregate\":\"sum\"}},{\"sort\":[{\"field\":\"product\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"product\",\"A\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"product\",\"A\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
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
    NeedsInputs(_) => fail("closed independent aggregate expression")
  }
}

///|
test "PIVOT aggregate expression keeps multiple consumed input columns" {
  let source = "(SELECT 1 AS product,1 AS amount,2 AS bonus,'A' AS axis UNION ALL SELECT 1,2,3,'A') |> PIVOT(SUM(amount + bonus) FOR axis IN('A')) |> ORDER BY product"
  let query = match @query.parse_query(source, syntax_limits()) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) => fail(source + ": " + reason)
    Err(_) => fail("unexpected expression syntax failure")
  }
  let program = match
    compile(query, { ..values_context(), inputs: [], }, construction_limits()) {
    Ok(program) => program
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedGrouping) => fail(source + ": UnsupportedGrouping")
    Err(_) => fail(source + ": unexpected lowering failure")
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
    NeedsInputs(_) => fail("closed PIVOT expression scope")
  }
}

///|
test "PIVOT aggregate expression keeps literal without consumed columns" {
  let source = "(SELECT 1 AS product,1 AS amount,'A' AS axis UNION ALL SELECT 1,2,'A') |> PIVOT(SUM(1) FOR axis IN('A')) |> ORDER BY product, amount"
  let query = match @query.parse_query(source, syntax_limits()) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) => fail(source + ": " + reason)
    Err(_) => fail("unexpected expression syntax failure")
  }
  let program = match
    compile(query, { ..values_context(), inputs: [], }, construction_limits()) {
    Ok(program) => program
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedGrouping) => fail(source + ": UnsupportedGrouping")
    Err(_) => fail(source + ": unexpected lowering failure")
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
    NeedsInputs(_) => fail("closed PIVOT expression scope")
  }
}

///|
test "PIVOT aggregate expression keeps nullable property arithmetic" {
  let source = "FROM objects |> SELECT id AS product, payload, 'A' AS axis |> PIVOT(SUM(payload.score + 1) FOR axis IN('A')) |> ORDER BY product"
  let query = match @query.parse_query(source, syntax_limits()) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) => fail(source + ": " + reason)
    Err(_) => fail("unexpected expression syntax failure")
  }
  let program = match
    compile(query, aggregate_property_order_context(), construction_limits()) {
    Ok(program) => program
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedGrouping) => fail(source + ": UnsupportedGrouping")
    Err(_) => fail(source + ": unexpected lowering failure")
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
    NeedsInputs(_) => fail("closed PIVOT expression scope")
  }
}

///|
test "PIVOT aggregate expression keeps nullable property alone" {
  let source = "FROM objects |> SELECT id AS product, payload, 'A' AS axis |> PIVOT(SUM(payload.score) FOR axis IN('A')) |> ORDER BY product"
  let query = match @query.parse_query(source, syntax_limits()) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) => fail(source + ": " + reason)
    Err(_) => fail("unexpected expression syntax failure")
  }
  let program = match
    compile(query, aggregate_property_order_context(), construction_limits()) {
    Ok(program) => program
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedGrouping) => fail(source + ": UnsupportedGrouping")
    Err(_) => fail(source + ": unexpected lowering failure")
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
    NeedsInputs(_) => fail("closed PIVOT expression scope")
  }
}

///|
test "PIVOT aggregate expression keeps immutable range consumption" {
  let source = "(SELECT 1 AS product,1 AS amount,'A' AS axis UNION ALL SELECT 1,2,'A') |> AS old |> SET amount = 7 |> PIVOT(SUM(old.amount + 1) FOR axis IN('A')) |> ORDER BY product, amount"
  let query = match @query.parse_query(source, syntax_limits()) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) => fail(source + ": " + reason)
    Err(_) => fail("unexpected expression syntax failure")
  }
  let program = match
    compile(query, { ..values_context(), inputs: [], }, construction_limits()) {
    Ok(program) => program
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedGrouping) => fail(source + ": UnsupportedGrouping")
    Err(_) => fail(source + ": unexpected lowering failure")
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
    NeedsInputs(_) => fail("closed PIVOT expression scope")
  }
}

///|
test "PIVOT expression retains the existing parameter declaration path" {
  let declarations = @parameters.read_declarations(
    Some(
      unnest_value_cursor(
        "{\"offset\":{\"type\":\"number\",\"nullable\":false}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let program = compile(
    @query.parse_query(
      "SELECT 1 AS amount,'A' AS axis |> PIVOT(SUM(amount + @offset) FOR axis IN('A'))",
      syntax_limits(),
    ).unwrap(),
    {
      ..values_context(),
      inputs: [],
      parameter_declarations: Some(declarations),
    },
    construction_limits(),
  ).unwrap()
  assert_true(semantic(program).contains("\"$param\":\"offset\""))
}

///|
test "PIVOT scalar expression matches a complete independently authored Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","derive":{"aql_pivot_argument_10":{"add":[{"field":"amount"},{"literal":1}]}}},{"pivot":{"index":["id","customer_id"],"column":"status","values":["open","closed"],"value":"aql_pivot_argument_10","aggregate":"sum"}},{"select":["id","customer_id",{"opened":"open"},"closed"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","customer_id","opened","closed"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "FROM orders |> PIVOT(SUM(amount + 1) FOR status IN ('open' AS opened,'closed'))",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed independent full Program")
  }
}
