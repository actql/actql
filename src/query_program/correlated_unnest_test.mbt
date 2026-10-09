///|
fn correlated_unnest_seed() -> String {
  (
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}},"rows":[{"id":2,"items":[2,null,2]},{"id":1,"items":[1]},{"id":3,"items":[]},{"id":4,"items":null}]},"as":"parents"}
  )
}

///|
fn correlated_unnest_context() -> Context {
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "parents", quoted: false, }],
        name: "parents",
        source: GeneratedValues(unnest_value_cursor(correlated_unnest_seed())),
        visible_fields: ["id", "items"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "correlated UNNEST preserves the explicit predicate order and LIMIT" {
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    correlated_unnest_seed() +
    "," +
    (
      #|{"from":"parents","derive":{"aql_unnest_array_4":{"field":"items"}}},{"unnest":{"column":"aql_unnest_array_4","as":"aql_unnest_element_5","with_index":"aql_unnest_offset_6"}},{"filter":{"not":{"is_null":{"field":"aql_unnest_element_5"}}}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"aql_unnest_offset_6","dir":"asc","nulls":"first"}]},{"select":["id",{"element":"aql_unnest_element_5"},{"position":"aql_unnest_offset_6"}]},{"take":{"count":2,"offset":0},"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","element","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  let actual = compile(
    @query.parse_query(
      "SELECT p.id, element, position FROM parents p CROSS JOIN UNNEST(p.items) element WITH OFFSET position WHERE element IS NOT NULL ORDER BY p.id, position LIMIT 2",
      syntax_limits(),
    ).unwrap(),
    correlated_unnest_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "correlated UNNEST retains parent slots in an independently checked Program" {
  // Copying the array preserves the original input column. Expansion belongs
  // to the common owner; NULL/empty arrays and duplicate elements are not
  // filtered or rewritten by the Frontend.
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    correlated_unnest_seed() +
    "," +
    (
      #|{"from":"parents","derive":{"aql_unnest_array_4":{"field":"items"}}},{"unnest":{"column":"aql_unnest_array_4","as":"aql_unnest_element_5","with_index":"aql_unnest_offset_6"}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"aql_unnest_offset_6","dir":"asc","nulls":"first"}]},{"select":["id",{"element":"aql_unnest_element_5"},{"position":"aql_unnest_offset_6"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","element","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
    msg="the existing common operation must accept the independent control",
  )
  for
    text in [
      "SELECT p.id, element, position FROM parents AS p CROSS JOIN UNNEST(p.items) AS element WITH OFFSET position ORDER BY p.id, position",
      "FROM parents AS p |> CROSS JOIN UNNEST(p.items) AS element WITH OFFSET position |> SELECT p.id, element, position |> ORDER BY p.id, position",
      "SELECT `p`.id, `element`, `position` FROM `parents` AS `p` CROSS JOIN UNNEST(`p`.items) `element` WITH OFFSET `position` ORDER BY `p`.id, `position`",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let actual = compile(
      query,
      correlated_unnest_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "correlated UNNEST retains original arrays and immutable Pipe ranges" {
  for
    text in [
      "SELECT p.id, p.items, element, position FROM parents p CROSS JOIN UNNEST(p.items) element WITH OFFSET position ORDER BY p.id, position",
      "FROM parents p |> SET items = [9] |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position |> SELECT p.id, p.items, element, position |> ORDER BY p.id, position",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      correlated_unnest_context(),
      construction_limits(),
    ).unwrap()
    let wire = semantic(actual)
    assert_true(wire.contains("\"derive\":{\"aql_unnest_array_"))
    assert_true(wire.contains("\":{\"field\":\"items\"}}"))
    assert_true(wire.contains("\"select\":[\"id\",\"items\","))
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
  let parent_star = compile(
    @query.parse_query(
      "SELECT p.*, element, position FROM parents p CROSS JOIN UNNEST(p.items) element WITH OFFSET position ORDER BY p.id, position",
      syntax_limits(),
    ).unwrap(),
    correlated_unnest_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(parent_star, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "correlated UNNEST keeps both closed object receivers" {
  let declarations = @parameters.read_declarations(
    Some(
      unnest_value_cursor(
        (
          #|{"left":{"type":"array","max_items":2,"items":{"type":"object","fields":{"id":{"type":"number"}}}},"right":{"type":"array","max_items":2,"items":{"type":"object","fields":{"id":{"type":"number"}}}}}
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
      "SELECT l AS original, r AS matched, l.id AS left_id, r.id AS right_id FROM UNNEST(@left) l CROSS JOIN UNNEST(@right) r",
      syntax_limits(),
    ).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(declarations),
    },
    construction_limits(),
  ).unwrap()
  let wire = semantic(actual)
  assert_true(wire.contains("\"original\":\"aql_unnest_element_3\""))
  assert_true(wire.contains("\"matched\":\"aql_unnest_element_5\""))
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(
        unnest_value_cursor("{\"left\":[{\"id\":1}],\"right\":[{\"id\":2}]}"),
      ),
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "correlated UNNEST rejects stale ranges and duplicate element aliases" {
  for
    (text, expected) in [
      (
        "FROM parents p |> SELECT id, items |> CROSS JOIN UNNEST(p.items) element |> SELECT id, element",
        "reference",
      ),
      ("SELECT p.id FROM parents p CROSS JOIN UNNEST(p.items) p", "range"),
      (
        "SELECT element FROM parents p CROSS JOIN UNNEST(p.items) element WITH OFFSET ELEMENT",
        "offset",
      ),
    ] {
    let result = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      correlated_unnest_context(),
      construction_limits(),
    )
    assert_true(
      match (result, expected) {
        (
          Err(Expression({ issue: @expression.UnknownReference, .. })),
          "reference",
        ) => true
        (Err(AmbiguousColumn), "range") => true
        (Err(DuplicateOutput), "offset") => true
        _ => false
      },
      msg=text,
    )
  }
  // Sequential JOIN placement is covered by the continuation controls.
}

///|
test "correlated UNNEST follows a checked ordinary JOIN without a second executor" {
  let actual = compile(
    @query.parse_query(
      "SELECT p.id, element, position FROM parents p JOIN parents q ON p.id = q.id MAX_OUTPUT_ROWS 10 CROSS JOIN UNNEST(p.items) element WITH OFFSET position ORDER BY p.id, position",
      syntax_limits(),
    ).unwrap(),
    correlated_unnest_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
  assert_true(semantic(actual).contains("\"max_output_rows\":10"))
}
