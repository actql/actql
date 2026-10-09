///|
fn unnest_receiver_parameters() -> @parameters.Declarations {
  @parameters.read_declarations(
    Some(
      unnest_value_cursor(
        (
          #|{"items":{"type":"array","nullable":true,"max_items":4,"items":{"type":"object","nullable":true,"fields":{"element":{"type":"number","nullable":true},"id":{"type":"number","nullable":false}}}}}
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
test "UNNEST receiver collision public sources retain ordinary checking" {
  for
    text in [
      "SELECT (element) AS original, (element).element AS field_value, position FROM UNNEST(@items) element WITH OFFSET position ORDER BY position",
      "SELECT element AS original, element.element AS field_value, position FROM UNNEST(@items) element WITH OFFSET position WHERE element IS NOT NULL ORDER BY position",
      "SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position",
      "SELECT element.*, position FROM UNNEST(@items) element WITH OFFSET position ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> SET element = 100 |> SELECT element AS original, element.element AS field_value, position |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> SET element = 100 |> SELECT * |> ORDER BY position",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(unnest_receiver_parameters()),
      },
      construction_limits(),
    ).unwrap()
    for
      values in [
        "[]", "null", "[{\"element\":null,\"id\":2},null,{\"element\":9,\"id\":1},{\"element\":9,\"id\":1}]",
      ] {
      assert_true(
        @check.check_parsed(
          actual,
          check_environment(),
          Some(unnest_value_cursor("{\"items\":" + values + "}")),
          check_limits(),
        )
        is Checked(_),
        msg=text,
      )
    }
  }
}

///|
test "UNNEST receiver collision does not revive a projected range" {
  let result = compile(
    @query.parse_query(
      "FROM UNNEST(@items) element |> SELECT id |> WHERE element IS NOT NULL",
      syntax_limits(),
    ).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(unnest_receiver_parameters()),
    },
    construction_limits(),
  )
  assert_true(
    result is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "UNNEST range receiver wins over its same-named exposed field" {
  // This complete Program is authored independently: the range selects the
  // original object; the qualified column selects its nullable numeric field.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"items":{"type":"array","nullable":true,"max_items":4,"items":{"type":"object","nullable":true,"fields":{"element":{"type":"number","nullable":true},"id":{"type":"number","nullable":false}}}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"derive":{"aql_unnest_field_6":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"element"}},"aql_unnest_field_7":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"id"}}}},{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"original":"aql_unnest_element_4"},{"field_value":"aql_unnest_field_6"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["original","field_value","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(
        unnest_value_cursor(
          "{\"items\":[{\"element\":null,\"id\":2},null,{\"element\":9,\"id\":1}]}",
        ),
      ),
      check_limits(),
    )
    is Checked(_),
  )
  for
    text in [
      "SELECT element AS original, element.element AS field_value, position FROM UNNEST(@items) element WITH OFFSET position ORDER BY position",
      "SELECT `ELEMENT` AS original, `ELEMENT`.`ELEMENT` AS field_value, position FROM UNNEST(@items) `element` WITH OFFSET position ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> SELECT element AS original, element.element AS field_value, position |> ORDER BY position",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(unnest_receiver_parameters()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}
