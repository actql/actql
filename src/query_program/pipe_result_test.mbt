///|
test "the existing Program retains a complete prefix Result before filtering" {
  // Independently authored from the adopted RESULT obligations: original
  // retains the NULL row and duplicate; active has only the non-NULL row.
  // A Result is not a View that can be replaced by the downstream filter.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_results","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"id":2,"note":null},{"id":1,"note":"x"},{"id":2,"note":null}]},"as":"original_rows"},{"from":"original_rows","filter":{"not":{"is_null":{"field":"note"}}},"as":"active_rows"}],"results":{"original":{"from":"original_rows","fields":["id","note"]},"active":{"from":"active_rows","fields":["id","note"]}}}],"results":{"original":{"from":{"stage":"main","result":"original"}},"active":{"from":{"stage":"main","result":"active"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("the prefix and final Results use existing Program owners")
  }
}

///|
test "RESULT lowers the full prefix and terminal name through existing Program Results" {
  let program = compile(
    @query.parse_query(
      "FROM pair |> RESULT original |> WHERE x > 0 |> RESULT active",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  // This Program is authored directly from the adopted tap semantics. The
  // terminal name reuses the final stage Result instead of adding an answer.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","select":["x","y"],"as":"aql_result_checkpoint_0"},{"filter":{"gt":[{"field":"x"},{"literal":0}]}},{"select":["x","y"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]},"aql_retained_result_0":{"from":"aql_result_checkpoint_0","fields":["x","y"]}}}],"results":{"original":{"from":{"stage":"main","result":"aql_retained_result_0"}},"active":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("RESULT must use the ordinary checker")
  }
}

///|
test "RESULT before aggregation preserves an independently authored prefix Program" {
  let program = compile(
    @query.parse_query(
      "FROM pair |> RESULT original |> AGGREGATE COUNT(*) AS n |> RESULT summary",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  // The prefix has its original columns, while COUNT has a single new
  // non-null output. The expected Program does not call the query lowerer.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","select":["x","y"],"as":"aql_result_checkpoint_0"},{"group":{"by":[],"aggregates":{"n":{"fn":"count"}}}},{"select":["n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]},"aql_retained_result_0":{"from":"aql_result_checkpoint_0","fields":["x","y"]}}}],"results":{"original":{"from":{"stage":"main","result":"aql_retained_result_0"}},"summary":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("retained prefix and aggregate use the ordinary checker")
  }
}

///|
test "top level RESULT consumes evaluated CTE and JOIN output through the shared lowerer" {
  for
    (text, context) in [
      (
        "WITH chosen AS (SELECT x, y FROM pair) FROM chosen |> RESULT original |> WHERE x > 0 |> SELECT y |> RESULT active",
        pair_context(),
      ),
      (
        "SELECT t.x AS y FROM t JOIN r ON t.x = r.k |> RESULT original |> WHERE y > 0 |> SELECT y |> ORDER BY y + 1 |> RESULT active",
        join_order_context(),
      ),
      (
        "WITH lhs AS (SELECT x, y FROM t), rhs AS (SELECT k FROM r) SELECT lhs.x AS y FROM lhs JOIN rhs ON lhs.x = rhs.k |> RESULT original |> WHERE y > 0 |> SELECT y |> ORDER BY y + 1 |> RESULT active",
        join_order_context(),
      ),
      (
        "SELECT a AS id FROM left_rows UNION ALL SELECT c AS id FROM right_rows |> RESULT original |> WHERE id > 0 |> RESULT active",
        set_context(),
      ),
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      _ => fail(text)
    }
    assert_true(
      semantic(program).contains(
        "\"original\":{\"from\":{\"result\":\"aql_retained_result_0\",\"stage\":\"main\"}}",
      ),
    )
    assert_false(semantic(program).contains("\"answer\":{\"from\""))
  }
}

///|
test "Graph RESULT requires an explicit public Relation projection" {
  let program = compile(
    @query.parse_query(
      "FROM GRAPH g |> MATCH WALK (a)-[]->(b) |> SELECT a.id AS src, b.id AS dst |> RESULT paths |> WHERE src > 0 |> RESULT active",
      syntax_limits(),
    ).unwrap(),
    diamond_graph_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(program).contains("\"fields\":[\"src\",\"dst\"]"))
  assert_true(
    compile(
      @query.parse_query(
        "FROM GRAPH g |> MATCH WALK (a)-[]->(b) |> RESULT paths |> SELECT a.id AS id",
        syntax_limits(),
      ).unwrap(),
      diamond_graph_context(),
      construction_limits(),
    )
    is Err(UnsupportedResult),
  )
}

///|
test "RESULT inside a CTE or derived query cannot publish a statement Result" {
  for
    text in [
      "WITH chosen AS (FROM pair |> RESULT saved) SELECT x FROM chosen", "SELECT x FROM (FROM pair |> RESULT saved) AS chosen",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(UnsupportedResult),
      msg=text,
    )
  }
}

///|
test "a nonterminal RESULT preserves the usual primary export" {
  let program = compile(
    @query.parse_query(
      "FROM pair |> RESULT original |> LIMIT 1",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(program).contains(
      "\"results\":{\"answer\":{\"from\":{\"result\":\"rows\",\"stage\":\"main\"}},\"original\":{\"from\":{\"result\":\"aql_retained_result_0\",\"stage\":\"main\"}}}",
    ),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("RESULT must use the ordinary checker")
  }
}

///|
test "RESULT exposes current columns without deleting immutable range snapshots" {
  for
    text in [
      "FROM pair AS old |> SET x = y |> RESULT saved |> SELECT old.x AS original, x AS current |> RESULT final",
      "FROM pair AS old |> DROP x |> RESULT saved |> SELECT old.x AS original, y |> RESULT final",
      "FROM pair AS old |> RENAME x AS z |> RESULT saved |> SELECT old.x AS original, z |> RESULT final",
      "FROM pair |> SELECT x |> RESULT saved |> WHERE x > 0 |> SELECT x |> ORDER BY x + 1 |> RESULT final",
      "FROM pair |> RESULT saved |> AS rebound", "FROM pair AS old |> SET x = y |> RESULT saved |> AS rebound",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      _ => fail(text)
    }
  }
}

///|
test "duplicate Result names and primary collisions are rejected" {
  for
    text in [
      "FROM pair |> RESULT saved |> RESULT saved", "FROM pair |> RESULT Saved |> RESULT `SAVED`",
      "FROM pair |> RESULT answer |> LIMIT 1",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(DuplicateOutput),
      msg=text,
    )
  }
}
