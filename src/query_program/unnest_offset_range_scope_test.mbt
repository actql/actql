///|
test "UNNEST OFFSET RENAME cannot rename an unprojected value-table range" {
  for
    source in [
      "FROM UNNEST(@items) element WITH OFFSET position |> RENAME position AS next |> SELECT element, next |> ORDER BY next",
      "FROM UNNEST(@items) element WITH OFFSET `Position` |> RENAME `POSITION` AS next |> SELECT element, next |> ORDER BY next",
      "FROM UNNEST(@items) element WITH OFFSET |> RENAME offset AS next |> SELECT element, next |> ORDER BY next",
      "FROM UNNEST(@items) element WITH OFFSET position |> DROP element |> RENAME position AS next |> SELECT next |> ORDER BY next",
      "FROM UNNEST(@items) element WITH OFFSET position |> JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 |> RENAME position AS next |> SELECT element, next |> ORDER BY next",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(unnest_parameters()),
        },
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=source,
    )
  }
}

///|
test "UNNEST OFFSET range names cannot be reused by later array scans" {
  for
    source in [
      "FROM UNNEST(@items) element WITH OFFSET position |> CROSS JOIN UNNEST(@items) position |> SELECT element",
      "FROM UNNEST(@items) element WITH OFFSET position |> CROSS JOIN UNNEST(@items) other WITH OFFSET position |> SELECT element",
      "FROM UNNEST(@items) element |> CROSS JOIN UNNEST(@items) other WITH OFFSET element |> SELECT other",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(unnest_parameters()),
        },
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=source,
    )
  }
}

///|
test "projected OFFSET RENAME agrees with an independent checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_script_seed_0","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_script_seed_0","derive":{"aql_unnest_array_3":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"select":[{"element":"aql_unnest_element_4"},{"position":"aql_unnest_offset_5"}]},{"sort":[{"field":"position","dir":"asc","nulls":"first"}]},{"select":["element",{"next":"position"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["element","next"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
      check_limits(),
    )
    is Checked(_),
  )
  let actual = compile_query_script(
    @query.parse_query_script(
      "FROM UNNEST(@items) element WITH OFFSET position |> SELECT element, position |> RENAME position AS next |> ORDER BY next",
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
test "OFFSET replacement and projection retain ordinary columns and NULL values" {
  for
    tail in [
      "AS row |> RENAME position AS next |> SELECT element, next |> ORDER BY next",
      "SET position = position + 10 |> RENAME position AS next |> SELECT element, next |> ORDER BY next",
      "DROP element |> SELECT position |> RENAME position AS next |> ORDER BY next",
      "DROP position |> SELECT element |> ORDER BY element NULLS LAST", "DROP position |> CROSS JOIN UNNEST([10]) position WITH OFFSET index |> SELECT element, position, index |> ORDER BY element NULLS LAST",
    ] {
    let actual = compile(
      @query.parse_query(
        "FROM UNNEST(@items) element WITH OFFSET position |> " + tail,
        syntax_limits(),
      ).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(unnest_parameters()),
      },
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
        check_limits(),
      )
      is Checked(_),
    )
  }
}

///|
test "OFFSET range admission is shared by the public single-query compiler" {
  for
    source in [
      "FROM UNNEST(@items) element WITH OFFSET position |> RENAME position AS next |> SELECT element, next",
      "FROM UNNEST(@items) element WITH OFFSET position |> CROSS JOIN UNNEST(@items) position |> SELECT element",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(unnest_parameters()),
        },
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=source,
    )
  }
  let actual = compile(
    @query.parse_query(
      "FROM UNNEST(@items) element WITH OFFSET position |> SELECT element, position |> RENAME position AS next |> ORDER BY next",
      syntax_limits(),
    ).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(unnest_parameters()),
    },
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
      check_limits(),
    )
    is Checked(_),
  )
}
