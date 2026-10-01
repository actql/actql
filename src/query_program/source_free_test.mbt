///|
test "source-free SELECT lowers to an independently authored ordinary Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":"hello"}}},{"select":[{"id":"aql_query_expr_0"},{"label":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","label"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT 1 AS id, 'hello' AS label", "SELECT 1 AS id, \"hello\" AS label", "SELECT 1 AS id, \"\\x68ello\" AS label",
      "SELECT 1 AS id, '\\150ello' AS label",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    for captured_stage in [None, Some("capture")] {
      let context = { ..fixture_context(), captured_stage, inputs: [], }
      let program = compile(query, context, construction_limits()).unwrap()
      assert_eq(semantic(program), semantic(expected))
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) =>
          fail("source-free SELECT must not request an Artifact")
        Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      }
    }
  }
}

///|
test "quoted values preserve exact text in an independent checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"literal":"\r"},"aql_query_expr_1":{"literal":"\n"},"aql_query_expr_2":{"literal":"\r\n"},"aql_query_expr_3":{"literal":"é"},"aql_query_expr_4":{"literal":"e\u0301"},"aql_query_expr_5":{"literal":"\\n"}}},{"select":[{"cr":"aql_query_expr_0"},{"lf":"aql_query_expr_1"},{"crlf":"aql_query_expr_2"},{"composed":"aql_query_expr_3"},{"decomposed":"aql_query_expr_4"},{"slash_n":"aql_query_expr_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["cr","lf","crlf","composed","decomposed","slash_n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT '\\r' AS cr, '\\n' AS lf, '\\r\\n' AS crlf, 'é' AS composed, 'e\\u0301' AS decomposed, '\\\\n' AS slash_n",
      "SELECT \"\\r\" AS cr, \"\\n\" AS lf, \"\\r\\n\" AS crlf, \"é\" AS composed, \"e\\u0301\" AS decomposed, \"\\\\n\" AS slash_n",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("literal-only query must not acquire inputs")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "source-free SELECT uses common scopes in Pipe, CTE and sets" {
  for
    source in [
      "SELECT 2 AS x |> WHERE x > 0 |> SELECT x |> ORDER BY x + 1", "SELECT 1 AS x WHERE FALSE",
      "WITH seed AS (SELECT 2 AS x) SELECT x FROM seed ORDER BY x", "WITH seed AS (SELECT 2 AS x) FROM seed |> SELECT x |> WHERE x > 0",
      "SELECT 2 AS x UNION ALL SELECT 1 AS x ORDER BY x", "SELECT DISTINCT 1 AS x ORDER BY x",
      "WITH seed AS (SELECT 2 AS x |> WHERE x > 0 |> SELECT x) SELECT x FROM seed",
      "SELECT COUNT(*) AS n", "SELECT x FROM (SELECT 2 AS x) AS seed ORDER BY x",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], captured_stage: Some("capture"), },
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail(source)
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "source-free witness and SELECT siblings are not visible names" {
  for
    source in [
      "SELECT *", "SELECT aql_source_free_unit AS x", "SELECT aql_source_free.aql_source_free_unit AS x",
      "SELECT 1 AS x, x AS y", "SELECT 1 AS x WHERE x > 0", "SELECT 1 AS x ORDER BY missing",
      "SELECT 1 AS x, 2 AS X",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(_),
      msg=source,
    )
  }
}

///|
test "source-free witness construction is bounded by normal builder limits" {
  let query = @query.parse_query("SELECT 1 AS x", syntax_limits()).unwrap()
  let limits = construction_limits()
  assert_true(
    compile(query, fixture_context(), {
      ..limits,
      source: { ..limits.source, max_output_bytes: 1, },
    })
    is Err(Construction(_)),
  )
}
