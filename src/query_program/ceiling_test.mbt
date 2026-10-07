///|
test "CEIL and CEILING match an independent complete checked Program" {
  for
    (operand, expressions) in [
      ("2.3", "{\"literal\":2.3}"),
      ("NULL", "{\"literal\":null}"),
      ("-2.3", "{\"literal\":-2.3}"),
    ] {
    let expression = "{\"negate\":{\"floor\":{\"subtract\":[{\"literal\":0}," +
      expressions +
      "]}}}"
    let expected = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"aql_source_free\",\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]}},{\"from\":\"aql_source_free\",\"derive\":{\"aql_query_expr_0\":" +
      expression +
      "}},{\"select\":[{\"value\":\"aql_query_expr_0\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    match
      @check.check_parsed(expected, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("source-free ceiling needs no acquisition")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
    for function in ["CEIL", "CEILING"] {
      let actual = compile(
        @query.parse_query(
          "SELECT " + function + "(" + operand + ") AS value",
          syntax_limits(),
        ).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      assert_true(
        @check.check_parsed(actual, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}

///|
test "ceiling uses ordinary numeric type and parameter validation" {
  for
    source in [
      "SELECT CEIL('text') AS value", "SELECT CEILING(CAST(TRUE AS BOOL)) AS value",
      "SELECT CEIL(CAST('1.25' AS DECIMAL(8,3))) AS value",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(_),
    )
  }
  let actual = compile(
    @query.parse_query("SELECT CEILING(@p) AS value", syntax_limits()).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(number_parameter_declarations()),
    },
    construction_limits(),
  ).unwrap()
  for (body, valid) in [("{\"p\":-2.3}", true), ("{\"p\":\"text\"}", false)] {
    let supplied = @wire.admit(
      @source.parse_json(body, construction_limits().source.source).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    let checked = @check.check_parsed(
      actual,
      check_environment(),
      Some(supplied),
      check_limits(),
    )
    if valid {
      assert_true(checked is Checked(_))
    } else {
      assert_true(checked is Rejected(_))
    }
  }
}
