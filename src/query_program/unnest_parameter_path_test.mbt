///|
fn unnest_parameter_path_declarations() -> @parameters.Declarations {
  @parameters.read_declarations(
    Some(
      unnest_value_cursor(
        (
          #|{"payload":{"type":"object","nullable":true,"fields":{"nested":{"type":"object","nullable":true,"fields":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}}}}}}}}
        ),
      ),
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
test "parameter property UNNEST star refuses unknown contracts and bounded work" {
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(unnest_parameter_path_declarations()),
  }
  for
    (text, expected) in [
      (
        "SELECT * FROM UNNEST(@payload.nested.missing) element",
        @typing.UnknownField("missing"),
      ),
      (
        "SELECT * FROM UNNEST(@missing.nested.items) element",
        @typing.UnknownParameter("missing"),
      ),
    ] {
    match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        context,
        construction_limits(),
      ) {
      Err(ExpressionTyping(issue)) => assert_eq(issue.kind, expected, msg=text)
      _ => fail("the common typing cause must survive: " + text)
    }
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * FROM UNNEST(@payload.nested) element",
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.InvalidArguments, .. })),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * FROM UNNEST(@payload.nested.items) element",
        syntax_limits(),
      ).unwrap(),
      context,
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: @expression.WorkLimit, .. })),
  )
}

///|
test "parameter property UNNEST star matches an independent nullable Program" {
  // This expectation is authored from ordinary parameter, property and UNNEST
  // contracts. It does not sample values or call the Frontend to infer fields.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"payload":{"type":"object","nullable":true,"fields":{"nested":{"type":"object","nullable":true,"fields":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}}}}}}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":{"property":{"value":{"property":{"value":{"$param":"payload"},"name":"nested"}},"name":"items"}}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"derive":{"aql_unnest_field_6":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"id"}},"aql_unnest_field_7":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"label"}}}},{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"id":"aql_unnest_field_6"},{"label":"aql_unnest_field_7"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","label","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(unnest_parameter_path_declarations()),
  }
  for
    values in [
      "null", "{\"nested\":null}", "{\"nested\":{\"items\":null}}", "{\"nested\":{\"items\":[]}}",
      "{\"nested\":{\"items\":[{\"id\":2,\"label\":null},null,{\"id\":2,\"label\":null}]}}",
    ] {
    assert_true(
      @check.check_parsed(
        expected,
        check_environment(),
        Some(unnest_value_cursor("{\"payload\":" + values + "}")),
        check_limits(),
      )
      is Checked(_),
      msg=values,
    )
  }
  for
    text in [
      "SELECT element.*, position FROM UNNEST(@payload.nested.items) element WITH OFFSET position ORDER BY position",
      "SELECT element.*, position FROM UNNEST(@PAYLOAD.nested.items) element WITH OFFSET position ORDER BY position",
      "SELECT element.*, position FROM UNNEST(@`PAYLOAD`.nested.items) element WITH OFFSET position ORDER BY position",
      "SELECT element.*, position FROM UNNEST(@payload.NESTED.ItEmS) element WITH OFFSET position ORDER BY position",
      "SELECT element.*, position FROM UNNEST(@payload.`NESTED`.`ITEMS`) element WITH OFFSET position ORDER BY position",
      "SELECT * FROM UNNEST(((@payload).nested).`items`) element WITH OFFSET position ORDER BY position",
      "FROM UNNEST(@payload.nested.items) element WITH OFFSET position |> SELECT element.*, position |> ORDER BY position",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}

///|
test "UNNEST property binding refuses case-fold collisions without inventing a field" {
  let declarations = @parameters.read_declarations(
    Some(
      unnest_value_cursor(
        (
          #|{"payload":{"type":"object","nullable":true,"fields":{"nested":{"type":"object","nullable":true,"fields":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":false}}}},"NESTED":{"type":"object","nullable":true,"fields":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":false}}}}}}}
        ),
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  assert_true(
    compile(
      @query.parse_query(
        "SELECT element FROM UNNEST(@payload.nested.items) element",
        syntax_limits(),
      ).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(declarations),
      },
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
}
