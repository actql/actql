///|
test "SQL logical aggregates lower the original Boolean operands through common extrema" {
  for
    text in [
      "SELECT LOGICAL_AND(TRUE) AS all_true, LOGICAL_OR(FALSE) AS any_true", "SELECT LOGICAL_AND(NULL) AS all_true, LOGICAL_OR(NULL) AS any_true",
      "SELECT LOGICAL_AND(TRUE) AS all_true, LOGICAL_OR(FALSE) AS any_true WHERE FALSE",
      "WITH f AS (SELECT 1 AS k, TRUE AS flag UNION ALL SELECT 1 AS k, FALSE AS flag UNION ALL SELECT 2 AS k, CAST(NULL AS BOOLEAN) AS flag) SELECT k, LOGICAL_AND(flag) AS all_true, LOGICAL_OR(flag WHERE k > 0) AS any_true FROM f GROUP BY k ORDER BY k",
      "FROM pair |> AGGREGATE LOGICAL_AND(x > 0) AS all_true, LOGICAL_OR(y > 0) AS any_true",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      if text.has_prefix("FROM pair") {
        pair_context()
      } else {
        { ..fixture_context(), inputs: [], }
      },
      construction_limits(),
    ).unwrap()
    let terms = semantic(program)
    assert_true(terms.contains("\"fn\":\"min\""), msg=text)
    assert_true(terms.contains("\"fn\":\"max\""), msg=text)
    assert_true(terms.contains("\"and\":["), msg=text)
    assert_true(terms.contains("\"or\":["), msg=text)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("the authored test context fixes all inputs")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}

///|
test "SQL logical aggregates retain the Boolean boundary beside ordinary extrema" {
  for
    text in [
      "SELECT LOGICAL_AND(1) AS x", "SELECT MIN(1) AS n, LOGICAL_AND(1) AS x", "SELECT LOGICAL_OR('true') AS x",
      "SELECT LOGICAL_AND(DISTINCT TRUE) AS x", "SELECT LOGICAL_OR(TRUE) OVER () AS x",
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
      Err(ExpressionTyping(_) | UnsupportedAggregate | UnsupportedAnalytic) =>
        ()
      Err(_) => fail("unexpected refusal for " + text)
    }
  }
}
