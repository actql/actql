///|
fn statistical_alias_reuse_expected(function_name : String) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","group":{"by":[],"aggregates":{"v":{"fn":"var_samp","field":"amount"}}}},{"select":["v"]},{"distinct":["v"]},{"sort":[{"field":"v","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["v"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ).replace(old="var_samp", new=function_name),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "statistical DISTINCT ORDER aliases reuse one independently checked aggregate" {
  for
    (selected, ordered, function_name) in [
      ("VAR_SAMP", "VAR_SAMP", "var_samp"),
      ("VARIANCE", "VAR_SAMP", "var_samp"),
      ("VAR_SAMP", "VARIANCE", "var_samp"),
      ("STDDEV", "STDDEV_SAMP", "stddev_samp"),
      ("STDDEV_SAMP", "STDDEV", "stddev_samp"),
      ("`vArIaNcE`", "`VAR_SAMP`", "var_samp"),
    ] {
    let expected = statistical_alias_reuse_expected(function_name)
    check_statistical_program(expected)
    let actual = match
      compile(
        @query.parse_query(
          "SELECT DISTINCT " +
          selected +
          "(amount) AS v FROM orders ORDER BY " +
          ordered +
          "(amount)",
          syntax_limits(),
        ).unwrap(),
        values_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedOrdering) =>
        fail(
          "the installed statistical alias is not recognized as the selected aggregate",
        )
      Err(_) => fail("unexpected refusal of an equivalent statistical alias")
    }
    assert_eq(semantic(actual), semantic(expected))
    check_statistical_program(actual)
  }
}

///|
// DISTINCT cannot restore an unselected input expression. The adopted
// semantic refusal is InvalidQuery, rather than an unimplemented ORDER path.
test "statistical aliases do not reuse different arguments functions filters or slots" {
  for
    text in [
      "SELECT DISTINCT VARIANCE(amount) AS v FROM orders ORDER BY VAR_SAMP(amount + 1)",
      "SELECT DISTINCT VARIANCE(amount) AS v FROM orders ORDER BY VAR_POP(amount)",
      "SELECT DISTINCT STDDEV(amount) AS v FROM orders ORDER BY STDDEV_POP(amount)",
      "SELECT DISTINCT VARIANCE(amount WHERE amount > 0) AS v FROM orders ORDER BY VAR_SAMP(amount WHERE amount > 1)",
      "SELECT DISTINCT 0 AS amount, VARIANCE(amount) AS v FROM orders ORDER BY VAR_SAMP(amount)",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=text,
    )
  }
}
