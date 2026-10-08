///|
test "quoted statistical calls match the independent complete common Program" {
  let expected = statistical_expected_program()
  check_statistical_program(expected)
  for
    text in [
      "SELECT VAR_POP(amount + 1) AS v FROM orders", "SELECT `VAR_POP`(amount + 1) AS v FROM orders",
      "FROM orders |> AGGREGATE `vAr_PoP`(amount + 1) AS v", "SELECT `\\x56AR_POP`(amount + 1) AS v FROM orders",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    check_statistical_program(program)
  }
}

///|
test "quoted COUNTIF OVER preserves the independent frame and nullable operands" {
  let expected = analytic_countif_expected()
  let frame = "ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING"
  for
    text in [
      "SELECT id, `COUNTIF`(flag) OVER (" +
      frame +
      ") AS truthy, `countif`(amount > 10) OVER (" +
      frame +
      ") AS positive FROM flags ORDER BY id",
      "FROM flags |> SELECT id, `COUNTIF`(flag) OVER (" +
      frame +
      ") AS truthy, `countif`(amount > 10) OVER (" +
      frame +
      ") AS positive |> ORDER BY id",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      analytic_countif_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("framed Values control must be closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "quoted COUNT star preserves the independent empty-input group Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","filter":{"literal":false}},{"group":{"by":[],"aggregates":{"n":{"fn":"count"}}}},{"select":["n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT COUNT(*) AS n WHERE FALSE", "SELECT `COUNT`(*) AS n WHERE FALSE",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("empty source-free group must not acquire inputs")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}
