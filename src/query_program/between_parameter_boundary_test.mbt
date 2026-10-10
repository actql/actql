///|
test "BETWEEN typed nullable parameter preserves the full independent Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"p":{"type":"number","nullable":true}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"between":[{"$param":"p"},{"literal":1},{"literal":2}]}}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let declarations = parameter_reference_declarations(
    "{\"p\":{\"type\":\"number\",\"nullable\":true}}",
  )
  for
    text in [
      "SELECT @p BETWEEN 1 AND 2 AS value", "SELECT @P BETWEEN 1 AND 2 AS value",
    ] {
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
    for value in ["2", "null"] {
      for program in [expected, actual] {
        match
          @check.check_parsed(
            program,
            check_environment(),
            Some(analytic_frame_parameter_values(value)),
            check_limits(),
          ) {
          Checked(_) => ()
          NeedsInputs(_) => fail("bound BETWEEN needs no acquisition")
          Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
        }
      }
    }
  }
}
