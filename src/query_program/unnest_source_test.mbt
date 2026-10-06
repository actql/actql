///|
fn unnest_parameters() -> @parameters.Declarations {
  let root = unnest_value_cursor(
    "{\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}",
  )
  @parameters.read_declarations(Some(root), {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn unnest_value_cursor(text : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(text, construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
test "UNNEST source matches a complete independent checked Program" {
  // The common scoped projection is deferred until after ordering. Both
  // operations read the same evaluated element/index slots; no expression,
  // filtering or multiplicity is changed by the final projection.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":{"$param":"items"}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"element":"aql_unnest_element_4"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["element","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let values = unnest_value_cursor("{\"items\":[2,null,2]}")
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(values),
      check_limits(),
    )
    is Checked(_),
    msg="the independently authored common expansion must already be accepted",
  )
  for
    text in [
      "SELECT element, position FROM UNNEST(@items) AS element WITH OFFSET AS position ORDER BY position",
      "SELECT ALL element element, position position FROM UNNEST(@items) AS element WITH OFFSET AS position ORDER BY position",
      "FROM UNNEST(@items) AS element WITH OFFSET AS position |> SELECT element, position |> ORDER BY position",
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
    assert_eq(semantic(actual), semantic(expected))
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(values),
        check_limits(),
      )
      is Checked(_),
    )
  }
}

///|
test "UNNEST source preserves nullable empty and duplicate inputs through common checking" {
  let query = @query.parse_query(
    "SELECT element, offset FROM UNNEST(@items) AS element WITH OFFSET ORDER BY offset",
    syntax_limits(),
  ).unwrap()
  let program = compile(
    query,
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(unnest_parameters()),
    },
    construction_limits(),
  ).unwrap()
  for value in ["null", "[]", "[2,null,2]"] {
    assert_true(
      @check.check_parsed(
        program,
        check_environment(),
        Some(unnest_value_cursor("{\"items\":" + value + "}")),
        check_limits(),
      )
      is Checked(_),
    )
  }
}

///|
test "UNNEST source does not expose its witness or synthesize value-table star semantics" {
  for
    (text, issue) in [
      ("SELECT aql_source_free_unit FROM UNNEST(@items) AS element", "column"),
      ("SELECT aql_unnest_array_2 FROM UNNEST(@items) AS element", "column"),
      (
        "SELECT element FROM UNNEST(@items) AS element WITH OFFSET AS ELEMENT", "collision",
      ),
      ("SELECT * FROM UNNEST(@items) AS element", "projection"),
    ] {
    let result = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..fixture_context(),
        inputs: [],
        parameter_declarations: Some(unnest_parameters()),
      },
      construction_limits(),
    )
    assert_true(
      match (result, issue) {
        (Err(Expression(diagnostic)), "column") =>
          diagnostic.issue is @expression.UnknownReference
        (Err(DuplicateOutput), "collision") => true
        (Err(UnsupportedProjection), "projection") => true
        _ => false
      },
      msg=text,
    )
  }
}
