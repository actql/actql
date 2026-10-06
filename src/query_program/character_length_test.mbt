///|
test "character length matches an independently authored checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"len":{"literal":"é😀"}}}},{"select":[{"n":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent source-free Program must be closed")
  }
  for name in ["LENGTH", "CHAR_LENGTH", "CHARACTER_LENGTH"] {
    let actual = compile(
      @query.parse_query(
        "SELECT " + name + "('e\\u0301\\U0001F600') AS n",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("character length must not introduce an external input")
    }
  }
}

///|
test "character length delegates operand typing to the ordinary checker" {
  let actual = compile(
    @query.parse_query("SELECT CHAR_LENGTH(1) AS n", syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Rejected(_),
  )
}
