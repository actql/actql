///|
test "derived SQL and Pipe sources have the same independent checked Program" {
  // The authored Stage Result input is the parsed derived producer, not a
  // repeated expansion of its Values acquisition or an independent evaluator.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.sql_set","stages":[{"id":"aql_cte_0","inputs":{},"steps":[{"values":{"schema":{"a":{"type":"number","nullable":true},"b":{"type":"string","nullable":false}},"rows":[{"a":1,"b":"x"},{"a":1,"b":"x"},{"a":2,"b":"y"},{"a":null,"b":"n"}]},"as":"left_rows"},{"from":"left_rows","filter":{"gt":[{"field":"a"},{"literal":0}]}},{"select":["a","b"],"as":"aql_cte_final"}],"results":{"rows":{"from":"aql_cte_final","fields":["a","b"]}}},{"id":"main","inputs":{"aql_query_source_0":{"result":{"stage":"aql_cte_0","result":"rows"}}},"steps":[{"from":"aql_query_source_0","select":["b","a"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["b","a"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT b, a FROM (SELECT a, b FROM left_rows WHERE a > 0) AS chosen", "SELECT b, a FROM (FROM left_rows |> WHERE a > 0 |> SELECT a, b) AS chosen",
      "FROM (FROM left_rows |> WHERE a > 0 |> SELECT a, b) AS chosen |> SELECT b, a",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      set_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("derived Values source is closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "derived Pipe projection exposes only its output scope" {
  for
    text in [
      "SELECT a FROM (SELECT a FROM left_rows |> WHERE a > 0) AS chosen", "SELECT chosen.a FROM (FROM left_rows |> SELECT a |> WHERE a > 0) AS chosen",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      set_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      _ => fail(text)
    }
  }
  for
    text in [
      "SELECT chosen.b FROM (FROM left_rows |> SELECT a) AS chosen", "SELECT left_rows.a FROM (FROM left_rows |> SELECT a) AS chosen",
      "SELECT chosen.a FROM (FROM left_rows AS old |> AS fresh |> SELECT old.a) AS chosen",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        set_context(),
        construction_limits(),
      )
      is Err(_),
      msg=text,
    )
  }
}
