///|
test "SQL TO_JSON_STRING recognizes the original query and pretty flag" {
  for
    text in [
      "SELECT TO_JSON_STRING(1) AS result", "SELECT TO_JSON_STRING(NULL) AS result",
      "SELECT TO_JSON_STRING([1,2], TRUE) AS result", "WITH t AS (SELECT CAST('9007199254740993' AS INT64) AS v) SELECT TO_JSON_STRING(v, NULL) AS result FROM t",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"to_json_string\":"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) =>
        fail("authored JSON serialization has no external inputs")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}

///|
test "SQL TO_JSON_STRING requires a Boolean pretty flag" {
  let text = "SELECT TO_JSON_STRING(1, 'true') AS result"
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
    Err(_) => fail("unexpected refusal before serialization operand typing")
  }
}
