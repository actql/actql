///|
test "DATE_DIFF spellings retain one complete independent temporal Program" {
  for unit in ["ms", "s", "m", "h", "d"] {
    let declaration_wire = "{\"begin\":{\"type\":\"timestamp\"},\"finish\":{\"type\":\"timestamp\",\"nullable\":true}}"
    let declarations = parameter_reference_declarations(declaration_wire)
    let expected = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"params\":" +
      declaration_wire +
      ",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"aql_source_free\",\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]}},{\"from\":\"aql_source_free\",\"derive\":{\"aql_query_expr_0\":{\"date_diff\":[{\"$param\":\"finish\"},{\"$param\":\"begin\"},{\"literal\":\"" +
      unit +
      "\"}]}}},{\"select\":[{\"value\":\"aql_query_expr_0\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    for name in ["DATE_DIFF", "date_diff", "`DaTe_DiFf`"] {
      let text = "SELECT " + name + "(@finish, @begin, '" + unit + "') AS value"
      let actual = compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(declarations),
        },
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected), msg=text)
      assert_true(
        @check.check_parsed_scoped(
          actual,
          check_environment(),
          TemplateOnly,
          None,
          check_limits(),
        )
        is TemplateOnly(Verified(_)),
      )
      for program in [actual, expected] {
        let supplied = @wire.admit(
          @source.parse_json(
            "{\"begin\":\"1970-01-01T00:00:00.000Z\",\"finish\":\"1969-12-31T23:59:59.999999999Z\"}",
            construction_limits().source.source,
          ).unwrap(),
          construction_limits().source.tree,
        ).unwrap()
        match
          @check.check_parsed(
            program,
            check_environment(),
            Some(supplied),
            check_limits(),
          ) {
          Checked(_) => ()
          NeedsInputs(_) =>
            fail("bound temporal Program needs no acquired input")
          Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
        }
      }
    }
  }
}

///|
test "DATE_DIFF retains static unit arity and exact peer-domain refusals" {
  for
    text in [
      "SELECT DATE_DIFF() AS value", "SELECT DATE_DIFF(NULL, NULL) AS value", "SELECT DATE_DIFF(NULL, NULL, 'ms', 1) AS value",
      "SELECT DATE_DIFF(NULL, NULL, 'month') AS value", "SELECT DATE_DIFF(NULL, NULL, 'MS') AS value",
      "SELECT DATE_DIFF(NULL, NULL, LOWER('ms')) AS value",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.InvalidArguments, .. })),
      msg=text,
    )
  }
  for
    text in [
      "SELECT DATE_DIFF(1, 2, 'ms') AS value", "SELECT DATE_DIFF('1970-01-01', '1970-01-01', 'd') AS value",
      "SELECT DATE_DIFF(NULL, NULL, 'ms') AS value",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(_),
      msg=text,
    )
  }
}
