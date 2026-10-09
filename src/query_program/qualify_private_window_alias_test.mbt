///|
fn checked_private_window_qualify(text : String, field : String) -> String raise {
  let program = match
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      select_window_private_context(field),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(Expression(diagnostic)) =>
      fail(text + ": " + @debug.to_string(diagnostic.issue))
    Err(_) => fail(text + ": unexpected lowering refusal")
  }
  match @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the checked input schema is closed")
  }
  semantic(program)
}

///|
test "QUALIFY materializes a SELECT window expression separately from a schema name" {
  for field in ["aql_select_window_0", "AQL_SELECT_WINDOW_0"] {
    let body = checked_private_window_qualify(
      "SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM records QUALIFY pos > 2 ORDER BY id DESC",
      field,
    )
    assert_true(body.contains("\"fields\":[\"id\",\"" + field + "\",\"pos\"]"))
    assert_eq(body.split("\"add\":").length() - 1, 1)
    assert_true(
      body.contains("\"add\":[{\"field\":\"aql_analytic_output_3\"},{\"literal\":1}]"),
      msg=body,
    )
  }
}

///|
test "QUALIFY demanded SELECT window expression also retains GROUP BY ALL keys" {
  let body = checked_private_window_qualify(
    "SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM records GROUP BY ALL QUALIFY pos > 2 ORDER BY id DESC",
    "aql_select_window_0",
  )
  assert_eq(body.split("\"add\":").length() - 1, 1)
  assert_true(
    body.contains("\"add\":[{\"field\":\"aql_analytic_output_3\"},{\"literal\":1}]"),
    msg=body,
  )
}

///|
test "QUALIFY private scope retains authored inputs and evaluated alias reuse" {
  for text in [
    "SELECT *, ROW_NUMBER() OVER w + 1 AS `pos` FROM records QUALIFY `pos` > 2 WINDOW w AS (ORDER BY id) ORDER BY id DESC",
    "SELECT *, ROW_NUMBER() OVER (ORDER BY records.id) + records.aql_select_window_0 AS pos FROM records QUALIFY pos > 50 ORDER BY id DESC",
  ] {
    let body = checked_private_window_qualify(text, "aql_select_window_0")
    assert_eq(body.split("\"add\":").length() - 1, 1)
    assert_true(body.contains("\"fields\":[\"id\",\"aql_select_window_0\",\"pos\"]"))
  }
}

///|
test "QUALIFY private-window output has an independent ordinary Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.qualify_private_window","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"aql_select_window_0":{"type":"number","nullable":false}},"rows":[{"id":2,"aql_select_window_0":10},{"id":1,"aql_select_window_0":90}]},"as":"records"},{"from":"records","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"rank_value":{"fn":"row_number"}}}},{"derive":{"pos":{"add":[{"field":"rank_value"},{"literal":1}]}}},{"filter":{"gt":[{"field":"pos"},{"literal":2}]}},{"select":["id","aql_select_window_0","pos"]},{"sort":[{"field":"id","dir":"desc","nulls":"last"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","aql_select_window_0","pos"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independently authored ordinary Program is closed")
  }
}

///|
test "SELECT window-valued alias remains invalid as another window input" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM records ORDER BY ROW_NUMBER() OVER (ORDER BY pos)",
        syntax_limits(),
      ).unwrap(),
      select_window_private_context("aql_select_window_0"),
      construction_limits(),
    )
    is Err(UnsupportedAnalytic),
  )
}
