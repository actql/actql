///|
test "duplicate USING names are invalid even when projection hides a repeated key" {
  for kind in ["INNER", "LEFT", "RIGHT", "FULL"] {
    for selected in ["l.x AS original", "*"] {
      let text = "SELECT " +
        selected +
        " FROM t AS l " +
        kind +
        " JOIN t AS r USING (x, `X`) MAX_OUTPUT_ROWS 10"
      let query = @query.parse_query(text, syntax_limits()).unwrap()
      for
        result in [
          compile(query, join_order_context(), construction_limits()),
          compile_query_script(
            @query.single_query_script(query),
            join_order_context(),
            construction_limits(),
          ),
        ] {
        match result {
          Ok(program) => fail("duplicate USING accepted: " + semantic(program))
          Err(DuplicateOutput) => ()
          Err(UnsupportedJoin) => fail("UnsupportedJoin: " + text)
          Err(_) => fail("unexpected refusal: " + text)
        }
      }
    }
  }
}

///|
test "valid USING keys preserve declared order and existing checker admission" {
  for kind in ["INNER", "LEFT", "RIGHT"] {
    let text = "SELECT * FROM t AS l " +
      kind +
      " JOIN t AS r USING (`Y`, x) MAX_OUTPUT_ROWS 10 ORDER BY x"
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, join_order_context(), construction_limits()).unwrap()
    let wire = semantic(program)
    assert_true(
      wire.contains(
        "\"on\":[{\"left\":\"y\",\"right\":\"y\"},{\"left\":\"x\",\"right\":\"x\"}]",
      ),
    )
    assert_true(wire.contains("\"fields\":[\"y\",\"x\"]"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("valid Values JOIN keys retain closed inputs")
    }
  }
}

///|
test "duplicate ON predicates keep their existing ordinary JOIN meaning" {
  let text = "SELECT l.x FROM t AS l JOIN t AS r ON l.x = r.x AND l.x = r.x MAX_OUTPUT_ROWS 10"
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(program).contains(
      "\"on\":[{\"left\":\"x\",\"right\":\"x\"},{\"left\":\"x\",\"right\":\"x\"}]",
    ),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("repeated ON conditions do not become duplicate USING names")
  }
}
