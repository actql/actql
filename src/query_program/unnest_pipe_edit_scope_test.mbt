///|
fn unnest_edit_expected(tail : String, fields : String) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"items":{"type":"array","nullable":true,"max_items":4,"items":{"type":"object","nullable":true,"fields":{"element":{"type":"number","nullable":true},"id":{"type":"number","nullable":false}}}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"derive":{"aql_unnest_field_6":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"element"}},"aql_unnest_field_7":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"id"}}}},
    ) +
    tail +
    (
      #|],"results":{"rows":{"from":"aql_gen_0","fields":
    ) +
    fields +
    (
      #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "UNNEST SET replaces the whole value-table column before star expansion" {
  let expected = unnest_edit_expected(
    "{\"derive\":{\"aql_pipe_set_5\":{\"literal\":100}}},{\"sort\":[{\"field\":\"aql_unnest_offset_5\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"element\":\"aql_pipe_set_5\"},{\"position\":\"aql_unnest_offset_5\"}],\"as\":\"aql_gen_0\"}",
    "[\"element\",\"position\"]",
  )
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(unnest_value_cursor("{\"items\":[]}")),
      check_limits(),
    )
    is Checked(_),
  )
  let actual = compile(
    @query.parse_query(
      "FROM UNNEST(@items) element WITH OFFSET position |> SET element = 100 |> SELECT * |> ORDER BY position",
      syntax_limits(),
    ).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(unnest_receiver_parameters()),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "UNNEST implicit fields are not Pipe edit column targets" {
  for operation in ["SET id = 100", "DROP id", "RENAME id AS next"] {
    assert_true(
      compile(
        @query.parse_query(
          "FROM UNNEST(@items) element WITH OFFSET position |> " +
          operation +
          " |> SELECT position",
          syntax_limits(),
        ).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(unnest_receiver_parameters()),
        },
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=operation,
    )
  }
}

///|
test "UNNEST DROP removes the whole value table and its exposed fields" {
  let expected = unnest_edit_expected(
    "{\"sort\":[{\"field\":\"aql_unnest_offset_5\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"position\":\"aql_unnest_offset_5\"}],\"as\":\"aql_gen_0\"}",
    "[\"position\"]",
  )
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(unnest_value_cursor("{\"items\":[]}")),
      check_limits(),
    )
    is Checked(_),
  )
  let actual = compile(
    @query.parse_query(
      "FROM UNNEST(@items) element WITH OFFSET position |> DROP element |> SELECT * |> ORDER BY position",
      syntax_limits(),
    ).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(unnest_receiver_parameters()),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  assert_true(semantic(actual).contains("\"fields\":[\"position\"]"))
  assert_false(semantic(actual).contains("\"fields\":[\"id\",\"position\"]"))
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(unnest_value_cursor("{\"items\":[]}")),
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "UNNEST whole-value edits preserve empty object placement and script checking" {
  let declarations = parameter_reference_declarations(
    "{\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":4,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{}}}}",
  )
  for range_name in ["element", "row", "`element`"] {
    let actual = compile_query_script(
      @query.parse_query_script(
        "FROM UNNEST(@items) " +
        range_name +
        " WITH OFFSET position |> SET " +
        range_name +
        " = 100 |> SELECT * |> ORDER BY position",
        syntax_limits(),
      ).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(declarations),
      },
      construction_limits(),
    ).unwrap()
    let name = if range_name == "row" { "row" } else { "element" }
    assert_true(
      semantic(actual).contains("\"fields\":[\"" + name + "\",\"position\"]"),
    )
    match
      @check.check_parsed(
        actual,
        check_environment(),
        Some(unnest_value_cursor("{\"items\":[{},null]}")),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the declared parameter and ordinary values are closed")
    }
  }
}
