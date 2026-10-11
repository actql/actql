///|
test "anonymous JOIN positional operand retains its existing named control" {
  let named = "SELECT 0 AS n UNION ALL SELECT l.x + r.k AS n FROM t AS l JOIN r ON l.x = r.k ORDER BY n"
  let anonymous = "SELECT 0 AS n UNION ALL SELECT l.x + r.k FROM t AS l JOIN r ON l.x = r.k ORDER BY n"
  for source in [named, anonymous] {
    let program = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
      Err(UnsupportedJoin) => fail(source + ": UnsupportedJoin")
      Err(_) => fail(source + ": another rejection")
    }
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("JOIN operand retains existing Values inputs")
    }
  }
}

///|
test "positional JOIN operands preserve WITH bindings and multi-JOIN ceilings" {
  for
    (source, joins) in [
      (
        "SELECT 0 AS n UNION ALL SELECT l.x + s.k FROM t AS l JOIN r ON l.x = r.k JOIN r AS s ON r.k = s.k ORDER BY n",
        2,
      ),
      (
        "WITH joined AS (SELECT t.x AS x, r.k AS k FROM t JOIN r ON t.x = r.k) SELECT 0 AS n UNION ALL SELECT j.x + r.k FROM joined AS j JOIN r ON j.k = r.k ORDER BY n",
        2,
      ),
      (
        "WITH combined AS (SELECT 0 AS n UNION ALL SELECT l.x + r.k FROM t AS l JOIN r ON l.x = r.k) FROM combined |> ORDER BY n",
        1,
      ),
    ] {
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
      { ..construction_limits(), max_join_output_rows: 7L, },
    ).unwrap()
    assert_eq(
      semantic(program).split("\"max_output_rows\":7").length(),
      joins + 1,
    )
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("positional JOIN inputs remain existing Values producers")
    }
  }
}

///|
test "anonymous JOIN outputs do not become BY NAME or final range names" {
  let by_name = "SELECT 0 AS n UNION ALL BY NAME SELECT l.x + r.k FROM t AS l JOIN r ON l.x = r.k"
  assert_true(
    compile(
      @query.parse_query(by_name, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedJoin),
  )
  for field in ["l.x", "r.k", "aql_chain_column_2"] {
    let source = "SELECT 0 AS n UNION ALL SELECT l.x + r.k FROM t AS l JOIN r ON l.x = r.k ORDER BY " +
      field
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=field,
    )
  }
}

///|
test "positional JOIN comparison Program is independent and checked" {
  // Ordinary Values/JOIN/derive/append/sort owners express the expected n values
  // 0, 2, 4. This does not copy or patch the frontend's physical slot layout.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_join","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"left"},{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"right"},{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":0}]},"as":"zero"},{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":7,"select":{"a":"left.x","b":"right.k"}}},{"derive":{"n":{"add":[{"field":"a"},{"field":"b"}]}}},{"select":["n"],"as":"sums"},{"from":"zero","append":{"with":"sums"}},{"sort":[{"field":"n","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("independent JOIN/add/append/sort comparison is closed")
  }
}
