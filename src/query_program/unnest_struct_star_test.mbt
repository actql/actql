///|
fn unnest_struct_parameters() -> @parameters.Declarations {
  @parameters.read_declarations(
    Some(
      unnest_value_cursor(
        (
          #|{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}}}}
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
fn unnest_struct_compile(text : String) -> @program.Program {
  compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(unnest_struct_parameters()),
    },
    construction_limits(),
  ).unwrap()
}

///|
test "STRUCT UNNEST stars match an independent nullable property Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"derive":{"aql_unnest_field_6":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"id"}},"aql_unnest_field_7":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"label"}}}},{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"id":"aql_unnest_field_6"},{"label":"aql_unnest_field_7"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","label","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    values in [
      "[]", "null", "[{\"id\":2,\"label\":null},null,{\"id\":2,\"label\":null}]",
    ] {
    assert_true(
      @check.check_parsed(
        expected,
        check_environment(),
        Some(unnest_value_cursor("{\"items\":" + values + "}")),
        check_limits(),
      )
      is Checked(_),
    )
  }
  for
    text in [
      "SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position",
      "SELECT element.*, position FROM UNNEST((@items)) element WITH OFFSET position ORDER BY position",
      "SELECT id, element.label, position FROM UNNEST(@items) element WITH OFFSET position ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> SELECT * |> ORDER BY position",
    ] {
    assert_eq(
      semantic(unnest_struct_compile(text)),
      semantic(expected),
      msg=text,
    )
  }
  // Common object fields have canonical order, independently of author JSON
  // member order. This is not the missing ordered GoogleSQL STRUCT contract.
  let reversed = @parameters.read_declarations(
    Some(
      unnest_value_cursor(
        (
          #|{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"label":{"type":"string","nullable":true},"id":{"type":"number","nullable":false}}}}}
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
  let actual = compile(
    @query.parse_query(
      "SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], parameter_declarations: Some(reversed), },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "STRUCT value-table receiver stays private and ends at AS or SELECT" {
  for
    text in [
      "SELECT element, position FROM UNNEST(@items) element WITH OFFSET position ORDER BY position",
      "SELECT element AS original, id, position FROM UNNEST(@items) element WITH OFFSET position WHERE element.id IS NOT NULL ORDER BY position",
      "SELECT element.* EXCEPT (label), position FROM UNNEST(@items) element WITH OFFSET position WHERE id IS NOT NULL ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> SET id = id + 10 |> SELECT id AS current, element.id AS original, position |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> DROP label |> AS current |> SELECT current.* |> ORDER BY position",
      "SELECT id FROM UNNEST(@items) element WITH OFFSET position ORDER BY element.label NULLS LAST, position",
      "SELECT id, COUNT(*) AS n FROM UNNEST(@items) element GROUP BY id ORDER BY id",
    ] {
    assert_true(
      @check.check_parsed(
        unnest_struct_compile(text),
        check_environment(),
        Some(
          unnest_value_cursor(
            "{\"items\":[{\"id\":2,\"label\":null},null,{\"id\":2,\"label\":null}]}",
          ),
        ),
        check_limits(),
      )
      is Checked(_),
      msg=text,
    )
  }
  for
    text in [
      "FROM UNNEST(@items) element |> SELECT id |> WHERE element.label IS NULL",
      "FROM UNNEST(@items) element |> AS current |> WHERE element.id IS NULL", "FROM UNNEST(@items) element |> SELECT * |> WHERE element.id IS NULL",
    ] {
    let result = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(unnest_struct_parameters()),
      },
      construction_limits(),
    )
    assert_true(
      result is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
}
