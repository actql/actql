///|
test "quoted IFNULL has the independently authored lazy common Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"coalesce":[{"literal":7},{"divide":[{"literal":1},{"literal":0}]}]}}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT IFNULL(7, 1 / 0) AS value", "SELECT `IFNULL`(7, 1 / 0) AS value", "SELECT `iFnUlL`(7, 1 / 0) AS value",
      "SELECT `\\x49FNULL`(7, 1 / 0) AS value",
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
      NeedsInputs(_) => fail("literal scalar calls must not acquire inputs")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}
