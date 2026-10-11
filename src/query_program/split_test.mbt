///|
// Complete controls are independently authored, not compiler-derived. The
// fixed machine program establishes the complete source-free shape.
fn split_literal_control(expression : String) -> @program.Program {
  @program.parse(
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
}

///|
test "SPLIT compiles source-free Programs against independent machine JSON" {
  for
    (call, body) in [
      ("SPLIT('a,b')", "{\"split\":[{\"literal\":\"a,b\"}]}"),
      (
        "SPLIT('a::b','::')", "{\"split\":[{\"literal\":\"a::b\"},{\"literal\":\"::\"}]}",
      ),
      ("SPLIT('','')", "{\"split\":[{\"literal\":\"\"},{\"literal\":\"\"}]}"),
      (
        "SPLIT(NULL,LOWER(','))", "{\"split\":[{\"literal\":null},{\"lower\":{\"literal\":\",\"}}]}",
      ),
    ] {
    let expected = split_literal_control(body)
    let actual = compile(
      @query.parse_query("SELECT " + call + " AS value", syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("literal SPLIT needs no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}

///|
test "SPLIT SQL and Pipe field delimiters share one complete checked Program" {
  // Retain the ordinary key so Array-valued output has deterministic row order.
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{\"orders\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false},\"customer_id\":{\"type\":\"string\",\"nullable\":false},\"status\":{\"type\":\"string\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}},\"steps\":[{\"from\":\"orders\",\"derive\":{\"aql_query_expr_1\":{\"split\":[{\"field\":\"status\"},{\"field\":\"id\"}]}}},{\"select\":[\"id\",{\"value\":\"aql_query_expr_1\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"id\",\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT id, SPLIT(status,id) AS value FROM orders", "FROM orders |> SELECT id, SPLIT(status,id) AS value",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      fixture_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("typed SPLIT needs no additional Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}
