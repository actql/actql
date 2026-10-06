///|
test "GoogleSQL BOOLEAN is the same checked cast target as BOOL" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"cast":{"value":{"literal":true},"target":{"type":"boolean"}}},"aql_query_expr_1":{"cast":{"value":{"literal":null},"target":{"type":"boolean"}}}}},{"select":[{"flag":"aql_query_expr_0"},{"missing":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["flag","missing"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    source in [
      "SELECT CAST(TRUE AS BOOL) AS flag, CAST(NULL AS BOOL) AS missing", "SELECT CAST(TRUE AS BOOLEAN) AS flag, CAST(NULL AS BOOLEAN) AS missing",
      "SELECT CAST(TRUE AS bOoLeAn) AS flag, CAST(NULL AS BOOL) AS missing",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let actual = compile(
      query,
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
