///|
fn join_select_window_control() -> @program.Program {
  // Handwritten common JOIN/analytic/projection/sort control. The joined
  // y=10 row receives pos=1, while y=20 receives pos=2.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.join_select_window","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"},{"from":"t","join":{"with":"r","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"x":"left.x","y":"left.y"}},"as":"joined"},{"from":"joined","analytic":{"partition_by":[],"order_by":[{"field":"y","dir":"asc","nulls":"first"}],"functions":{"pos":{"fn":"row_number"}}}},{"select":["x","pos"]},{"sort":[{"field":"pos","dir":"asc","nulls":"first"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["x","pos"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "JOIN SELECT window independent common Program passes the checker" {
  match
    @check.check_parsed(
      join_select_window_control(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent JOIN SELECT window control is closed")
  }
}

///|
test "JOIN SELECT window reaches the ordinary checker without QUALIFY" {
  let source = "SELECT l.x AS x, ROW_NUMBER() OVER (ORDER BY l.y) AS pos FROM t AS l JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 ORDER BY pos"
  let query = @query.parse_query(source, syntax_limits()).unwrap()
  let program = match
    compile(query, join_order_context(), construction_limits()) {
    Ok(program) => program
    Err(UnsupportedJoin) => fail("JOIN SELECT window: UnsupportedJoin")
    Err(_) => fail("JOIN SELECT window: another lowering issue")
  }
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the JOIN SELECT window fixture is closed")
  }
}

///|
test "JOIN Pipe SELECT window retains the current joined row" {
  let source = "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.x AS x, ROW_NUMBER() OVER (ORDER BY l.y) AS pos |> ORDER BY pos"
  let query = @query.parse_query(source, syntax_limits()).unwrap()
  let program = match
    compile_query_script(
      @query.single_query_script(query),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedJoin) => fail("JOIN Pipe SELECT window: UnsupportedJoin")
    Err(UnsupportedAnalytic) =>
      fail("JOIN Pipe SELECT window: UnsupportedAnalytic")
    Err(UnsupportedProjection) =>
      fail("JOIN Pipe SELECT window: UnsupportedProjection")
    Err(UnknownColumn) => fail("JOIN Pipe SELECT window: UnknownColumn")
    Err(Expression(diagnostic)) =>
      fail("JOIN Pipe SELECT window: " + @debug.to_string(diagnostic.issue))
    Err(_) => fail("JOIN Pipe SELECT window: another lowering issue")
  }
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the JOIN Pipe SELECT window fixture is closed")
  }
}

///|
fn check_join_select_window(source : String) -> Unit raise {
  let query = @query.parse_query(source, syntax_limits()).unwrap()
  for
    program in [
      compile(query, join_order_context(), construction_limits()).unwrap(),
      compile_query_script(
        @query.single_query_script(query),
        join_order_context(),
        construction_limits(),
      ).unwrap(),
    ] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("JOIN SELECT window has closed Values inputs")
    }
  }
}

///|
test "JOIN SELECT window matches independent complete lowering" {
  let expected = join_current_row_expected(
    "{\"from\":\"aql_chain_join_2\",\"analytic\":{\"partition_by\":[],\"order_by\":[{\"field\":\"aql_chain_column_3\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"functions\":{\"pos\":{\"fn\":\"row_number\"}}}},{\"sort\":[{\"field\":\"pos\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"x\":\"aql_chain_column_2\"},\"pos\"],\"as\":\"aql_chain_result_3\"}",
    "[\"x\",\"pos\"]",
  )
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent complete lowering is closed")
  }
  let query = @query.parse_query(
    "SELECT l.x AS x, ROW_NUMBER() OVER (ORDER BY l.y) AS pos FROM t AS l JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 ORDER BY pos",
    syntax_limits(),
  ).unwrap()
  assert_eq(
    semantic(
      compile(query, join_order_context(), construction_limits()).unwrap(),
    ),
    semantic(expected),
  )
}

///|
test "JOIN SELECT window retains filter expression and output slots" {
  for
    source in [
      "SELECT l.x AS x, ROW_NUMBER() OVER (ORDER BY l.y) + 1 AS pos FROM t AS l JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 WHERE l.x > 1 ORDER BY pos",
      "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> WHERE l.x > 1 |> SELECT l.x AS x, ROW_NUMBER() OVER (ORDER BY l.y) + 1 AS pos |> ORDER BY pos",
      "SELECT l.x AS x, ROW_NUMBER() OVER (ORDER BY l.y) AS pos FROM t AS l LEFT JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 ORDER BY pos",
    ] {
    check_join_select_window(source)
  }
}

///|
test "JOIN SELECT window cannot read sibling SELECT aliases" {
  let query = @query.parse_query(
    "SELECT l.y AS invented, ROW_NUMBER() OVER (ORDER BY invented) AS pos FROM t AS l JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 ORDER BY pos",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, join_order_context(), construction_limits())
    is Err(UnknownColumn),
  )
  assert_true(
    compile_query_script(
      @query.single_query_script(query),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

///|
test "JOIN Pipe SELECT window cannot restore a projected-away range" {
  let query = @query.parse_query(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.x AS x |> SELECT x, ROW_NUMBER() OVER (ORDER BY l.y) AS pos |> ORDER BY pos",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, join_order_context(), construction_limits())
    is Err(UnknownColumn),
  )
  assert_true(
    compile_query_script(
      @query.single_query_script(query),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}
