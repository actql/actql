///|
test "IFNULL produces an independently authored and normally checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"coalesce":[{"literal":null},{"literal":7}]}}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("the independent control needs no inputs")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  for
    text in [
      "SELECT IFNULL(NULL, 7) AS value", "SELECT ifnull(NULL, 7) AS value",
    ] {
    let generated = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(generated), semantic(expected))
    match
      @check.check_parsed(generated, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("source-free IFNULL must not acquire inputs")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}
