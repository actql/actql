///|
test "derived scalar alias has an independent checked value Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.derived_value_alias","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1},{"value":2}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed value control")
  }
}

///|
test "a named derived value table keeps its scalar receiver rather than a row object" {
  let actual = match
    compile(
      @query.parse_query(
        "SELECT chosen AS value FROM (FROM UNNEST([1,2]) AS element) AS chosen",
        syntax_limits(),
      ).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(p) => p
    Err(UnsupportedProjection) =>
      fail("derived value receiver: UnsupportedProjection")
    Err(UnsupportedCte) => fail("derived value receiver: UnsupportedCte")
    Err(Expression({ issue: @expression.UnknownReference, .. })) =>
      fail("derived value receiver: UnknownReference")
    Err(_) => fail("derived value receiver: other lowering failure")
  }
  assert_false(
    semantic(actual).contains("\"object\""),
    msg="scalar receiver was rebound as an ordinary row object",
  )
  match
    @check.check_parsed(
      actual,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed scalar receiver")
  }
}

///|
test "derived alias preserves nullable scalar kind and resets the old receiver" {
  let context = {
    ..values_context(),
    inputs: [],
    parameter_declarations: Some(unnest_parameters()),
  }
  let values = unnest_value_cursor("{\"items\":[2,null,2]}")
  for
    source in [
      "SELECT chosen AS value FROM (FROM UNNEST(@items) element) chosen ORDER BY value NULLS FIRST",
      "FROM (FROM UNNEST(@items) element) `CHOSEN` |> SELECT `CHOSEN` AS value |> ORDER BY value NULLS FIRST",
    ] {
    let p = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_false(semantic(p).contains("\"object\""))
    match
      @check.check_parsed(
        p,
        check_environment(numeric=true),
        Some(values),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed declared scalar")
    }
  }
  for
    source in [
      "SELECT element AS value FROM (FROM UNNEST(@items) element) chosen", "SELECT chosen.* FROM (FROM UNNEST(@items) element) chosen",
    ] {
    let result = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    )
    assert_true(
      result is Err(UnknownColumn) ||
      result is Err(UnsupportedProjection) ||
      result is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "derived object alias preserves its whole receiver and nullable property typing" {
  let context = {
    ..values_context(),
    inputs: [],
    parameter_declarations: Some(unnest_struct_parameters()),
  }
  let values = unnest_value_cursor(
    "{\"items\":[{\"id\":2,\"label\":\"kept\"},null,{\"id\":2,\"label\":null}]}",
  )
  for
    source in [
      "SELECT chosen AS value,chosen.id AS id FROM (FROM UNNEST(@items) element) chosen ORDER BY id NULLS FIRST",
      "SELECT chosen.* FROM (FROM UNNEST(@items) element) chosen ORDER BY id NULLS FIRST",
    ] {
    let p = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        p,
        check_environment(numeric=true),
        Some(values),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed declared object")
    }
  }
}

///|
test "offset makes the derived alias an ordinary column row" {
  let context = {
    ..values_context(),
    inputs: [],
    parameter_declarations: Some(unnest_parameters()),
  }
  for
    source in [
      "SELECT chosen.element AS value,chosen.position FROM (FROM UNNEST(@items) element WITH OFFSET position) chosen ORDER BY position",
      "SELECT chosen.* FROM (FROM UNNEST(@items) element WITH OFFSET position) chosen ORDER BY position",
    ] {
    let p = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        p,
        check_environment(numeric=true),
        Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed offset row")
    }
  }
}

///|
test "derived value alias matches a complete independent existing expression Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_unnest_array_2":{"array":[{"literal":1},{"literal":2}]}}},{"unnest":{"column":"aql_unnest_array_2","as":"aql_unnest_element_3"},"as":"aql_script_cte_0"},{"from":"aql_script_cte_0","select":[{"value":"aql_unnest_element_3"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "SELECT chosen AS value FROM (FROM UNNEST([1,2]) AS element) AS chosen",
      syntax_limits(),
    ).unwrap(),
    { ..values_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed independent scoped value")
  }
}
