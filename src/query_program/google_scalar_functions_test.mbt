///|
// These are independently authored source-to-Program controls. Execution
// expectations live in the public Host tests; neither suite is live BigQuery.
fn google_scalar_literal_control(expression : String) -> @program.Program {
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
test "Google scalar spellings preserve complete independently checked Programs" {
  for
    (names, arguments, expression) in [
      (
        ["STARTS_WITH", "starts_with", "`StArTs_WiTh`"],
        "'😀é', '😀'",
        "{\"starts_with\":[{\"literal\":\"😀é\"},{\"literal\":\"😀\"}]}",
      ),
      (
        ["ENDS_WITH", "ends_with", "`EnDs_WiTh`"],
        "'é😀', '😀'",
        "{\"ends_with\":[{\"literal\":\"é😀\"},{\"literal\":\"😀\"}]}",
      ),
      (
        ["STARTS_WITH"],
        "'', ''",
        "{\"starts_with\":[{\"literal\":\"\"},{\"literal\":\"\"}]}",
      ),
      (
        ["ENDS_WITH"],
        "'', ''",
        "{\"ends_with\":[{\"literal\":\"\"},{\"literal\":\"\"}]}",
      ),
      (
        ["STARTS_WITH"],
        "NULL, ''",
        "{\"starts_with\":[{\"literal\":null},{\"literal\":\"\"}]}",
      ),
      (
        ["ENDS_WITH"],
        "'', NULL",
        "{\"ends_with\":[{\"literal\":\"\"},{\"literal\":null}]}",
      ),
      (["SIGN", "sign", "`SiGn`"], "-2.3", "{\"sign\":{\"literal\":-2.3}}"),
      (["SIGN"], "0", "{\"sign\":{\"literal\":0}}"),
      (["SIGN"], "2.3", "{\"sign\":{\"literal\":2.3}}"),
      (["SIGN"], "NULL", "{\"sign\":{\"literal\":null}}"),
    ] {
    let expected = google_scalar_literal_control(expression)
    for name in names {
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
          NeedsInputs(_) => fail("literal scalar control needs no acquisition")
          Rejected(issue) => raise @check.diagnostic_cause(issue)
        }
      }
    }
  }
}

///|
test "Google scalar SQL and Pipe calls match one independent field Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","derive":{"aql_query_expr_0":{"starts_with":[{"field":"status"},{"literal":"op"}]},"aql_query_expr_1":{"ends_with":[{"field":"status"},{"literal":"en"}]},"aql_query_expr_2":{"sign":{"field":"amount"}}}},{"select":[{"starts":"aql_query_expr_0"},{"ends":"aql_query_expr_1"},{"direction":"aql_query_expr_2"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["starts","ends","direction"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT STARTS_WITH(status, 'op') AS starts, ENDS_WITH(status, 'en') AS ends, SIGN(amount) AS direction FROM orders",
      "FROM orders |> SELECT STARTS_WITH(status, 'op') AS starts, ENDS_WITH(status, 'en') AS ends, SIGN(amount) AS direction",
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
        NeedsInputs(_) => fail("typed field control must be statically closed")
        Rejected(issue) => raise @check.diagnostic_cause(issue)
      }
    }
  }
}

///|
test "Google scalar calls refuse missing and extra arguments before admission" {
  for
    expression in [
      "STARTS_WITH()", "STARTS_WITH('a')", "STARTS_WITH('a', 'b', 'c')", "ENDS_WITH()",
      "ENDS_WITH('a')", "ENDS_WITH('a', 'b', 'c')", "SIGN()", "SIGN(1, 2)",
    ] {
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
test "Google scalar calls retain ordinary type refusals even beside NULL" {
  for
    expression in [
      "STARTS_WITH(1, '1')", "STARTS_WITH('1', 1)", "STARTS_WITH(NULL, 1)", "ENDS_WITH(TRUE, 'true')",
      "ENDS_WITH('true', TRUE)", "ENDS_WITH(1, NULL)", "SIGN('1')", "SIGN(TRUE)",
      "SIGN(CAST('1.25' AS DECIMAL(8,3)))",
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
test "Google scalar parameter contracts admit nullable values and reject wrong bindings" {
  let declarations = @parameters.read_declarations(
    Some(
      @wire.admit(
        @source.parse_json(
          "{\"p\":{\"type\":\"string\",\"nullable\":true},\"q\":{\"type\":\"string\",\"nullable\":false},\"n\":{\"type\":\"number\",\"nullable\":true}}",
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
      "SELECT STARTS_WITH(@p, @q) AS starts, ENDS_WITH(@q, @p) AS ends, SIGN(@n) AS direction",
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
      ("{\"p\":null,\"q\":\"\",\"n\":null}", true),
      ("{\"p\":\"é\",\"q\":\"é\",\"n\":-2.3}", true),
      ("{\"p\":1,\"q\":\"\",\"n\":0}", false),
      ("{\"p\":\"\",\"q\":null,\"n\":0}", false),
      ("{\"p\":\"\",\"q\":\"\",\"n\":\"1\"}", false),
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
