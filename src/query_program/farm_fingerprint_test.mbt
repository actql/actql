///|
test "SQL FARM_FINGERPRINT checks String and returns the exact integer domain" {
  for
    text in [
      "SELECT FARM_FINGERPRINT('a') AS result", "WITH t AS (SELECT 'a' AS s) SELECT FARM_FINGERPRINT(s) AS result FROM t",
      "SELECT FARM_FINGERPRINT(NULL) AS result",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"farm_fingerprint\":"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("the authored String has no Source input")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}

///|
test "SQL FARM_FINGERPRINT refuses a Number operand" {
  match
    compile(
      @query.parse_query(
        "SELECT FARM_FINGERPRINT(1) AS result",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) =>
      assert_true(
        @check.check_parsed(program, check_environment(), None, check_limits())
        is Rejected(_),
      )
    Err(ExpressionTyping(_)) => ()
    Err(_) => fail("unexpected failure before fingerprint typing")
  }
}
