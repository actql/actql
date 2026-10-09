///|
test "standalone JOIN set entry retains independently checked ordinary operations" {
  // Both branches read the same retained input values. Append preserves two
  // copies of id=1; the global sort runs after append, not on one operand.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"},{"from":"t","filter":{"eq":[{"field":"x"},{"literal":1}]}},{"join":{"with":"r","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":1000,"select":{"id":"left.x"}},"as":"first"},{"from":"t","join":{"with":"r","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":1000,"select":{"id":"left.x"}},"as":"second"},{"from":"first","append":{"with":"second"}},{"sort":[{"field":"id","dir":"asc","nulls":"first"}]},{"select":["id"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent ordinary JOIN/append control must be closed")
  }
  let query = @query.parse_query(
    "SELECT t.x AS id FROM t JOIN r ON t.x = r.k WHERE t.x = 1 UNION ALL SELECT t.x AS id FROM t JOIN r ON t.x = r.k ORDER BY id",
    syntax_limits(),
  ).unwrap()
  let script = compile_query_script(
    @query.single_query_script(query),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(script, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the existing script route must retain the declared values")
  }
  let actual = match
    compile(query, join_order_context(), construction_limits()) {
    Ok(program) => program
    Err(UnsupportedJoin) =>
      fail("the standalone entry refuses the existing JOIN set route")
    Err(_) => fail("unexpected standalone JOIN set refusal")
  }
  assert_eq(semantic(actual), semantic(script))
}

///|
test "JOIN set entry preserves nested operand and CTE scopes through existing owners" {
  for
    text in [
      "SELECT t.x AS id FROM t JOIN r ON t.x = r.k UNION ALL SELECT k AS id FROM r ORDER BY id",
      "SELECT x AS id FROM t UNION ALL SELECT t.x AS id FROM t JOIN r ON t.x = r.k ORDER BY id",
      "SELECT x AS id FROM t UNION ALL (SELECT t.x AS id FROM t JOIN r ON t.x = r.k UNION ALL SELECT k AS id FROM r) ORDER BY id",
      "WITH combined AS (SELECT t.x AS id FROM t JOIN r ON t.x = r.k UNION ALL SELECT k AS id FROM r) SELECT id FROM combined ORDER BY id",
      "WITH seed AS (SELECT x FROM t) SELECT l.x AS id FROM seed AS l JOIN r ON l.x = r.k UNION ALL SELECT k AS id FROM r ORDER BY id",
      "FROM t |> JOIN r ON t.x = r.k |> SELECT t.x AS id |> UNION ALL (FROM r |> SELECT k AS id) |> ORDER BY id",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let expected_route = compile_query_script(
      @query.single_query_script(query),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    let actual = compile(query, join_order_context(), construction_limits()).unwrap()
    assert_eq(semantic(actual), semantic(expected_route), msg=text)
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("JOIN set scope must remain closed: " + text)
    }
  }
}

///|
test "JOIN set entry retains declared output ceilings and final output scope" {
  let text = "SELECT t.x AS id FROM t JOIN r ON t.x = r.k UNION ALL SELECT t.x AS id FROM t JOIN r ON t.x = r.k ORDER BY id + 1 LIMIT 2 OFFSET 1"
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  let program = compile(query, join_order_context(), {
    ..construction_limits(),
    max_join_output_rows: 7L,
  }).unwrap()
  let wire = semantic(program)
  assert_eq(wire.split("\"max_output_rows\":7").length(), 3)
  assert_true(wire.contains("\"take\":{\"count\":2,\"offset\":1}"))
  assert_true(wire.contains("\"fields\":[\"id\"]"))
  for order in ["r.k", "t.x", "missing"] {
    let invalid = @query.parse_query(
      "SELECT t.x AS id FROM t JOIN r ON t.x = r.k UNION ALL SELECT k AS id FROM r ORDER BY " +
      order,
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile(invalid, join_order_context(), construction_limits())
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=order,
    )
  }
}

///|
test "JOIN set alignment composes terminal column projection without another material" {
  let query = @query.parse_query(
    "SELECT l.x AS id, r.y AS amount FROM t AS l JOIN t AS r ON l.x = r.x WHERE l.x = 1 UNION ALL CORRESPONDING SELECT r.y AS amount, l.x AS id FROM t AS l JOIN t AS r ON l.x = r.x WHERE l.x >= 2 ORDER BY id",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, join_order_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(!wire.contains("aql_data_set_aligned_"), msg=wire)
  assert_true(
    wire.contains(
      "\"select\":[{\"id\":\"aql_join_input_7\"},{\"amount\":\"aql_join_input_6\"}]",
    ),
  )
  assert_true(wire.contains("\"fields\":[\"id\",\"amount\"]"))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail(
        "composed projection must retain the common checked column contracts",
      )
  }
}

///|
test "JOIN set routing preserves the existing nearest placement refusal" {
  let query = @query.parse_query(
    "FROM queries AS q |> NEAREST candidates AS c QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 KEEP (q.note, c.label) AS neighbor |> UNION ALL (SELECT l.request_id FROM queries AS l JOIN queries AS r ON l.request_id = r.request_id)",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, nearest_context(), construction_limits())
    is Err(UnsupportedNearest),
  )
}
