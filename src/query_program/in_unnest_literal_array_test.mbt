///|
fn literal_membership_declarations() -> @parameters.Declarations {
  let raw = @wire.admit(
    @source.parse_json(
      "{\"p\":{\"type\":\"number\",\"nullable\":true}}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  @parameters.read_declarations(Some(raw), {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
// Complete, independently authored existing Program. The source lowerer is
// never called to obtain a control expression, parameter or Result declaration.
test "literal array membership has an independently checked complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"p":{"type":"number","nullable":true}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"in":[{"literal":2},{"literal":[1,2,null,{"$param":"p"}]}]},"aql_query_expr_1":{"not_in":[{"literal":2},{"literal":[1,2,null,{"$param":"p"}]}]}}},{"select":[{"included":"aql_query_expr_0"},{"excluded":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["included","excluded"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let supplied = @wire.admit(
    @source.parse_json("{\"p\":null}", construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  for
    text in [
      "SELECT 2 IN UNNEST([1, 2, NULL, @p]) AS included, 2 NOT IN UNNEST([1, 2, NULL, @p]) AS excluded",
      "SELECT 2 IN UNNEST(ARRAY[(1), +((2)), NULL, ((@p))]) AS included, 2 NOT IN UNNEST((ARRAY[1, 2, NULL, @p])) AS excluded",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(literal_membership_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
    for program in [expected, actual] {
      match
        @check.check_parsed(
          program,
          check_environment(),
          Some(supplied),
          check_limits(),
        ) {
        Checked(_) => ()
        NeedsInputs(_) => fail("the scalar parameter is already supplied")
        Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      }
    }
  }
}

///|
test "literal array membership preserves the common type and parameter refusal" {
  for
    text in [
      "SELECT 2 IN UNNEST([1, TRUE]) AS included", "SELECT 2 IN UNNEST([@missing]) AS included",
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

///|
test "scalar annotated membership preserves the original item type refusal" {
  let actual = compile(
    @query.parse_query(
      "SELECT 2 IN UNNEST(ARRAY<STRING>[1]) AS found",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Rejected(_),
    msg="a STRING item declaration cannot admit a numeric ARRAY element",
  )
}
