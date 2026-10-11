///|
test "translate instr complete Programs match independent trees including omitted defaults" {
  {
    let expected = split_literal_control(
      "{\"translate\":[{\"literal\":\"ab\"},{\"literal\":\"ab\"},{\"literal\":\"ba\"}]}",
    )
    let actual = compile(
      @query.parse_query(
        "SELECT translate('ab','ab','ba') AS value",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("translate instr literals need no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
  {
    let expected = split_literal_control(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}",
    )
    let actual = compile(
      @query.parse_query(
        "SELECT instr('banana','an') AS value",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("translate instr literals need no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
  {
    let expected = split_literal_control(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
    )
    let actual = compile(
      @query.parse_query(
        "SELECT instr('banana','an',1) AS value",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("translate instr literals need no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
  {
    let expected = split_literal_control(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
    )
    let actual = compile(
      @query.parse_query(
        "SELECT instr('banana','an',1,1) AS value",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("translate instr literals need no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
  {
    let expected = split_literal_control(
      "{\"instr\":[{\"literal\":\"aaaa\"},{\"literal\":\"aa\"},{\"literal\":-1},{\"literal\":2}]}",
    )
    let actual = compile(
      @query.parse_query(
        "SELECT instr('aaaa','aa',-1,2) AS value",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("translate instr literals need no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
  {
    let expected = split_literal_control(
      "{\"translate\":[{\"literal\":null},{\"literal\":\"aa\"},{\"literal\":\"x\"}]}",
    )
    let actual = compile(
      @query.parse_query(
        "SELECT TRANSLATE(NULL,'aa','x') AS value",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("translate instr literals need no Source")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
  let expected = split_literal_control(
    "{\"instr\":[{\"literal\":null},{\"literal\":\"a\"},{\"literal\":0},{\"literal\":-1}]}",
  )
  let actual = compile(
    @query.parse_query("SELECT INSTR(NULL,'a',0,-1) AS value", syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  for program in [actual, expected] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("translate instr literals need no Source")
      Rejected(issue) => raise @check.diagnostic_cause(issue)
    }
  }
}
