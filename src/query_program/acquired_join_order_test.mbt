///|
test "standalone acquired JOIN uses the existing shared capture assembly" {
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  for
    source in [
      "SELECT DISTINCT -l.amount AS amount FROM orders AS l JOIN orders AS r ON l.id = r.id MAX_OUTPUT_ROWS 25 ORDER BY -amount",
      "FROM orders AS l |> JOIN orders AS r ON l.id = r.id MAX_OUTPUT_ROWS 25 |> SELECT DISTINCT -l.amount AS amount |> ORDER BY -amount",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        data_acquisition_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("declared captured schema must be closed")
    }
    let wire = semantic(program)
    assert_eq(wire.split("\"carrier\":\"relation\"").length(), 2)
    assert_eq(@program.stage_count(program), 2)
    assert_true(wire.contains("\"max_output_rows\":25"))
    assert_true(wire.contains("\"fields\":[\"amount\"]"))
  }
}

///|
test "acquired JOIN routing retains name and authored bound refusals" {
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  let bounded = @query.parse_query(
    "SELECT l.id FROM orders AS l JOIN orders AS r ON l.id = r.id MAX_OUTPUT_ROWS 25",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(bounded, context, {
      ..construction_limits(),
      max_join_output_rows: 10L,
    })
    is Err(UnsupportedJoin),
  )
  let collided = @query.parse_query(
    "SELECT l.id FROM orders AS l JOIN orders AS l ON l.id = l.id MAX_OUTPUT_ROWS 25",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(collided, context, construction_limits()) is Err(AmbiguousRelation),
  )
}

///|
test "acquired JOIN routing preserves the authored filter expression" {
  let program = compile(
    @query.parse_query(
      "SELECT l.id FROM orders AS l JOIN orders AS r ON l.id = r.id MAX_OUTPUT_ROWS 25 WHERE l.amount = l.amount ORDER BY l.id",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), captured_stage: Some("capture"), },
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_eq(wire.split("\"eq\":").length(), 2)
  assert_true(wire.contains("\"max_output_rows\":25"))
  assert_eq(wire.split("\"carrier\":\"relation\"").length(), 2)
}
