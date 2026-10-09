///|
test "scalar UNNEST RENAME cannot rename a value-table range" {
  for name in ["element", "`element`", "`ELEMENT`"] {
    let source = "FROM UNNEST(@items) " +
      name +
      " WITH OFFSET position |> RENAME " +
      name +
      " AS next |> SELECT next, position |> ORDER BY position"
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
test "scalar UNNEST explicit projection makes an ordinary RENAME column" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_script_seed_0","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_script_seed_0","derive":{"aql_unnest_array_3":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"select":[{"element":"aql_unnest_element_4"},{"position":"aql_unnest_offset_5"}]},{"sort":[{"field":"position","dir":"asc","nulls":"first"}]},{"select":[{"next":"element"},"position"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["next","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
      "FROM UNNEST(@items) element WITH OFFSET position |> SELECT element, position |> RENAME element AS next |> ORDER BY position",
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
test "scalar UNNEST range kind survives JOIN and rejects reused aliases" {
  for
    source in [
      "FROM UNNEST(@items) element WITH OFFSET position |> JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 |> RENAME element AS next |> SELECT next, position",
      "FROM UNNEST(@items) element WITH OFFSET position |> CROSS JOIN UNNEST(@items) element |> SELECT position",
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
test "scalar UNNEST range replacement does not disable ordinary edits or DISTINCT" {
  for
    tail in [
      "AS row |> RENAME element AS next |> ORDER BY position", "SET element = 100 |> RENAME element AS next |> SELECT * |> ORDER BY position",
      "DROP element |> RENAME position AS next |> SELECT * |> ORDER BY next", "DROP position |> DISTINCT |> SELECT element AS next |> ORDER BY next NULLS LAST",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(
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
    match
      @check.check_parsed(
        actual,
        check_environment(),
        Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("declared scalar inputs are closed")
    }
  }
}

///|
test "scalar UNNEST public single-query entry checks ordinary edited columns" {
  for
    tail in [
      "SELECT element, position |> RENAME element AS next |> ORDER BY position",
      "AS row |> RENAME element AS next |> ORDER BY position", "SET element = 100 |> RENAME element AS next |> SELECT * |> ORDER BY position",
      "DROP element |> RENAME position AS next |> SELECT * |> ORDER BY next", "DROP position |> DISTINCT |> SELECT element AS next |> ORDER BY next NULLS LAST",
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
    match
      @check.check_parsed(
        actual,
        check_environment(),
        Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the public single-query input is closed")
    }
  }
}
