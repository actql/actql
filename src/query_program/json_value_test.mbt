///|
test "SQL JSON_VALUE checks original String input and admitted Json data" {
  for
    text in [
      "SELECT JSON_VALUE('{}', '$.n') AS result", "SELECT JSON_VALUE(JSON '{\"a\":[42]}', '$.a[0]') AS result",
      "WITH t AS (SELECT '{\"a\":1}' AS doc, '$.a' AS p) SELECT JSON_VALUE(doc, p) AS result FROM t",
      "SELECT JSON_VALUE(NULL) AS result",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"json_value\":"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("authored JSON extraction has no external inputs")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}

///|
test "SQL JSON_VALUE refuses an unsupported first argument or a non-String path" {
  for
    text in [
      "SELECT JSON_VALUE(1) AS result", "SELECT JSON_VALUE('{}', 1) AS result",
    ] {
    match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) =>
        assert_true(
          @check.check_parsed(
            program,
            check_environment(),
            None,
            check_limits(),
          )
          is Rejected(_),
        )
      Err(ExpressionTyping(_)) => ()
      Err(_) => fail("unexpected failure before JSON_VALUE typing")
    }
  }
}
