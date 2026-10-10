///|
// Complete controls are independently authored, not compiler-derived. Public
// Host tests separately establish finite-number results and schema contracts.
fn round_trunc_literal_control(expression : String) -> @program.Program {
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
test "unary ROUND and TRUNC preserve complete independent literal Programs" {
  for
    (names, op) in [
      (["ROUND", "round", "`RoUnD`"], "round"),
      (["TRUNC", "trunc", "`TrUnC`"], "trunc"),
    ] {
    for
      (argument, operand) in [
        ("2.5", "{\"literal\":2.5}"),
        ("-2.5", "{\"literal\":-2.5}"),
        ("0.49999999999999994", "{\"literal\":0.49999999999999994}"),
        ("4503599627370495.5", "{\"literal\":4503599627370495.5}"),
        ("1.7976931348623157e308", "{\"literal\":1.7976931348623157e308}"),
        ("NULL", "{\"literal\":null}"),
      ] {
      let expected = round_trunc_literal_control(
        "{\"" + op + "\":" + operand + "}",
      )
      for name in names {
        let source = "SELECT " + name + "(" + argument + ") AS value"
        let actual = compile(
          @query.parse_query(source, syntax_limits()).unwrap(),
          { ..fixture_context(), inputs: [], },
          construction_limits(),
        ).unwrap()
        assert_eq(semantic(actual), semantic(expected), msg=source)
        for program in [expected, actual] {
          match
            @check.check_parsed(
              program,
              check_environment(),
              None,
              check_limits(),
            ) {
            Checked(_) => ()
            NeedsInputs(_) =>
              fail("literal unary rounding needs no acquisition")
            Rejected(issue) => raise @check.diagnostic_cause(issue)
          }
        }
      }
    }
  }
}

///|
test "ROUND and TRUNC SQL and Pipe field calls match an independent Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","derive":{"aql_query_expr_0":{"round":{"field":"amount"}},"aql_query_expr_1":{"trunc":{"field":"amount"}}}},{"select":[{"rounded":"aql_query_expr_0"},{"truncated":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["rounded","truncated"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT ROUND(amount) AS rounded, TRUNC(amount) AS truncated FROM orders",
      "FROM orders |> SELECT ROUND(amount) AS rounded, TRUNC(amount) AS truncated",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      fixture_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
    for program in [expected, actual] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        NeedsInputs(_) => fail("typed rounding fields need no acquisition")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}

///|
test "ROUND and TRUNC refuse optional N and rounding mode before checking" {
  for name in ["ROUND", "TRUNC"] {
    for argument in ["", "2.5, 0", "2.5, 0, 'ROUND_HALF_EVEN'"] {
      let source = "SELECT " + name + "(" + argument + ") AS value"
      assert_true(
        compile(
          @query.parse_query(source, syntax_limits()).unwrap(),
          { ..fixture_context(), inputs: [], },
          construction_limits(),
        )
        is Err(Expression({ issue: @expression.InvalidArguments, .. })),
        msg=source,
      )
    }
  }
}

///|
test "ROUND and TRUNC reject strings Unicode booleans and decimals" {
  for name in ["ROUND", "TRUNC"] {
    for
      argument in ["'2.5'", "'😀é'", "TRUE", "CAST('1.25' AS DECIMAL(8,3))"] {
      let source = "SELECT " + name + "(" + argument + ") AS value"
      let actual = compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_true(
        @check.check_parsed(actual, check_environment(), None, check_limits())
        is Rejected(_),
        msg=source,
      )
    }
  }
}

///|
test "ROUND and TRUNC parameter contracts admit NULL and reject invalid bindings" {
  let declarations = @parameters.read_declarations(
    Some(
      @wire.admit(
        @source.parse_json(
          "{\"p\":{\"type\":\"number\",\"nullable\":true},\"q\":{\"type\":\"number\",\"nullable\":false}}",
          construction_limits().source.source,
        ).unwrap(),
        construction_limits().source.tree,
      ).unwrap(),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "SELECT ROUND(@p) AS nullable_round, TRUNC(@p) AS nullable_trunc, ROUND(@q) AS required_round, TRUNC(@q) AS required_trunc",
      syntax_limits(),
    ).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(declarations),
    },
    construction_limits(),
  ).unwrap()
  for
    (body, accepted) in [
      ("{\"p\":null,\"q\":2.5}", true),
      ("{\"p\":-2.5,\"q\":2.5}", true),
      ("{\"p\":\"😀é\",\"q\":1}", false),
      ("{\"p\":1,\"q\":\"😀é\"}", false),
      ("{\"p\":true,\"q\":1}", false),
      ("{\"p\":1,\"q\":null}", false),
    ] {
    let supplied = @wire.admit(
      @source.parse_json(body, construction_limits().source.source).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    let checked = @check.check_parsed(
      actual,
      check_environment(),
      Some(supplied),
      check_limits(),
    )
    if accepted {
      assert_true(checked is Checked(_), msg=body)
    } else {
      assert_true(checked is Rejected(_), msg=body)
    }
  }
}

///|
test "unary rounding preserves demanded and skipped division children" {
  for
    (source, expression) in [
      (
        "ROUND(1 / 0)", "{\"round\":{\"divide\":[{\"literal\":1},{\"literal\":0}]}}",
      ),
      (
        "TRUNC(1 / 0)", "{\"trunc\":{\"divide\":[{\"literal\":1},{\"literal\":0}]}}",
      ),
      (
        "ROUND(IF(TRUE, -2.5, 1 / 0))", "{\"round\":{\"if\":[{\"literal\":true},{\"literal\":-2.5},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}}",
      ),
      (
        "IF(TRUE, 7, TRUNC(1 / 0))", "{\"if\":[{\"literal\":true},{\"literal\":7},{\"trunc\":{\"divide\":[{\"literal\":1},{\"literal\":0}]}}]}",
      ),
    ] {
    let expected = round_trunc_literal_control(expression)
    let actual = compile(
      @query.parse_query("SELECT " + source + " AS value", syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
    for program in [expected, actual] {
      assert_true(
        @check.check_parsed(program, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}
