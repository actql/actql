///|
test "SQL UNIX_SECONDS checks the original Timestamp operand" {
  let program = compile(
    @query.parse_query(
      "SELECT UNIX_SECONDS(CAST('1969-12-31T23:59:59.999999999Z' AS TIMESTAMP)) AS seconds, UNIX_SECONDS(NULL) AS missing",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program).split("\"unix_seconds\":").length(), 3)
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "SQL UNIX_SECONDS rejects implicit Number and String operands" {
  for operand in ["1", "'1970-01-01T00:00:00.000Z'"] {
    let program = compile(
      @query.parse_query(
        "SELECT UNIX_SECONDS(" + operand + ") AS seconds",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg=operand,
    )
  }
}
