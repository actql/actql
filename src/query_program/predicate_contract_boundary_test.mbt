///|
// Independently authored machine expressions establish wiring only. LIKE's
// current common NULL contract is not certification of GoogleSQL semantics.
test "predicate boundary source preserves complete independent Programs" {
  for
    (text, expression) in [
      (
        "2 BETWEEN 1 AND 3", "{\"between\":[{\"literal\":2},{\"literal\":1},{\"literal\":3}]}",
      ),
      (
        "2 NOT BETWEEN 1 AND 3", "{\"not\":{\"between\":[{\"literal\":2},{\"literal\":1},{\"literal\":3}]}}",
      ),
      (
        "'abc' LIKE 'a%'", "{\"like\":[{\"literal\":\"abc\"},{\"literal\":\"a%\"}]}",
      ),
      (
        "'abc' NOT LIKE 'a%'", "{\"not\":{\"like\":[{\"literal\":\"abc\"},{\"literal\":\"a%\"}]}}",
      ),
      (
        "3 BETWEEN 4 AND NULL", "{\"between\":[{\"literal\":3},{\"literal\":4},{\"literal\":null}]}",
      ),
      (
        "3 NOT BETWEEN 4 AND NULL", "{\"not\":{\"between\":[{\"literal\":3},{\"literal\":4},{\"literal\":null}]}}",
      ),
      ("NULL LIKE 'a%'", "{\"like\":[{\"literal\":null},{\"literal\":\"a%\"}]}"),
      (
        "'abc' LIKE NULL", "{\"like\":[{\"literal\":\"abc\"},{\"literal\":null}]}",
      ),
    ] {
    let expected = @program.parse(
      (
        #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":
      ) +
      expression +
      (
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
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => assert_true(text != "'abc' LIKE NULL")
        NeedsInputs(_) => fail("literal predicate must not acquire inputs")
        Rejected(issue) =>
          if text == "'abc' LIKE NULL" {
            assert_eq(@check.diagnostic_category(issue), @check.InvalidInput)
          } else {
            raise @check.diagnostic_cause(issue)
          }
      }
    }
  }
}
