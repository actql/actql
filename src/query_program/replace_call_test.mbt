///|
test "REPLACE source matches an independently authored checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"replace":[{"literal":"banana"},{"literal":"ana"},{"literal":"X"}]}}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("the independent replacement control needs no input")
    Rejected(error) => raise @check.diagnostic_cause(error)
  }
  for
    text in [
      "SELECT REPLACE('banana', 'ana', 'X') AS value", "SELECT replace('banana', 'ana', 'X') AS value",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("source-free replacement must not acquire inputs")
      Rejected(error) => raise @check.diagnostic_cause(error)
    }
  }
}
