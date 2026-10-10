///|
fn unnest_as_expected(
  struct_value : Bool,
  with_offset : Bool,
  tail_override? : String? = None,
  fields_override? : String? = None,
) -> @program.Program {
  let declarations = if struct_value {
    (
      #|{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}}}}
    )
  } else {
    (
      #|{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}}
    )
  }
  let index = if with_offset {
    ",\"with_index\":\"aql_unnest_offset_5\""
  } else {
    ""
  }
  let properties = if struct_value && with_offset {
    (
      #|,{"derive":{"aql_unnest_field_6":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"id"}},"aql_unnest_field_7":{"property":{"value":{"field":"aql_unnest_element_4"},"name":"label"}}}}
    )
  } else if struct_value {
    (
      #|,{"derive":{"aql_unnest_field_4":{"property":{"value":{"field":"aql_unnest_element_3"},"name":"id"}},"aql_unnest_field_5":{"property":{"value":{"field":"aql_unnest_element_3"},"name":"label"}}}}
    )
  } else {
    ""
  }
  let tail = if with_offset {
    (
      #|,{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"original":"aql_unnest_element_4"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}
    )
  } else if struct_value {
    (
      #|,{"sort":[{"field":"aql_unnest_field_4","dir":"asc","nulls":"last"}]},{"select":[{"original":"aql_unnest_element_3"},{"id":"aql_unnest_field_4"}],"as":"aql_gen_0"}
    )
  } else {
    (
      #|,{"filter":{"gt":[{"field":"aql_unnest_element_3"},{"literal":0}]}},{"sort":[{"field":"aql_unnest_element_3","dir":"asc","nulls":"first"}]},{"select":[{"value":"aql_unnest_element_3"}],"as":"aql_gen_0"}
    )
  }
  let fields = if with_offset {
    "[\"original\",\"position\"]"
  } else if struct_value {
    "[\"original\",\"id\"]"
  } else {
    "[\"value\"]"
  }
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"params\":" +
    declarations +
    (if with_offset {
      (
        #|,"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4"
      )
    } else {
      (
        #|,"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_2":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_2","as":"aql_unnest_element_3"
      )
    }) +
    index +
    "}}" +
    properties +
    tail_override.unwrap_or(tail) +
    "],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":" +
    fields_override.unwrap_or(fields) +
    "}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Pipe AS retains the scalar value table under its new range" {
  let expected = unnest_as_expected(false, false)
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(unnest_value_cursor("{\"items\":[2,null,1]}")),
      check_limits(),
    )
    is Checked(_),
  )
  let actual = compile(
    @query.parse_query(
      "FROM UNNEST(@items) element |> AS current |> WHERE current > 0 |> SELECT current AS value |> ORDER BY value",
      syntax_limits(),
    ).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(unnest_parameters()),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Pipe AS retains the whole object and its implicit member slots" {
  let expected = unnest_as_expected(true, false)
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
  let actual = unnest_struct_compile(
    "FROM UNNEST(@items) element |> AS current |> SELECT current AS original, id |> ORDER BY id NULLS LAST",
  )
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "multi-column Pipe AS keeps the former value as an ordinary whole column" {
  let expected = unnest_as_expected(true, true)
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
  for
    text in [
      "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> SELECT current.element AS original, position |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> SELECT element AS original, current.position AS position |> ORDER BY position",
    ] {
    assert_eq(
      semantic(unnest_struct_compile(text)),
      semantic(expected),
      msg=text,
    )
  }
}

///|
test "AS retains object star layout separately from ordinary whole columns" {
  let expected = unnest_as_expected(
    true,
    true,
    tail_override=Some(
      (
        #|,{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"id":"aql_unnest_field_6"},{"label":"aql_unnest_field_7"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}
      ),
    ),
    fields_override=Some("[\"id\",\"label\",\"position\"]"),
  )
  for
    text in [
      "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> SELECT * |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> SELECT current.* |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> AS first |> AS current |> SELECT current.* |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> RENAME element AS next |> SELECT * |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> RENAME element AS next |> SELECT current.* |> ORDER BY position",
    ] {
    assert_eq(
      semantic(unnest_struct_compile(text)),
      semantic(expected),
      msg=text,
    )
  }
}

///|
test "AS current whole columns can be renamed without reviving old ranges" {
  let expected = unnest_as_expected(true, true)
  for
    text in [
      "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> RENAME element AS next |> SELECT next AS original, position |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> RENAME element AS next |> SELECT current.element AS original, position |> ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> AS first |> AS current |> SELECT current.element AS original, position |> ORDER BY position",
    ] {
    assert_eq(
      semantic(unnest_struct_compile(text)),
      semantic(expected),
      msg=text,
    )
  }
}

///|
test "AS preserves scalar value-table kind across repeated aliases" {
  let expected = unnest_as_expected(false, false)
  for
    text in [
      "FROM UNNEST(@items) element |> AS first |> AS current |> WHERE current > 0 |> SELECT current AS value |> ORDER BY value",
      "FROM UNNEST(@items) element |> AS `Current` |> WHERE `CURRENT` > 0 |> SELECT current AS value |> ORDER BY value",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(unnest_parameters()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
  assert_true(
    compile(
      @query.parse_query(
        "FROM UNNEST(@items) element |> AS current |> RENAME current AS next |> SELECT next",
        syntax_limits(),
      ).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(unnest_parameters()),
      },
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
}

///|
test "AS does not authorize editing implicit object members" {
  for operation in ["SET id = 100", "DROP id", "RENAME id AS next"] {
    let text = "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> " +
      operation +
      " |> SELECT position"
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(unnest_struct_parameters()),
        },
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=text,
    )
  }
}

///|
test "AS cannot bypass the existing whole-object DISTINCT refusal" {
  for
    text in [
      "FROM UNNEST(@items) element |> AS current |> DISTINCT |> SELECT id", "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> DISTINCT |> SELECT id",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(unnest_struct_parameters()),
        },
        construction_limits(),
      )
      is Err(UnsupportedProjection),
      msg=text,
    )
  }
}

///|
test "AS captures qualified star before whole-column SET" {
  let expected = unnest_as_expected(
    true,
    true,
    tail_override=Some(
      (
        #|,{"derive":{"aql_pipe_set_5":{"literal":100}}},{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"id":"aql_unnest_field_6"},{"label":"aql_unnest_field_7"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}
      ),
    ),
    fields_override=Some("[\"id\",\"label\",\"position\"]"),
  )
  assert_eq(
    semantic(
      unnest_struct_compile(
        "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> SET element = 100 |> SELECT current.* |> ORDER BY position",
      ),
    ),
    semantic(expected),
  )
}

///|
test "AS whole-column DROP removes implicit fields from current star" {
  let expected = unnest_as_expected(
    true,
    true,
    tail_override=Some(
      (
        #|,{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}
      ),
    ),
    fields_override=Some("[\"position\"]"),
  )
  assert_eq(
    semantic(
      unnest_struct_compile(
        "FROM UNNEST(@items) element WITH OFFSET position |> AS current |> DROP element |> SELECT * |> ORDER BY position",
      ),
    ),
    semantic(expected),
  )
}
