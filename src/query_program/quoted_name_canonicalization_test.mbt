///|
test "quoted output names use the same authored field identity in declarations and references" {
  for
    (name, canonical) in [
      ("e\\u0301", "\"é\""),
      ("line\\rname", "\"line\\nname\""),
    ] {
    let source = "SELECT 1 AS `" + name + "`"
    let expected = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"aql_source_free\",\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]}},{\"from\":\"aql_source_free\",\"derive\":{\"aql_query_expr_0\":{\"literal\":1}}},{\"select\":[{" +
      canonical +
      ":\"aql_query_expr_0\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[" +
      canonical +
      "]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    assert_true(
      @check.check_parsed(expected, check_environment(), None, check_limits())
      is Checked(_),
    )
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("Unexpected acquisition")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
    assert_eq(semantic(actual), semantic(expected), msg=source)
  }
}

///|
test "canonical quoted aliases remain usable through SQL and Pipe output scopes" {
  for
    (source, control) in [
      (
        "SELECT x AS `e\\u0301` FROM pair ORDER BY `é`", "SELECT x AS `é` FROM pair ORDER BY `é`",
      ),
      (
        "FROM pair |> SELECT x AS `é` |> RENAME `e\\u0301` AS `line\\rname` |> WHERE `line\\nname` > 0 |> ORDER BY `line\\rname`",
        "FROM pair |> SELECT x AS `é` |> RENAME `é` AS `line\\nname` |> WHERE `line\\nname` > 0 |> ORDER BY `line\\nname`",
      ),
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    let baseline = compile(
      @query.parse_query(control, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(baseline), msg=source)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "canonical identifier collisions cannot create two output aliases" {
  for
    source in [
      "SELECT x AS `é`, y AS `e\\u0301` FROM pair", "SELECT x AS `line\\nname`, y AS `line\\rname` FROM pair",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(DuplicateOutput),
      msg=source,
    )
  }
}
