///|
fn in_unnest_declarations() -> @parameters.Declarations {
  let raw = @wire.admit(
    @source.parse_json(
      (
        #|{"xs":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}}
      ),
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
test "IN UNNEST matches a complete independent ordinary Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"xs":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"in":[{"literal":2},{"$param":"xs"}]},"aql_query_expr_1":{"not_in":[{"literal":2},{"$param":"xs"}]}}},{"select":[{"included":"aql_query_expr_0"},{"excluded":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["included","excluded"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let supplied = @wire.admit(
    @source.parse_json("{\"xs\":[2,null]}", construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(),
      Some(supplied),
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) =>
      fail("independent array parameter Program needs no acquisition")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let actual = compile(
    @query.parse_query(
      "SELECT 2 IN UNNEST(@xs) AS included, 2 NOT IN UNNEST(@xs) AS excluded",
      syntax_limits(),
    ).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(in_unnest_declarations()),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match
    @check.check_parsed(
      actual,
      check_environment(),
      Some(supplied),
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) =>
      fail("source array parameter Program needs no acquisition")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "IN UNNEST preserves common parameter validation instead of substituting a set" {
  let query = @query.parse_query(
    "SELECT 2 IN UNNEST(@xs) AS included",
    syntax_limits(),
  ).unwrap()
  let actual = compile(
    query,
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(in_unnest_declarations()),
    },
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is NeedsInputs(_),
  )
  for value in ["2", "[true]", "[1,2,3,4]"] {
    let supplied = @wire.admit(
      @source.parse_json(
        "{\"xs\":" + value + "}",
        construction_limits().source.source,
      ).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(supplied),
        check_limits(),
      )
      is Rejected(_),
      msg=value,
    )
  }
  let undeclared = compile(
    query,
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(undeclared, check_environment(), None, check_limits())
    is Rejected(_),
  )
}
