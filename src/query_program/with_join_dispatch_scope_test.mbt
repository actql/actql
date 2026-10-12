///|
test "WITH JOIN dispatch installs producer scope before resolving the right input" {
  let query = @query.parse_query(
    "WITH lefts AS (SELECT id, payload FROM objects), rights AS (SELECT id, other FROM others) FROM lefts AS l |> WHERE l.payload.score > 15 |> JOIN rights AS r ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id, r.other.score |> ORDER BY id",
    syntax_limits(),
  ).unwrap()
  let direct = compile(query, join_property_context(), construction_limits()).unwrap()
  let script = compile_query_script(
    @query.single_query_script(query),
    join_property_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(direct), semantic(script))
  check_join_property(direct)
  let body = semantic(direct)
  assert_true(body.contains("\"max_output_rows\":12"))
  assert_true(
    body.contains(
      "\"filter\":{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":15}]}",
    ),
  )
  assert_eq(body.split("\"values\":").length(), 3)
  assert_true(body.contains("\"fields\":[\"id\",\"score\"]"))
}

///|
test "WITH JOIN right bindings keep their original lexical body and shared input" {
  let query = @query.parse_query(
    "WITH keyed AS (FROM t |> ASSERT UNIQUE BY (x)) SELECT l.x AS x FROM keyed AS l JOIN keyed AS r ON l.x=r.x MAX_OUTPUT_ROWS 10 ORDER BY x",
    syntax_limits(),
  ).unwrap()
  let actual = compile(query, join_order_context(), construction_limits()).unwrap()
  check_join_property(actual)
  let body = semantic(actual)
  assert_eq(body.split("\"values\":").length(), 2)
  assert_eq(body.split("\"assert_rows\":").length(), 2)
  assert_true(body.contains("\"max_output_rows\":10"))
  assert_eq(@program.stage_count(actual), 1)
}

///|
test "WITH JOIN dispatch does not admit a truly unresolved right producer" {
  let query = @query.parse_query(
    "WITH chosen AS (SELECT x FROM t) SELECT chosen.x FROM chosen JOIN missing ON chosen.x=missing.x",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, join_order_context(), construction_limits())
    is Err(UnresolvedRelation(_)),
  )
}
