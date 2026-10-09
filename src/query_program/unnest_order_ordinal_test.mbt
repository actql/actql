///|
fn unnest_ordinal_expected() -> @program.Program {
  unnest_ordinal_tail_expected(
    "{\"sort\":[{\"field\":\"aql_unnest_offset_5\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"id\":\"aql_unnest_field_6\"},{\"label\":\"aql_unnest_field_7\"},{\"position\":\"aql_unnest_offset_5\"}],\"as\":\"aql_gen_0\"}",
    "[\"id\",\"label\",\"position\"]",
  )
}

///|
fn unnest_ordinal_tail_expected(
  tail : String,
  fields : String,
) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"derive":{"aql_unnest_field_6":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"id"}},"aql_unnest_field_7":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"label"}}}},
    ) +
    tail +
    "],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":" +
    fields +
    "}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "SELECT supplies authored output ordinals instead of the input value table" {
  let expected = unnest_ordinal_tail_expected(
    "{\"sort\":[{\"field\":\"aql_unnest_offset_5\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"position\":\"aql_unnest_offset_5\"},{\"id\":\"aql_unnest_field_6\"},{\"label\":\"aql_unnest_field_7\"}],\"as\":\"aql_gen_0\"}",
    "[\"position\",\"id\",\"label\"]",
  )
  let actual = unnest_struct_compile(
    "FROM UNNEST(@items) element WITH OFFSET position |> SELECT position, element.* |> ORDER BY 1",
  )
  assert_eq(semantic(actual), semantic(expected))
  let expanded = unnest_ordinal_tail_expected(
    "{\"sort\":[{\"field\":\"aql_unnest_field_7\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"id\":\"aql_unnest_field_6\"},{\"label\":\"aql_unnest_field_7\"},{\"position\":\"aql_unnest_offset_5\"}],\"as\":\"aql_gen_0\"}",
    "[\"id\",\"label\",\"position\"]",
  )
  assert_eq(
    semantic(
      unnest_struct_compile(
        "FROM UNNEST(@items) element WITH OFFSET position |> SELECT element.*, position |> ORDER BY 2",
      ),
    ),
    semantic(expanded),
  )
}

///|
test "an ordinal addresses its slot despite an equal implicit member name" {
  let expected = unnest_ordinal_tail_expected(
    "{\"sort\":[{\"field\":\"aql_unnest_offset_5\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"original\":\"aql_unnest_field_6\"},{\"position\":\"aql_unnest_offset_5\"}],\"as\":\"aql_gen_0\"}",
    "[\"original\",\"position\"]",
  )
  assert_eq(
    semantic(
      unnest_struct_compile(
        "FROM UNNEST(@items) element WITH OFFSET id |> ORDER BY 2 |> SELECT element.id AS original, id AS position",
      ),
    ),
    semantic(expected),
  )
}

///|
test "whole-column SET and DROP update actual ordinal slots" {
  let replacement = unnest_ordinal_tail_expected(
    "{\"derive\":{\"aql_pipe_set_5\":{\"literal\":100}}},{\"sort\":[{\"field\":\"aql_pipe_set_5\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"element\":\"aql_pipe_set_5\"},{\"position\":\"aql_unnest_offset_5\"}],\"as\":\"aql_gen_0\"}",
    "[\"element\",\"position\"]",
  )
  assert_eq(
    semantic(
      unnest_struct_compile(
        "FROM UNNEST(@items) element WITH OFFSET position |> SET element = 100 |> ORDER BY 1 |> SELECT *",
      ),
    ),
    semantic(replacement),
  )
  let dropped = unnest_ordinal_tail_expected(
    "{\"sort\":[{\"field\":\"aql_unnest_offset_5\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"position\":\"aql_unnest_offset_5\"}],\"as\":\"aql_gen_0\"}",
    "[\"position\"]",
  )
  assert_eq(
    semantic(
      unnest_struct_compile(
        "FROM UNNEST(@items) element WITH OFFSET position |> DROP element |> ORDER BY 1 |> SELECT position",
      ),
    ),
    semantic(dropped),
  )
}

///|
test "Pipe ORDER ordinals count an object value table once before projection" {
  let expected = unnest_ordinal_expected()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(
        unnest_value_cursor(
          "{\"items\":[{\"id\":2,\"label\":\"z\"},null,{\"id\":1,\"label\":\"a\"}]}",
        ),
      ),
      check_limits(),
    )
    is Checked(_),
  )
  for ordinal in ["2", "(2)", "+2"] {
    let actual = unnest_struct_compile(
      "FROM UNNEST(@items) element WITH OFFSET position |> ORDER BY " +
      ordinal +
      " |> SELECT element.*, position",
    )
    assert_eq(semantic(actual), semantic(expected), msg=ordinal)
  }
}

///|
test "implicit object fields do not extend the ORDER ordinal column count" {
  for
    source in [
      "FROM UNNEST(@items) element WITH OFFSET position |> ORDER BY 3 |> SELECT element.*, position",
      "FROM UNNEST(@items) element |> ORDER BY 2 |> SELECT element.*",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(unnest_struct_parameters()),
        },
        construction_limits(),
      )
      is Err(UnsupportedOrdering),
      msg=source,
    )
  }
}
