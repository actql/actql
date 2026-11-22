///|
test "SQL ARRAY_TO_STRING accepts original arrays with optional replacement" {
  let text = "SELECT ARRAY_TO_STRING(['a'], ',') AS joined, ARRAY_TO_STRING([NULL, '', NULL, 'x'], '|') AS skipped, ARRAY_TO_STRING([NULL, '', NULL, 'x'], '|', 'n') AS replaced"
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program).split("\"array_to_string\":").length(), 4)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("authored string arrays require no captured source")
    Rejected(issue) => raise @check.diagnostic_cause(issue)
  }
}

///|
test "SQL ARRAY_TO_STRING refuses non-string array items or separators" {
  for
    text in [
      "SELECT ARRAY_TO_STRING([1], ',') AS x", "SELECT ARRAY_TO_STRING(['a'], 1) AS x",
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
          msg=text,
        )
      Err(ExpressionTyping(_)) => ()
      Err(_) =>
        fail("unexpected failure before ARRAY_TO_STRING typing: " + text)
    }
  }
}
