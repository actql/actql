///|
test "POW SQL Programs match independent canonical literal controls" {
  for name in ["POW", "POWER", "`PoWeR`"] {
    for
      (arguments, children) in [
        ("2, 3", "[{\"literal\":2},{\"literal\":3}]"),
        ("0, 0", "[{\"literal\":0},{\"literal\":0}]"),
        ("NULL, -1", "[{\"literal\":null},{\"literal\":-1}]"),
        (
          "NULL, 1 / 0", "[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]",
        ),
      ] {
      let expected = round_trunc_literal_control("{\"pow\":" + children + "}")
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
          NeedsInputs(_) => fail("literal POW must not acquire input")
          Rejected(issue) => raise @check.diagnostic_cause(issue)
        }
      }
    }
  }
}

///|
test "POW refuses foreign domains and invalid arities without coercion" {
  for
    text in [
      "POW(2)", "POW(2, 3, 4)", "POWER(2)", "POWER(2, 3, 4)", "POW('2', 3)", "POW(2, TRUE)",
      "POW(NULL, '3')", "POW(2, CAST('3' AS DECIMAL(2,0)))", "MOD(5, 2)", "POW(1e400, 0)",
      "POW(1, 1e400)",
    ] {
    match @query.parse_query("SELECT " + text + " AS value", syntax_limits()) {
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
