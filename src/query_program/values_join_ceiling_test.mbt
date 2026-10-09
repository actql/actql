///|
fn values_join_ceiling_control(bound : String) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_join_left","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_join_left":{"from":"t","fields":["x","y"]}}},{"id":"aql_join_right","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"}],"results":{"aql_join_right":{"from":"r","fields":["k"]}}},{"id":"main","inputs":{"l":{"result":{"stage":"aql_join_left","result":"aql_join_left"}},"r":{"result":{"stage":"aql_join_right","result":"aql_join_right"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":
    ) +
    bound +
    (
      #|,"select":{"x":"left.x"}},"as":"aql_join_output"}],"results":{"rows":{"from":"aql_join_output","fields":["x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "standalone Values JOIN retains every explicit author ceiling" {
  for bound in ["1", "5", "10"] {
    let expected = values_join_ceiling_control(bound)
    match
      @check.check_parsed(expected, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("independent bounded Values JOIN is closed")
    }
    let actual = compile(
      @query.parse_query(
        "SELECT t.x AS x FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS " + bound,
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "authored Values JOIN ceiling is checked against admitted frontend maximum" {
  let query = @query.parse_query(
    "SELECT t.x AS x FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 11",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, join_order_context(), {
      ..construction_limits(),
      max_join_output_rows: 10L,
    })
    is Err(UnsupportedJoin),
  )
}

///|
test "declared low JOIN ceiling is not replaced by a cartesian reservation" {
  let actual = compile(
    @query.parse_query(
      "SELECT t.x AS x FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 1",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    { ..construction_limits(), max_join_output_rows: 1L, },
  ).unwrap()
  assert_eq(semantic(actual), semantic(values_join_ceiling_control("1")))
}

///|
test "omitted Values JOIN ceiling retains the existing computed fallback" {
  let actual = compile(
    @query.parse_query(
      "SELECT t.x AS x FROM t JOIN r ON t.x = r.k",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(values_join_ceiling_control("4")))
}

///|
test "ordinary INNER LEFT and CROSS Values joins retain their own explicit guard" {
  for kind in ["INNER", "LEFT", "CROSS"] {
    let condition = if kind == "CROSS" { "" } else { " ON t.x = r.k" }
    let actual = compile(
      @query.parse_query(
        "SELECT t.x AS x FROM t " +
        kind +
        " JOIN r" +
        condition +
        " MAX_OUTPUT_ROWS 1",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_true(semantic(actual).contains("\"max_output_rows\":1"))
    assert_false(semantic(actual).contains("\"max_output_rows\":4"))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the declared guard retains closed Values inputs")
    }
  }
}
