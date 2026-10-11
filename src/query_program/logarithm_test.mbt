///|
test "Exponential and logarithmic Programs match independent canonical controls" {
  for
    (text, expression) in [
      ("EXP(0)", "{\"exp\":{\"literal\":0}}"),
      ("LN(1)", "{\"ln\":{\"literal\":1}}"),
      ("LOG(1)", "{\"ln\":{\"literal\":1}}"),
      ("LOG10(100)", "{\"log10\":{\"literal\":100}}"),
      ("LOG(8, 2)", "{\"log\":[{\"literal\":8},{\"literal\":2}]}"),
      ("LOG(NULL, 1)", "{\"log\":[{\"literal\":null},{\"literal\":1}]}"),
      (
        "LOG(NULL, 1 / 0)", "{\"log\":[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
      ),
    ] {
    let expected = round_trunc_literal_control(expression)
    let actual = compile(
      @query.parse_query("SELECT " + text + " AS value", syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("literal math must not acquire input")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}

///|
test "Exponential and logarithmic Programs reject foreign and malformed arguments" {
  for
    text in [
      "EXP()", "EXP(1, 2)", "LN()", "LN(1, 2)", "LOG()", "LOG(1, 2, 3)", "LOG10()",
      "LOG10(1, 2)", "EXP('1')", "LN(TRUE)", "LOG(1, '2')", "LOG(NULL, '2')", "LOG10(CAST('1' AS DECIMAL(2,0)))",
      "LOG10(1e400)",
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

///|
test "Grouped LOG and LN reuse the same unary key without erasing binary LOG" {
  fn compiled(text : String) -> @program.Program {
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
  }
  let control = compiled("SELECT LN(1) AS value GROUP BY LN(1)")
  for
    text in [
      "SELECT LOG(1) AS value GROUP BY LN(1)", "SELECT LN(1) AS value GROUP BY LOG(1)",
      "SELECT `LoG`(1) AS value GROUP BY `lN`(1)",
    ] {
    assert_eq(semantic(compiled(text)), semantic(control))
  }
  let binary = compiled("SELECT LOG(8, 2) AS value GROUP BY LOG(8, 2)")
  let different = compiled("SELECT LOG(8, 2) AS value GROUP BY LN(8)")
  assert_true(semantic(binary) != semantic(different))
}
