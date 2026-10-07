///|
// This verifies current source-to-Program wiring, not execution or GoogleSQL
// conformance of the common scalar laws. Expectations are authored directly.
test "scalar boundary source preserves the complete independent Program" {
  for
    (text, expression) in [
      ("SQRT(9)", "{\"sqrt\":{\"literal\":9}}"),
      ("LOWER('É')", "{\"lower\":{\"literal\":\"É\"}}"),
      ("UPPER('é')", "{\"upper\":{\"literal\":\"é\"}}"),
      ("TRIM('\\u2003value\\u2003')", "{\"trim\":{\"literal\":\" value \"}}"),
    ] {
    let expected = @program.parse(
      (
        #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":
      ) + expression + (
        #|}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
      ),
      construction_limits().program,
      format=Json,
    ).unwrap()
    let actual = compile(
      @query.parse_query("SELECT " + text + " AS value", syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
    for program in [expected, actual] {
      match @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("literal scalar control must not acquire inputs")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}
