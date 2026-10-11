///|
test "repeat reverse complete source free Programs match independent machine trees" {
  for
    (call, body) in [
      (
        "REPEAT('😀é',2)", "{\"repeat\":[{\"literal\":\"😀é\"},{\"literal\":2}]}",
      ),
      ("`REVERSE`('😀é')", "{\"reverse\":{\"literal\":\"😀é\"}}"),
      (
        "REVERSE(REPEAT('😀é',2))", "{\"reverse\":{\"repeat\":[{\"literal\":\"😀é\"},{\"literal\":2}]}}",
      ),
      (
        "REPEAT('',1e100)", "{\"repeat\":[{\"literal\":\"\"},{\"literal\":1e+100}]}",
      ),
      ("REPEAT(NULL,-1)", "{\"repeat\":[{\"literal\":null},{\"literal\":-1}]}"),
      ("REVERSE(NULL)", "{\"reverse\":{\"literal\":null}}"),
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
        NeedsInputs(_) => fail("literal repeat reverse needs no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}
