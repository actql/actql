///|
fn unnest_join_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"items":{"type":"array","nullable":true,"max_items":3,"items":{"type":"number","nullable":true}}},"stages":[{"id":"main","inputs":{},"steps":[{"as":"seed","values":{"schema":{"unit":{"type":"boolean","nullable":false}},"rows":[{"unit":true}]}},{"from":"seed","derive":{"array":{"$param":"items"}}},{"unnest":{"column":"array","as":"element","with_index":"position"},"as":"expanded"},{"as":"keys","values":{"schema":{"key":{"type":"number","nullable":false}},"rows":[{"key":2}]}},{"from":"expanded","join":{"with":"keys","kind":"inner","on":[{"left":"element","right":"key"}],"max_output_rows":10,"select":{"element":"left.element","position":"left.position","key":"right.key"}},"as":"joined"},{"from":"joined","sort":[{"field":"position","dir":"asc","nulls":"first"}]},{"select":["element","position","key"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["element","position","key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "UNNEST JOIN retains nullable object receivers ranges and explicit bounds" {
  for
    text in [
      "SELECT p.id, e.*, position, k.key FROM parents p CROSS JOIN UNNEST(p.items) e WITH OFFSET position JOIN (SELECT 20 AS key) k ON e.code = k.key MAX_OUTPUT_ROWS 10 ORDER BY p.id, position",
      "FROM parents p |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> JOIN (SELECT 20 AS key) k ON e.code = k.key MAX_OUTPUT_ROWS 10 |> SELECT p.id, e AS object, e.*, position, k.key |> ORDER BY p.id, position",
      "FROM parents p |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id AS id, code, e.code AS original, position |> AS row |> SET code = 99 |> LEFT JOIN (SELECT 20 AS key) k ON row.original = k.key MAX_OUTPUT_ROWS 10 |> SELECT id, code AS `current`, row.original AS original, position, k.key |> ORDER BY id, position",
      "SELECT p.id, e.code, position, k.key FROM parents p JOIN (SELECT 2 AS first_key) first ON p.id = first.first_key MAX_OUTPUT_ROWS 10 CROSS JOIN UNNEST(p.items) e WITH OFFSET position LEFT JOIN (SELECT 20 AS key) k ON e.code = k.key MAX_OUTPUT_ROWS 10 ORDER BY p.id, position",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let actual = compile(
      query,
      joined_unnest_star_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("UNNEST JOIN remains closed")
    }
    assert_true(semantic(actual).contains("\"max_output_rows\":10"))
  }
}

///|
test "UNNEST JOIN does not revive projected ranges or remove array admission" {
  for
    text in [
      "FROM parents p |> CROSS JOIN UNNEST(p.items) e |> SELECT code |> JOIN (SELECT 20 AS key) k ON e.code = k.key |> SELECT code",
      "FROM parents p |> CROSS JOIN UNNEST(p.items) e |> AS rebound |> JOIN (SELECT 20 AS key) k ON p.id = k.key |> SELECT code",
      "SELECT p.id FROM parents p CROSS JOIN UNNEST(p.id) e JOIN (SELECT 20 AS key) k ON e = k.key",
      "SELECT p.id FROM parents p CROSS JOIN UNNEST(p.items) e JOIN (SELECT 20 AS key) k ON e.code = k.key MAX_OUTPUT_ROWS 0",
    ] {
    let query = @query.parse_query(text, syntax_limits())
    match query {
      Err(_) => assert_true(text.contains("MAX_OUTPUT_ROWS 0"))
      Ok(query) => {
        let actual = compile(
          query,
          joined_unnest_star_context(),
          construction_limits(),
        )
        assert_true(actual is Err(_), msg=text)
      }
    }
  }
}

///|
test "UNNEST JOIN continuation has an independently checked common Program" {
  assert_true(
    @check.check_parsed(
      unnest_join_control(),
      check_environment(),
      Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "UNNEST JOIN continuation preserves sequential SQL and Pipe admission" {
  for
    text in [
      "SELECT element, position, k.key FROM UNNEST(@items) element WITH OFFSET position JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 ORDER BY position",
      "FROM UNNEST(@items) element WITH OFFSET position |> JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 |> SELECT element, position, k.key |> ORDER BY position",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let actual = compile(
      query,
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
    let wire = semantic(actual)
    assert_true(wire.contains("\"unnest\""))
    assert_true(wire.contains("\"join\""))
    assert_true(wire.contains("\"max_output_rows\":10"))
  }
}

///|
test "UNNEST FULL JOIN retains the common identity premises" {
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(unnest_parameters()),
  }
  let supplied = Some(unnest_value_cursor("{\"items\":[2,null,2]}"))
  let unkeyed = compile(
    @query.parse_query(
      "SELECT element, position, k.key FROM UNNEST(@items) element WITH OFFSET position FULL JOIN (SELECT 2 AS key UNION ALL SELECT 3 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 ORDER BY position NULLS LAST, k.key",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(unkeyed, check_environment(), supplied, check_limits()) {
    Rejected(error) =>
      assert_true(
        @check.diagnostic_cause(error) is Closure(Joins(MissingStableIdentity(_))),
      )
    _ => fail("FULL must not manufacture identity evidence after expansion")
  }
  let keyed = compile_query_script(
    @query.parse_query_script(
      "WITH keys AS (FROM (SELECT 2 AS key UNION ALL SELECT 3 AS key) keys_input |> ASSERT UNIQUE BY (key)) FROM UNNEST(@items) element WITH OFFSET position |> ASSERT UNIQUE BY (position) |> FULL JOIN keys k ON element = k.key MAX_OUTPUT_ROWS 10 |> SELECT element, position, k.key |> ORDER BY position NULLS LAST, k.key",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(keyed, check_environment(), supplied, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("explicit common assertions must retain the FULL premises")
  }
  assert_true(semantic(keyed).contains("\"max_output_rows\":10"))
}
