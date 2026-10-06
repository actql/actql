///|
test "omitted output AS preserves the independent ordinary Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":"hello"}}},{"select":[{"id":"aql_query_expr_0"},{"label":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","label"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("independent source-free control requires no input proofs")
  }
  for
    text in [
      "SELECT 1 AS id, 'hello' AS label", "SELECT 1 id, 'hello' label", "SELECT 1 `id`, 'hello' `label`",
    ] {
    let generated = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(generated), semantic(expected))
  }
}

///|
test "omitted aggregate AS preserves the independent common Group" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","group":{"by":[],"aggregates":{"n":{"fn":"count"}}}},{"select":["n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for text in ["SELECT COUNT(*) n", "SELECT COUNT(*) AS n"] {
    let generated = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(generated), semantic(expected))
    for program in [expected, generated] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) | NeedsInputs(_) => ()
        Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      }
    }
  }
}
