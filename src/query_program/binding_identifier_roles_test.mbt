///|
test "quoted reserved output lowers to the independent ordinary Program and common checker" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"ROWS":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["ROWS"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query("SELECT 1 AS `ROWS`", syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("a quoted output does not acquire an input")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "quoted manual row aliases reach the ordinary common Program checker" {
  for
    source in [
      "SELECT `ROWS` AS id FROM UNNEST([1]) AS `ROWS`", "SELECT `ROWS` AS id FROM UNNEST([1]) AS item WITH OFFSET AS `ROWS`",
      "WITH result_rows AS (SELECT 1 AS id) FROM result_rows |> AS `ROWS` |> SELECT `ROWS`.id",
      "WITH result_rows AS (SELECT 1 AS x) FROM result_rows |> UNPIVOT(v FOR k IN(x)) AS `ROWS` |> SELECT `ROWS`.v AS id",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_true(semantic(actual).contains("\"fields\":[\"id\"]"), msg=source)
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("the authored value is source-free")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}
