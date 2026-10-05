///|
test "escaped output identifiers match an independent complete ordinary Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"space name":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["space name"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for source in ["SELECT 1 AS `space\\040name`", "SELECT 1 AS `space\\x20name`"] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("identifier decoding does not acquire an input")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "escaped identifiers use normal column alias and parameter scopes" {
  for
    source in [
      "SELECT o.`\\151d` AS `\\141nswer` FROM orders AS o", "FROM orders |> AS `\\157` |> SELECT `o`.`\\151d` AS `\\141nswer`",
      "SELECT @`\\160` AS answer",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let actual = compile(
      query,
      {
        ..fixture_context(),
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(actual).contains("\"fields\":[\"answer\"]"))
  }
}

///|
test "escaped and physical LF identifiers retain the ordinary field contract" {
  for source in ["SELECT 1 AS `line\\nname`", "SELECT 1 AS `line\r\nname`"] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(actual).contains("\"fields\":[\"line\\nname\"]"))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("a quoted name does not acquire an input")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}
