///|
fn scalar_receiver_seed() -> String {
  (
    #|{"values":{"schema":{"element":{"type":"number","nullable":false},"position":{"type":"number","nullable":false},"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}},"rows":[{"element":100,"position":50,"items":[2,null,1]}]},"as":"parents"}
  )
}

///|
fn scalar_receiver_context() -> Context {
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "parents", quoted: false, }],
        name: "parents",
        source: GeneratedValues(unnest_value_cursor(scalar_receiver_seed())),
        visible_fields: ["element", "position", "items"],
        graph_bindings: [],
      },
    ],
  }
}

///|
// The two range receivers select UNNEST's value/index. Qualified p columns
// still select 100/50; the predicate cannot read the parent element instead.
fn scalar_receiver_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    scalar_receiver_seed() +
    "," +
    (
      #|{"from":"parents","derive":{"aql_unnest_array_5":{"field":"items"}}},{"unnest":{"column":"aql_unnest_array_5","as":"aql_unnest_element_6","with_index":"aql_unnest_offset_7"}},{"filter":{"gt":[{"field":"aql_unnest_element_6"},{"literal":0}]}},{"sort":[{"field":"aql_unnest_offset_7","dir":"asc","nulls":"first"}]},{"select":[{"element":"aql_unnest_element_6"},{"original":"element"},{"position":"aql_unnest_offset_7"},{"original_position":"position"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["element","original","position","original_position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "scalar and OFFSET range receivers take precedence over parent columns" {
  let expected = scalar_receiver_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent ordinary Program is closed")
  }
  for
    source in [
      "FROM parents p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position |> WHERE element > 0 |> SELECT element, p.element AS original, position, p.position AS original_position |> ORDER BY position",
      "SELECT element, p.element AS original, position, p.position AS original_position FROM parents p CROSS JOIN UNNEST(p.items) element WITH OFFSET position WHERE element > 0 ORDER BY position",
      "FROM parents p |> CROSS JOIN UNNEST(p.items) `ELEMENT` WITH OFFSET `POSITION` |> WHERE `element` > 0 |> SELECT `element` AS element, p.element AS original, `position` AS position, p.position AS original_position |> ORDER BY position",
    ] {
    let actual = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        scalar_receiver_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(Expression(diagnostic)) =>
        fail(source + ": " + @debug.to_string(diagnostic.issue))
      Err(AmbiguousColumn) => fail(source + ": AmbiguousColumn")
      Err(_) => fail(source + ": other lowering refusal")
    }
    assert_eq(semantic(actual), semantic(expected), msg=source)
  }
}

///|
test "scalar range precedence does not survive a SELECT scope replacement" {
  let source = "FROM parents p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position |> SELECT p.element AS original |> WHERE element > 0"
  assert_true(
    compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      scalar_receiver_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: UnknownReference, origin: Some(_), })),
  )
}

///|
test "scalar receiver slots survive JOIN remapping and pre-JOIN predicates" {
  let source = "FROM parents p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position |> WHERE position = 0 |> JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 3 |> WHERE position = 0 |> SELECT element, p.element AS original, position, p.position AS original_position |> ORDER BY position"
  let actual = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    scalar_receiver_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(actual)
  // These are the authored input slots, not a query of product JSON to find
  // whichever slot it happened to choose. JOIN must use the array element.
  assert_true(wire.contains("\"left\":\"aql_unnest_element_6\""))
  assert_true(wire.contains("\"field\":\"aql_unnest_offset_7\""))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "scalar receiver GROUP keys retain actual values without reviving other ranges" {
  for
    source in [
      "SELECT element, COUNT(*) AS n FROM parents p CROSS JOIN UNNEST(p.items) element WITH OFFSET position GROUP BY element ORDER BY element NULLS LAST",
      "SELECT element + 1 AS next, COUNT(*) AS n FROM parents p CROSS JOIN UNNEST(p.items) element WITH OFFSET position GROUP BY element + 1 ORDER BY next NULLS LAST",
      "FROM parents p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position |> AGGREGATE COUNT(*) AS n GROUP BY element |> ORDER BY element NULLS LAST",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      scalar_receiver_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
    assert_true(semantic(actual).contains("aql_unnest_element_6"), msg=source)
  }
}
