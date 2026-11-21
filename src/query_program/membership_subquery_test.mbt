///|
test "standalone WHERE membership lowers to a null-rejecting left-only semi join" {
  let text = "WITH t AS (SELECT n FROM UNNEST(ARRAY<NUMBER>[1, 1, NULL, 7]) AS n), k AS (SELECT n FROM UNNEST(ARRAY<NUMBER>[1, 1, NULL]) AS n) SELECT n FROM t WHERE n IN (SELECT n FROM k)"
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    captured_stage: Some("capture"),
  }
  let program = compile(query, context, construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"kind\":\"semi\""))
  assert_true(wire.contains("\"null_key\":\"no_match\""))
  assert_true(wire.contains("\"select\":{\"n\":\"left.n\"}"))
  let checked = match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(result) => result
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("membership of local values has no Source input")
  }
  let results = @stage_results.stage_at(
    @check.checked_stage_results(checked),
    0,
  ).unwrap()
  let result = @relation_results.lookup(results, "rows").unwrap()
  assert_eq(@relation_results.fields(result), ["n"])
  let schema = @relation_results.output_schema(result)
  let field = @schema.lookup(schema, Unqualified("n")).unwrap()
  assert_true(field.nullable && field.shape is Number)
}

///|
test "WHERE membership hides its right columns and requires one projected member" {
  let context = {
    ..fixture_context(),
    inputs: [],
    captured_stage: Some("capture"),
  }
  let source = "WITH t AS (SELECT 1 AS n) SELECT n FROM t WHERE n IN (SELECT 1 AS n, 2 AS other)"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    )
    is Err(UnsupportedProjection),
  )
  for
    text in [
      "WITH t AS (SELECT 1 AS n) SELECT n FROM t WHERE n IN (1, 2)", "WITH t AS (SELECT 1 AS n) SELECT n FROM t WHERE n IN UNNEST([1, 2])",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_false(semantic(program).contains("\"kind\":\"semi\""))
  }
}
