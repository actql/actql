///|
test "SQL ARRAY_CONCAT checks original arrays, order and NULL context" {
  let text = "SELECT ARRAY_CONCAT([1], [2]) AS joined, ARRAY_CONCAT([], [3, 3], [1]) AS duplicates, ARRAY_CONCAT(NULL, [2]) AS absent"
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program).split("\"array_concat\":").length(), 4)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("authored arrays require no captured source")
    Rejected(issue) => raise @check.diagnostic_cause(issue)
  }
}

///|
test "SQL ARRAY_CONCAT refuses non-array and incompatible item domains" {
  for
    text in [
      "SELECT ARRAY_CONCAT(1) AS x", "SELECT ARRAY_CONCAT([1], ['2']) AS x",
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
      Err(_) => fail("unexpected failure before ARRAY_CONCAT typing: " + text)
    }
  }
}
