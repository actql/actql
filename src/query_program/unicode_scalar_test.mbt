///|
test "Unicode scalar source free Programs match independently authored machine trees" {
  for
    (call, body) in [
      ("BYTE_LENGTH('😀')", "{\"byte_length\":{\"literal\":\"😀\"}}"),
      ("`OCTET_LENGTH`('😀')", "{\"byte_length\":{\"literal\":\"😀\"}}"),
      ("UNICODE('é')", "{\"unicode\":{\"literal\":\"é\"}}"),
      ("CHR(128512)", "{\"chr\":{\"literal\":128512}}"),
      ("CHR(UNICODE('😀'))", "{\"chr\":{\"unicode\":{\"literal\":\"😀\"}}}"),
      ("CHR(NULL)", "{\"chr\":{\"literal\":null}}"),
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
        NeedsInputs(_) => fail("literal Unicode scalar needs no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}
