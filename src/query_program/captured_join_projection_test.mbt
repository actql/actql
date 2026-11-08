///|
test "captured single JOIN projection uses shared binding and authored keys and ceiling" {
  let query = @query.parse_query(
    "SELECT l.id AS original, r.id AS matched FROM records AS l JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 3 ORDER BY original",
    syntax_limits(),
  ).unwrap()
  let actual = compile(query, cte_capture_context(), construction_limits()).unwrap()
  let body = semantic(actual)
  assert_true(body.contains("\"max_output_rows\":3"))
  assert_true(body.contains("\"on\":[{\"left\":\"id\",\"right\":\"id\"}]"))
  assert_true(body.contains("\"fields\":[\"original\",\"matched\"]"))
  assert_eq(body.split("\"carrier\":\"relation\"").length(), 2)
  assert_false(body.contains("\"filter\":{\"literal\":true}"))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("one declared capture retains both input ports")
  }
}

///|
test "standalone captured projection and shared script retain the same Program" {
  for kind in ["INNER", "LEFT", "RIGHT", "CROSS"] {
    let condition = if kind == "CROSS" { "" } else { " ON l.id = r.id" }
    let query = @query.parse_query(
      "SELECT l.id AS original, r.id AS matched FROM records AS l " +
      kind +
      " JOIN records AS r" +
      condition +
      " MAX_OUTPUT_ROWS 10 ORDER BY original",
      syntax_limits(),
    ).unwrap()
    let direct = compile(query, cte_capture_context(), construction_limits()).unwrap()
    let script = compile_query_script(
      @query.single_query_script(query),
      cte_capture_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(direct), semantic(script))
  }
}

///|
test "independent captured self JOIN control retains typed columns and ceiling" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"capture","inputs":{"records":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{"left":{"result":{"stage":"capture","result":"source"}},"right":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":3,"select":{"original":"left.id","matched":"right.id"}},"as":"joined"},{"sort":[{"field":"original","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["original","matched"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independently authored single capture Program is closed")
  }
}
