///|
fn joined_unnest_star_seed(name? : String = "parents") -> String {
  (
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"object","nullable":true,"fields":{"code":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}}}},"rows":[{"id":2,"items":[{"code":20,"label":null},null,{"code":20,"label":null}]},{"id":1,"items":[{"code":10,"label":"a"}]},{"id":3,"items":[]},{"id":4,"items":null}]},"as":"
  ) +
  name +
  "\"}"
}

///|
test "joined star uses the current ARRAY while preserving its original range" {
  let head = "FROM parents p |> JOIN keys k ON p.id = k.key MAX_OUTPUT_ROWS 4 |> SET items = [9]"
  for
    tail in [
      " |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position",
      " |> CROSS JOIN UNNEST(items) e WITH OFFSET position |> SELECT * |> ORDER BY id, position",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(head + tail, syntax_limits()).unwrap(),
      joined_unnest_star_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        head + " |> CROSS JOIN UNNEST(items) e |> SELECT e.*",
        syntax_limits(),
      ).unwrap(),
      joined_unnest_star_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

///|
test "joined correlated star preserves exact type scope and work refusals" {
  for
    (text, expected) in [
      (
        "SELECT e.* FROM parents p JOIN keys k ON p.id = k.key MAX_OUTPUT_ROWS 4 CROSS JOIN UNNEST(p.id) e",
        0,
      ),
      (
        "FROM parents p |> JOIN keys k ON p.id = k.key MAX_OUTPUT_ROWS 4 |> SELECT id, items |> CROSS JOIN UNNEST(p.items) e |> SELECT e.*",
        1,
      ),
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      joined_unnest_star_context(),
      construction_limits(),
    )
    assert_true(
      match (expected, actual) {
        (0, Err(Expression({ issue: InvalidArguments, origin: Some(_), }))) =>
          true
        (1, Err(Expression({ issue: UnknownReference, origin: Some(_), }))) =>
          true
        _ => false
      },
      msg=text,
    )
  }
  // A zero authored JOIN ceiling is rejected by syntax admission itself.
  assert_true(
    @query.parse_query_script(
      "SELECT e.* FROM parents p JOIN keys k ON p.id = k.key MAX_OUTPUT_ROWS 0 CROSS JOIN UNNEST(p.items) e",
      syntax_limits(),
    )
    is Err({ issue: Syntax(_), span: Some(_), }),
  )
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        "SELECT e.* FROM parents p JOIN keys k ON p.id = k.key MAX_OUTPUT_ROWS 4 CROSS JOIN UNNEST(p.items) e",
        syntax_limits(),
      ).unwrap(),
      joined_unnest_star_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: WorkLimit, .. })),
  )
}

///|
fn joined_unnest_star_keys(name? : String = "keys") -> String {
  (
    #|{"values":{"schema":{"key":{"type":"number","nullable":false}},"rows":[{"key":1},{"key":2},{"key":3},{"key":4}]},"as":"
  ) +
  name +
  "\"}"
}

///|
fn joined_unnest_star_context() -> Context {
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "parents", quoted: false, }],
        name: "parents",
        source: GeneratedValues(unnest_value_cursor(joined_unnest_star_seed())),
        visible_fields: ["id", "items"],
        graph_bindings: [],
      },
      {
        relation: [{ value: "keys", quoted: false, }],
        name: "keys",
        source: GeneratedValues(unnest_value_cursor(joined_unnest_star_keys())),
        visible_fields: ["key"],
        graph_bindings: [],
      },
    ],
  }
}

