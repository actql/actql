///|
test "SQL FORMAT checks the original and dynamic text template" {
  for
    text in [
      "SELECT FORMAT('%s', 'a') AS result", "WITH t AS (SELECT '%-4.2s/%%/%s' AS pattern, 'x🙂y' AS s) SELECT FORMAT(pattern, s, 'ok') AS result FROM t",
      "SELECT FORMAT('%s', NULL) AS result",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"format_strings\":"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("authored text needs no captured Source")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}

///|
test "SQL FORMAT does not silently convert numeric arguments to String" {
  let text = "SELECT FORMAT('%s', 1) AS result"
  match
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) =>
      assert_true(
        @check.check_parsed(program, check_environment(), None, check_limits())
        is Rejected(_),
      )
    Err(ExpressionTyping(_)) => ()
    Err(_) => fail("unexpected refusal before FORMAT operand typing")
  }
}
