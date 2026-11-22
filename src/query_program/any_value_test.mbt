///|
test "SQL ANY_VALUE keeps original arguments and filters in the checked group" {
  for
    text in [
      "SELECT ANY_VALUE(1) AS result", "WITH f AS (SELECT 1 AS k, CAST(NULL AS INT64) AS v UNION ALL SELECT 1 AS k, CAST(7 AS INT64) AS v) SELECT k, ANY_VALUE(v WHERE k > 0) AS result FROM f GROUP BY k",
      "FROM pair |> AGGREGATE ANY_VALUE(x) AS result",
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
    assert_true(semantic(program).contains("\"fn\":\"any_value\""), msg=text)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("the authored test context fixes all inputs")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}

///|
test "SQL ANY_VALUE refuses unsupported aggregate modifiers" {
  for
    text in [
      "SELECT ANY_VALUE(1) OVER () AS result", "SELECT ANY_VALUE(DISTINCT 1) AS result",
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
      Err(UnsupportedAggregate | UnsupportedAnalytic) => ()
      Err(_) => fail("unexpected refusal for " + text)
    }
  }
}
