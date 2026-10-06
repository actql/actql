///|
test "unary plus SELECT matches a complete independent checked Program" {
  let expression =
    #|{"negate":{"negate":{"cast":{"value":{"literal":"1.25"},"target":{"type":"decimal","precision":8,"scale":3}}}}}
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"aql_source_free\",\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]}},{\"from\":\"aql_source_free\",\"derive\":{\"aql_query_expr_0\":" +
    expression +
    "}},{\"select\":[{\"value\":\"aql_query_expr_0\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "SELECT +CAST('1.25' AS DECIMAL(8,3)) AS value",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  for program in [expected, actual] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) =>
        fail("source-free numeric expression needs no acquisition")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "unary plus references and parameters use ordinary checker rejection" {
  for
    source in [
      "SELECT +status AS value FROM orders", "SELECT +CAST(TRUE AS BOOL) AS value",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(_),
    )
  }
  let actual = compile(
    @query.parse_query("SELECT +@p AS value", syntax_limits()).unwrap(),
    {
      ..values_context(),
      inputs: [],
      parameter_declarations: Some(number_parameter_declarations()),
    },
    construction_limits(),
  ).unwrap()
  for (body, valid) in [("{\"p\":-7}", true), ("{\"p\":\"text\"}", false)] {
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
