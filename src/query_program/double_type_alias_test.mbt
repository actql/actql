///|
test "NUMBER DOUBLE and FLOAT64 casts preserve the same checked numeric target" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"cast":{"value":{"literal":1.25},"target":{"type":"number"}}},"aql_query_expr_1":{"cast":{"value":{"literal":null},"target":{"type":"number"}}}}},{"select":[{"value":"aql_query_expr_0"},{"missing":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value","missing"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for target in ["NUMBER", "number", "NuMbEr", "FLOAT64", "DOUBLE", "dOuBlE"] {
    let actual = compile(
      @query.parse_query(
        "SELECT CAST(1.25 AS " +
        target +
        ") AS value, CAST(NULL AS " +
        target +
        ") AS missing",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=target)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "DOUBLE array annotations retain numeric item types NULLs and duplicates" {
  for
    (items, expression) in [
      (
        "[2, NULL, 2]", "{\"if\":[{\"literal\":true},{\"array\":[{\"literal\":2},{\"literal\":null},{\"literal\":2}]},{\"empty_array\":{\"items\":{\"type\":\"number\",\"nullable\":false}}}]}",
      ),
      (
        "[]", "{\"empty_array\":{\"items\":{\"type\":\"number\",\"nullable\":false}}}",
      ),
    ] {
    let expected = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"aql_source_free\",\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]}},{\"from\":\"aql_source_free\",\"derive\":{\"aql_query_expr_0\":" +
      expression +
      "}},{\"select\":[{\"items\":\"aql_query_expr_0\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"items\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    assert_true(
      @check.check_parsed(expected, check_environment(), None, check_limits())
      is Checked(_),
    )
    for target in ["FLOAT64", "DOUBLE", "dOuBlE"] {
      let actual = compile(
        @query.parse_query(
          "SELECT ARRAY<" + target + ">" + items + " AS items",
          syntax_limits(),
        ).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected), msg=target + items)
      assert_true(
        @check.check_parsed(actual, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}
