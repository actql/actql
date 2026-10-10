///|
// Complete controls are independently authored, not compiler-derived. Public
// Host tests separately establish finite-number results and schema contracts.
fn safe_arithmetic_literal_control(expression : String) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":
    ) +
    expression +
    (
      #|}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "SAFE arithmetic SQL preserves complete independent Programs" {
  for
    (text, expression) in [
      ("SAFE_ADD(1, 2)", "{\"safe_add\":[{\"literal\":1},{\"literal\":2}]}"),
      (
        "SAFE_SUBTRACT(1, 2)", "{\"safe_subtract\":[{\"literal\":1},{\"literal\":2}]}",
      ),
      (
        "SAFE_MULTIPLY(1, 2)", "{\"safe_multiply\":[{\"literal\":1},{\"literal\":2}]}",
      ),
      (
        "SAFE_DIVIDE(1, 0)", "{\"safe_divide\":[{\"literal\":1},{\"literal\":0}]}",
      ),
      (
        "SAFE_NEGATE(-1.7976931348623157e308)", "{\"safe_negate\":{\"literal\":-1.7976931348623157e308}}",
      ),
      (
        "SAFE_DIVIDE(NULL, 1 / 0)", "{\"safe_divide\":[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
      ),
      (
        "IF(FALSE, SAFE_MULTIPLY(1 / 0, 2), 7)", "{\"if\":[{\"literal\":false},{\"safe_multiply\":[{\"divide\":[{\"literal\":1},{\"literal\":0}]},{\"literal\":2}]},{\"literal\":7}]}",
      ),
    ] {
    let expected = safe_arithmetic_literal_control(expression)
    let actual = compile(
      @query.parse_query("SELECT " + text + " AS value", syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
    for program in [expected, actual] {
      assert_true(
        @check.check_parsed(program, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}

///|
test "SAFE arithmetic wrong domains fail static checking before execution" {
  for
    name in [
      "SAFE_ADD", "SAFE_SUBTRACT", "SAFE_MULTIPLY", "SAFE_DIVIDE", "SAFE_NEGATE",
    ] {
    for operand in ["TRUE", "'2'", "'😀'", "CAST('1.25' AS DECIMAL(8,3))"] {
      let args = if name == "SAFE_NEGATE" { operand } else { "1, " + operand }
      let actual = compile(
        @query.parse_query(
          "SELECT " + name + "(" + args + ") AS value",
          syntax_limits(),
        ).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_true(
        @check.check_parsed(actual, check_environment(), None, check_limits())
        is Rejected(_),
      )
    }
  }
}