///|
// Independently authored ordinary operations retain the JOIN ceiling, array,
// nullable object fields and duplicate elements. No Frontend output is used.
fn joined_unnest_star_control() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    joined_unnest_star_seed() +
    "," +
    joined_unnest_star_keys() +
    (
      #|,{"from":"parents","join":{"with":"keys","kind":"inner","on":[{"left":"id","right":"key"}],"max_output_rows":4,"select":{"id":"left.id","items":"left.items","key":"right.key"}},"as":"joined"},{"from":"joined","derive":{"array":{"field":"items"}}},{"unnest":{"column":"array","as":"element","with_index":"position"}},{"derive":{"code":{"property":{"value":{"field":"element"},"name":"code"}},"label":{"property":{"value":{"field":"element"},"name":"label"}}}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"position","dir":"asc","nulls":"first"}]},{"select":["id","code","label","position"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","code","label","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "joined correlated star has an independently checked ordinary Program" {
  assert_true(
    @check.check_parsed(
      joined_unnest_star_control(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "joined correlated star obtains the child scope from actual JOIN output" {
  // Independently fix the complete predicate, ceiling and physical slot wiring.
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    joined_unnest_star_seed(name="aql_script_seed_2") +
    "," +
    joined_unnest_star_keys(name="aql_script_seed_3") +
    (
      #|,{"from":"aql_script_seed_2","join":{"with":"aql_script_seed_3","max_output_rows":4,"select":{"aql_chain_column_2":"left.id","aql_chain_column_3":"left.items","aql_chain_column_4":"right.key"},"kind":"inner","on":[{"left":"id","right":"key"}]},"as":"aql_chain_join_4"},{"from":"aql_chain_join_4","derive":{"aql_unnest_array_5":{"field":"aql_chain_column_3"}}},{"unnest":{"column":"aql_unnest_array_5","as":"aql_unnest_element_6","with_index":"aql_unnest_offset_7"}},{"derive":{"aql_unnest_field_8":{"property":{"value":{"field":"aql_unnest_element_6"},"name":"code"}},"aql_unnest_field_9":{"property":{"value":{"field":"aql_unnest_element_6"},"name":"label"}}}},{"sort":[{"field":"aql_chain_column_2","dir":"asc","nulls":"first"},{"field":"aql_unnest_offset_7","dir":"asc","nulls":"first"}]},{"select":[{"id":"aql_chain_column_2"},{"code":"aql_unnest_field_8"},{"label":"aql_unnest_field_9"},{"position":"aql_unnest_offset_7"}],"as":"aql_chain_result_5"}],"results":{"rows":{"from":"aql_chain_result_5","fields":["id","code","label","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT p.id, e.*, position FROM parents p JOIN keys k ON p.id = k.key MAX_OUTPUT_ROWS 4 CROSS JOIN UNNEST(p.items) e WITH OFFSET position ORDER BY p.id, position",
      "FROM parents p |> JOIN keys k ON p.id = k.key MAX_OUTPUT_ROWS 4 |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position",
    ] {
    let program = match
      compile_query_script(
        @query.parse_query_script(text, syntax_limits()).unwrap(),
        joined_unnest_star_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedProjection) =>
        fail("JOIN output child schema is not passed to UNNEST star")
      Err(_) => fail("unexpected joined star refusal")
    }
    assert_true(
      semantic(program).contains(
        "\"fields\":[\"id\",\"code\",\"label\",\"position\"]",
      ),
    )
    assert_true(semantic(program).contains("\"max_output_rows\":4"))
    assert_eq(semantic(program), semantic(expected), msg=text)
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "joined ordinary range accepts quoted parenthesized property correlation" {
  let text = "SELECT `p`.id, e.*, position FROM parents `p` JOIN keys k ON `p`.id = k.key MAX_OUTPUT_ROWS 4 CROSS JOIN UNNEST((`p`).`ITEMS`) e WITH OFFSET position ORDER BY `p`.id, position"
  let script = match @query.parse_query_script(text, syntax_limits()) {
    Ok(script) => script
    Err(diagnostic) => fail(@debug.to_string(diagnostic))
  }
  let actual = match
    compile_query_script(
      script,
      joined_unnest_star_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(Expression({ issue: UnknownReference, .. })) =>
      fail("parenthesized range receiver is unresolved")
    Err(UnknownColumn) => fail("parenthesized range: UnknownColumn")
    Err(UnsupportedProjection) =>
      fail("parenthesized range: UnsupportedProjection")
    Err(_) => fail("unexpected parenthesized range refusal")
  }
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}
