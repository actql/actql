///|
test "precision rounding preserves independent complete SQL literal Programs" {
  for name in ["round", "trunc"] {
    for
      (arguments, children) in [
        ("1.235, 2", "[{\"literal\":1.235},{\"literal\":2}]"),
        ("125, -1", "[{\"literal\":125},{\"literal\":-1}]"),
        ("NULL, 2", "[{\"literal\":null},{\"literal\":2}]"),
        ("1.25, NULL", "[{\"literal\":1.25},{\"literal\":null}]"),
        (
          "NULL, 1 / 0", "[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]",
        ),
      ] {
      let expected = round_trunc_literal_control(
        "{\"" + name + "\":" + children + "}",
      )
      let actual = compile(
        @query.parse_query(
          "SELECT " + name + "(" + arguments + ") AS value",
          syntax_limits(),
        ).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      for program in [actual, expected] {
        match
          @check.check_parsed(
            program,
            check_environment(),
            None,
            check_limits(),
          ) {
          Checked(_) => ()
          NeedsInputs(_) => fail("precision literal needs no acquisition")
          Rejected(issue) => raise @check.diagnostic_cause(issue)
        }
      }
    }
  }
}

///|
test "precision rounding type checks both operands without decimal or string coercion" {
  for name in ["ROUND", "TRUNC"] {
    for
      arguments in [
        "1.25, '2'", "1.25, TRUE", "1.25, CAST('2' AS DECIMAL(2,0))", "'1.25', 2",
        "NULL, '2'", "1.25, B'2'",
      ] {
      let syntax = @query.parse_query(
        "SELECT " + name + "(" + arguments + ") AS value",
        syntax_limits(),
      )
      match syntax {
        Err(_) => ()
        Ok(parsed) =>
          match
            compile(
              parsed,
              { ..fixture_context(), inputs: [], },
              construction_limits(),
            ) {
            Err(_) => ()
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
          }
      }
    }
  }
}
