///|
// Complete controls are authored independently of the frontend. Public Host
// tests separately assert results and schemas; neither suite is live BigQuery.
fn strpos_literal_control(left : String, right : String) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"strpos":[
    ) +
    left +
    "," +
    right +
    (
      #|]}}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "STRPOS spellings preserve independent Programs and exact Unicode operands" {
  for
    (arguments, left, right) in [
      ("'😀a', 'a'", "{\"literal\":\"😀a\"}", "{\"literal\":\"a\"}"),
      ("'e\\u0301x', 'x'", "{\"literal\":\"éx\"}", "{\"literal\":\"x\"}"),
      ("'é', 'e\\u0301'", "{\"literal\":\"é\"}", "{\"literal\":\"é\"}"),
      (
        "'a\\u0000b', '\\u0000b'", "{\"literal\":\"a\\u0000b\"}", "{\"literal\":\"\\u0000b\"}",
      ),
      ("'', ''", "{\"literal\":\"\"}", "{\"literal\":\"\"}"),
      ("NULL, ''", "{\"literal\":null}", "{\"literal\":\"\"}"),
      ("'', NULL", "{\"literal\":\"\"}", "{\"literal\":null}"),
      ("NULL, NULL", "{\"literal\":null}", "{\"literal\":null}"),
    ] {
    let expected = strpos_literal_control(left, right)
    for name in ["STRPOS", "strpos", "`StRpOs`"] {
      let source = "SELECT " + name + "(" + arguments + ") AS value"
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
          NeedsInputs(_) => fail("literal STRPOS must not acquire inputs")
          Rejected(issue) => raise @check.diagnostic_cause(issue)
        }
      }
    }
  }
}

///|
test "STRPOS SQL and Pipe field calls match one complete independent Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","derive":{"aql_query_expr_0":{"strpos":[{"field":"status"},{"literal":"en"}]},"aql_query_expr_1":{"strpos":[{"literal":"open"},{"field":"status"}]}}},{"select":[{"position":"aql_query_expr_0"},{"reverse_position":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["position","reverse_position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT STRPOS(status, 'en') AS position, STRPOS('open', status) AS reverse_position FROM orders",
      "FROM orders |> SELECT STRPOS(status, 'en') AS position, STRPOS('open', status) AS reverse_position",
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
        NeedsInputs(_) => fail("typed STRPOS fields need no acquisition")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}

///|
test "STRPOS refuses missing and extra arguments before ordinary checking" {
  for expression in ["STRPOS()", "STRPOS('a')", "STRPOS('a', 'b', 'c')"] {
    let source = "SELECT " + expression + " AS value"
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

///|
test "STRPOS preserves ordinary type refusals even beside NULL" {
  for
    expression in [
      "STRPOS(1, '1')", "STRPOS('1', 1)", "STRPOS(TRUE, 'true')", "STRPOS('true', TRUE)",
      "STRPOS(NULL, 1)", "STRPOS(TRUE, NULL)", "STRPOS(CAST('1' AS DECIMAL(8,3)), '1')",
    ] {
    let source = "SELECT " + expression + " AS value"
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

///|
test "STRPOS parameter contracts admit NULL and reject invalid bindings" {
  let declarations = @parameters.read_declarations(
    Some(
      @wire.admit(
        @source.parse_json(
          "{\"p\":{\"type\":\"string\",\"nullable\":true},\"q\":{\"type\":\"string\",\"nullable\":false}}",
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
      "SELECT STRPOS(@p, @q) AS forward_position, STRPOS(@q, @p) AS reverse_position",
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
      ("{\"p\":null,\"q\":\"\"}", true),
      ("{\"p\":\"😀a\",\"q\":\"a\"}", true),
      ("{\"p\":1,\"q\":\"\"}", false),
      ("{\"p\":\"\",\"q\":null}", false),
      ("{\"p\":\"\",\"q\":true}", false),
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
test "STRPOS keeps demanded children in authored left-to-right order" {
  let demanded = "{\"if\":[{\"eq\":[{\"divide\":[{\"literal\":1},{\"literal\":0}]},{\"literal\":0}]},{\"literal\":\"x\"},{\"literal\":\"y\"}]}"
  for
    (arguments, left, right) in [
      ("NULL, IF(1 / 0 = 0, 'x', 'y')", "{\"literal\":null}", demanded),
      ("IF(1 / 0 = 0, 'x', 'y'), NULL", demanded, "{\"literal\":null}"),
    ] {
    let expected = strpos_literal_control(left, right)
    let actual = compile(
      @query.parse_query(
        "SELECT STRPOS(" + arguments + ") AS value",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [expected, actual] {
      assert_true(
        @check.check_parsed(program, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}
