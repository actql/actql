// Independently rebuilt diagnostic; no exact old-source identity is claimed.

///|
test "padding and side slices preserve independent source-free Programs" {
  for
    (source, body) in [
      ("LEFT('abc',2)", "{\"left\":[{\"literal\":\"abc\"},{\"literal\":2}]}"),
      ("RIGHT('abc',2)", "{\"right\":[{\"literal\":\"abc\"},{\"literal\":2}]}"),
      ("LPAD('abc',5)", "{\"lpad\":[{\"literal\":\"abc\"},{\"literal\":5}]}"),
      (
        "RPAD('abc',5,'x')", "{\"rpad\":[{\"literal\":\"abc\"},{\"literal\":5},{\"literal\":\"x\"}]}",
      ),
      (
        "LPAD(NULL,-1,'')", "{\"lpad\":[{\"literal\":null},{\"literal\":-1},{\"literal\":\"\"}]}",
      ),
      (
        "RIGHT('abc',ROUND(2.25,0))", "{\"right\":[{\"literal\":\"abc\"},{\"round\":[{\"literal\":2.25},{\"literal\":0}]}]}",
      ),
    ] {
    let expected = round_trunc_literal_control(body)
    let actual = compile(
      @query.parse_query("SELECT " + source + " AS value", syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
    for program in [expected, actual] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("literal padding needs no acquisition")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}

///|
test "padding and side field calls match complete SQL and Pipe Programs" {
  for
    (name, tag) in [
      ("LEFT", "left"),
      ("RIGHT", "right"),
      ("LPAD", "lpad"),
      ("RPAD", "rpad"),
    ] {
    let expected = @program.parse(
      (
        #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","derive":{"aql_query_expr_0":{
      ) +
      "\"" +
      tag +
      "\"" +
      (
        #|:[{"field":"status"},{"field":"amount"}]}}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
      ),
      construction_limits().program,
      format=Json,
    ).unwrap()
    for
      source in [
        "SELECT " + name + "(status,amount) AS value FROM orders",
        "FROM orders |> SELECT " + name + "(status,amount) AS value",
      ] {
      let actual = compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        fixture_context(),
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected), msg=source)
      for program in [expected, actual] {
        match
          @check.check_parsed(
            program,
            check_environment(),
            None,
            check_limits(),
          ) {
          Checked(_) => ()
          NeedsInputs(_) => fail("typed padding fields need no acquisition")
          Rejected(issue) => raise @check.diagnostic_cause(issue)
        }
      }
    }
  }
}
