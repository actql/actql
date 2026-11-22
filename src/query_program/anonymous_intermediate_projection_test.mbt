///|
test "intermediate unnamed SELECT retains its complete original captured row" {
  let source = "FROM pair |> SELECT x + 1, y AS n |> AS captured |> SELECT captured AS row"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("an intermediate anonymous SELECT is not an unsupported projection")
    Err(issue) =>
      fail(
        "wrong intermediate SELECT refusal: " + infer_defaults_issue_tag(issue),
      )
  }
  assert_eq(anonymous_result_fields(program), ["row"])
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the original pair remains closed")
  }
}

///|
test "intermediate unnamed aggregate analytic and retained CTE values stay complete" {
  for
    source in [
      "SELECT COUNT(*) FROM pair |> AS captured |> SELECT captured AS row", "FROM pair |> SELECT RANK() OVER (ORDER BY x), y AS n |> AS captured |> SELECT captured AS row",
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x |> SELECT x + 1, n |> AS captured |> SELECT captured AS row",
    ] {
    let program = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedAggregate) => fail("UnsupportedAggregate: " + source)
      Err(UnsupportedAnalytic) => fail("UnsupportedAnalytic: " + source)
      Err(UnsupportedProjection) => fail("UnsupportedProjection: " + source)
      Err(issue) =>
        fail(
          "wrong intermediate value refusal: " +
          source +
          ": " +
          infer_defaults_issue_tag(issue),
        )
    }
    assert_eq(anonymous_result_fields(program), ["row"], msg=source)
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail(
          "intermediate aggregate/analytic values retain the original closed inputs",
        )
    }
  }
  let source = "WITH t AS (SELECT 1 AS x) FROM t |> SELECT x + 1, 3 AS n |> AS captured |> SELECT captured AS row"
  let program = anonymous_result_program(source)
  assert_eq(anonymous_result_fields(program), ["row"])
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the CTE row remains complete")
  }
}

///|
test "intermediate anonymous values stay unnamed while genuine row names remain accessible" {
  for
    tail in [
      "SELECT f0_", "SELECT captured.f0_", "SELECT (captured).f0_", "ORDER BY f0_",
    ] {
    let source = "FROM pair |> SELECT x + 1, y AS n |> AS captured |> " + tail
    match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(issue) =>
        fail(
          "wrong intermediate unnamed member refusal: " +
          infer_defaults_issue_tag(issue),
        )
      Ok(_) => fail("an intermediate DATA name became a SQL name: " + source)
    }
  }
  for
    source in [
      "FROM pair |> SELECT x + 1, y AS n |> AS captured |> SELECT captured.n AS value",
      "FROM pair |> SELECT x + 1 AS f0_, y AS n |> AS captured |> SELECT captured.f0_ AS value",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let program = compile(query, pair_context(), construction_limits()).unwrap()
    assert_eq(anonymous_result_fields(program), ["value"])
    assert_eq(
      semantic(program),
      semantic(compile(query, pair_context(), construction_limits()).unwrap()),
    )
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("genuine intermediate row names remain closed")
    }
  }
}

///|
test "original intermediate SELECT set fixture reaches the real member namespace owner" {
  let source = "SELECT STRUCT(1 AS f0_, 2 AS n) AS row FROM pair UNION ALL (FROM pair |> SELECT 1, 2 AS n |> AS captured |> SELECT captured AS row) ORDER BY "
  match
    compile(
      @query.parse_query(source + "row.f0_", syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ) {
    Err(UnknownColumn)
    | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
    Err(issue) =>
      fail(
        "the intermediate operand stopped before member checking: " +
        infer_defaults_issue_tag(issue),
      )
    Ok(_) => fail("the original anonymous set member became named")
  }
  let program = compile(
    @query.parse_query(source + "row.n", syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(anonymous_result_fields(program), ["row"])
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the original two set rows remain closed")
  }
}

///|
test "unnamed analytic staging does not require a later terminal SELECT" {
  for
    source in [
      "FROM pair |> SELECT RANK() OVER (ORDER BY x), y AS n |> AGGREGATE COUNT(*) AS total",
      "FROM pair |> SELECT RANK() OVER (ORDER BY x), y AS n |> AS kept |> AGGREGATE COUNT(*) AS total",
    ] {
    let program = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedProjection) =>
        fail(
          "an original anonymous analytic does not need a terminal SELECT: " +
          source,
        )
      Err(issue) =>
        fail(
          "wrong no-terminal analytic refusal: " +
          infer_defaults_issue_tag(issue),
        )
    }
    assert_eq(anonymous_result_fields(program), ["total"])
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the original no-terminal aggregate remains closed")
    }
  }
  let program = compile_query_script(
    @query.parse_query_script(
      "WITH counted AS (FROM pair |> SELECT RANK() OVER (ORDER BY x), y AS n |> AGGREGATE COUNT(*) AS total) SELECT total FROM counted",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(anonymous_result_fields(program), ["total"])
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the CTE retains the same closed original aggregate")
  }
}

///|
test "no-terminal analytic profile never makes a private evaluated label readable" {
  for
    tail in [
      "AGGREGATE COUNT(f0_) AS total", "AGGREGATE COUNT(aql_set_anonymous_3) AS total",
      "AS kept |> AGGREGATE COUNT(kept.f0_) AS total",
    ] {
    let source = "FROM pair |> SELECT RANK() OVER (ORDER BY x), y AS n |> " +
      tail
    match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(issue) =>
        fail(
          "wrong no-terminal private label refusal: " +
          infer_defaults_issue_tag(issue),
        )
      Ok(_) =>
        fail(
          "an evaluated anonymous label became an aggregate input: " + source,
        )
    }
  }
}
