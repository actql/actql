///|
test "source parameter spelling resolves to the independently declared Program name" {
  let expected = limit_parameter_expected()
  let context = {
    ..values_context(),
    parameter_declarations: Some(number_parameter_declarations()),
  }
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    )
    is Checked(_),
    msg="the independently authored p references satisfy the ordinary checker",
  )
  let control = compile(
    @query.parse_query(
      "SELECT id, amount FROM orders ORDER BY id LIMIT @p OFFSET @p",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(control), semantic(expected))
  for
    text in [
      "SELECT id, amount FROM orders ORDER BY id LIMIT @P OFFSET @P", "SELECT id, amount FROM orders ORDER BY id LIMIT @`P` OFFSET @`\\x50`",
      "FROM orders |> SELECT id, amount |> ORDER BY id |> LIMIT @P OFFSET @`P`",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(analytic_frame_parameter_values("1")),
        check_limits(),
      )
      is Checked(_),
      msg=text,
    )
  }
}

///|
test "scalar parameter binding preserves the complete independent Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"p":{"type":"number"}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"$param":"p"}}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    )
    is Checked(_),
  )
  for
    source in [
      "SELECT @p AS value", "SELECT @P AS value", "SELECT @`\\x50` AS value",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
  }
}

///|
test "frame parameters bind through the existing analytic boundary" {
  let expected = analytic_frame_parameter_expected()
  let actual = compile(
    @query.parse_query(
      "SELECT id, FIRST_VALUE(amount) OVER (ORDER BY id ROWS BETWEEN @P PRECEDING AND @`P` FOLLOWING) AS first, LAST_VALUE(amount) OVER (ORDER BY id ROWS BETWEEN @`\\x50` PRECEDING AND @p FOLLOWING) AS last FROM orders ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    {
      ..values_context(),
      parameter_declarations: Some(number_parameter_declarations()),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
fn parameter_reference_declarations(text : String) -> @parameters.Declarations {
  @parameters.read_declarations(
    Some(
      @wire.admit(
        @source.parse_json(text, construction_limits().source.source).unwrap(),
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
}

///|
test "declared spelling values and literal data are not rewritten" {
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(
      parameter_reference_declarations("{\"P\":{\"type\":\"number\"}}"),
    ),
  }
  let actual = compile(
    @query.parse_query("SELECT @p AS value, 'p' AS text", syntax_limits()).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  let source = semantic(actual)
  assert_true(source.contains("\"params\":{\"P\":{\"type\":\"number\"}}"))
  assert_true(source.contains("\"$param\":\"P\""))
  assert_true(source.contains("\"literal\":\"p\""))
  let values = @wire.admit(
    @source.parse_json("{\"P\":7}", construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(values),
      check_limits(),
    )
    is Checked(_),
  )
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(analytic_frame_parameter_values("7")),
      check_limits(),
    )
    is Rejected(_),
    msg="machine value keys still match the exact declaration",
  )
}

///|
test "ambiguous declarations and binding work remain bounded" {
  let query = @query.parse_query("SELECT @p AS value", syntax_limits()).unwrap()
  assert_true(
    compile(
      query,
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(
          parameter_reference_declarations(
            "{\"p\":{\"type\":\"number\"},\"P\":{\"type\":\"number\"}}",
          ),
        ),
      },
      construction_limits(),
    )
    is Err(InvalidContext),
  )
  assert_true(
    compile(
      query,
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(number_parameter_declarations()),
      },
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: WorkLimit, .. })),
  )
}

///|
test "DISTINCT ORDER reuses the evaluated expression with an equivalent parameter name" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","params":{"p":{"type":"number"}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_query_expr_0":{"add":[{"field":"x"},{"$param":"p"}]}}},{"select":[{"score":"aql_query_expr_0"}]},{"distinct":["score"]},{"sort":[{"field":"score","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    )
    is Checked(_),
  )
  for
    source in [
      "SELECT DISTINCT x + @p AS score FROM t ORDER BY x + @P", "SELECT DISTINCT x + @`P` AS score FROM t ORDER BY x + @p",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      {
        ..join_order_context(),
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
  }
}
