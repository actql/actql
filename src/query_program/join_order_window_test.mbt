///|
fn join_order_window_control() -> @program.Program {
  // Independent ordinary JOIN/window/sort/projection, before any source is
  // lowered. Ordering by unselected y must still see the joined input value.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.join_order_window","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"},{"from":"t","join":{"with":"r","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"id":"left.x","y":"left.y"}},"as":"joined"},{"from":"joined","analytic":{"partition_by":[],"order_by":[{"field":"y","dir":"asc","nulls":"first"}],"functions":{"position":{"fn":"row_number"}}}},{"sort":[{"field":"position","dir":"asc","nulls":"first"}]},{"select":["id"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn check_join_order_window(text : String) -> Unit raise {
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  for
    program in [
      compile_query_script(
        @query.single_query_script(query),
        join_order_context(),
        construction_limits(),
      ).unwrap(),
      compile(query, join_order_context(), construction_limits()).unwrap(),
    ] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("both JOIN inputs and analytic fields are supplied by Values")
    }
    let body = semantic(program)
    assert_true(body.contains("\"max_output_rows\":10"))
    assert_true(body.contains("\"fn\":\"row_number\""))
    assert_true(body.contains("\"fields\":[\"id\"]"))
  }
}

///|
test "JOIN ORDER-only analytic has an independently checked Program" {
  match
    @check.check_parsed(
      join_order_window_control(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent common analytic control is closed")
  }
}

///|
test "JOIN SQL ORDER-only window sees an unselected input field" {
  check_join_order_window(
    "SELECT t.x AS id FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY ROW_NUMBER() OVER (ORDER BY t.y)",
  )
}

///|
test "JOIN SQL ORDER-only window resolves an evaluated SELECT alias" {
  check_join_order_window(
    "SELECT -t.x AS id FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY ROW_NUMBER() OVER (ORDER BY id)",
  )
}

///|
test "JOIN SQL ORDER-only window retains a qualified input under alias collision" {
  check_join_order_window(
    "SELECT -t.x AS id FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY ROW_NUMBER() OVER (ORDER BY t.x)",
  )
}

///|
test "JOIN projected Pipe ORDER-only window consumes current output" {
  check_join_order_window(
    "FROM t |> JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 |> SELECT -t.x AS id |> ORDER BY ROW_NUMBER() OVER (ORDER BY id)",
  )
}

///|
test "JOIN Pipe analytic ORDER cannot recover a projected-away input range" {
  let query = @query.parse_query(
    "FROM t |> JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 |> SELECT t.x AS id |> ORDER BY ROW_NUMBER() OVER (ORDER BY t.y)",
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
