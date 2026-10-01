///|
test "nested WITH declarations preserve lexical visibility and range spelling" {
  for
    text in [
      "WITH chosen AS (WITH hidden AS (SELECT a FROM left_rows) SELECT hidden.a FROM hidden) SELECT chosen.a FROM chosen",
      "WITH base AS (SELECT a FROM left_rows), chosen AS (WITH base AS (SELECT a FROM base WHERE a > 0) SELECT base.a FROM base) SELECT a FROM chosen UNION ALL SELECT a FROM base",
      "SELECT chosen.a FROM (WITH hidden AS (SELECT a FROM left_rows) SELECT hidden.a FROM hidden) AS chosen",
      "WITH chosen AS (WITH `Hidden` AS (SELECT a FROM left_rows) SELECT `Hidden`.a FROM `Hidden`) SELECT a FROM chosen",
    ] {
    let program = match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        set_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(_) => fail(text)
    }
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      _ => fail(text)
    }
  }
}

///|
test "hoisted nested WITH producers do not escape their authored scope" {
  for
    text in [
      "WITH chosen AS (WITH hidden AS (SELECT a FROM left_rows) SELECT a FROM hidden) SELECT a FROM chosen UNION ALL SELECT a FROM hidden",
      "SELECT a FROM (WITH hidden AS (SELECT a FROM left_rows) SELECT a FROM hidden) AS chosen UNION ALL SELECT a FROM hidden",
      "WITH chosen AS (WITH hidden AS (SELECT a FROM later), later AS (SELECT a FROM left_rows) SELECT a FROM hidden) SELECT a FROM chosen",
      "WITH chosen AS (WITH hidden AS (SELECT a FROM hidden) SELECT a FROM hidden) SELECT a FROM chosen",
      "WITH chosen AS (WITH hidden AS (SELECT a FROM left_rows), HIDDEN AS (SELECT a FROM left_rows) SELECT a FROM hidden) SELECT a FROM chosen",
    ] {
    let result = @query.parse_query(text, syntax_limits()).map(query => {
      compile(query, set_context(), construction_limits())
    })
    assert_true(result is Err(_) || result is Ok(Err(_)), msg=text)
  }
}

///|
test "derived SQL and Pipe sources have the same independent checked Program" {
  // The authored Stage Result input is the parsed derived producer, not a
  // repeated expansion of its Values acquisition or an independent evaluator.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.sql_set","stages":[{"id":"aql_cte_0","inputs":{},"steps":[{"values":{"schema":{"a":{"type":"number","nullable":true},"b":{"type":"string","nullable":false}},"rows":[{"a":1,"b":"x"},{"a":1,"b":"x"},{"a":2,"b":"y"},{"a":null,"b":"n"}]},"as":"left_rows"},{"from":"left_rows","filter":{"gt":[{"field":"a"},{"literal":0}]}},{"select":["a","b"],"as":"aql_cte_final"}],"results":{"rows":{"from":"aql_cte_final","fields":["a","b"]}}},{"id":"main","inputs":{"aql_query_source_0":{"result":{"stage":"aql_cte_0","result":"rows"}}},"steps":[{"from":"aql_query_source_0","select":["b","a"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["b","a"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT b, a FROM (SELECT a, b FROM left_rows WHERE a > 0) AS chosen", "SELECT b, a FROM (FROM left_rows |> WHERE a > 0 |> SELECT a, b) AS chosen",
      "FROM (FROM left_rows |> WHERE a > 0 |> SELECT a, b) AS chosen |> SELECT b, a",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      set_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("derived Values source is closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "derived Pipe projection exposes only its output scope" {
  for
    text in [
      "SELECT a FROM (SELECT a FROM left_rows |> WHERE a > 0) AS chosen", "SELECT chosen.a FROM (FROM left_rows |> SELECT a |> WHERE a > 0) AS chosen",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      set_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      _ => fail(text)
    }
  }
  for
    text in [
      "SELECT chosen.b FROM (FROM left_rows |> SELECT a) AS chosen", "SELECT left_rows.a FROM (FROM left_rows |> SELECT a) AS chosen",
      "SELECT chosen.a FROM (FROM left_rows AS old |> AS fresh |> SELECT old.a) AS chosen",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        set_context(),
        construction_limits(),
      )
      is Err(_),
      msg=text,
    )
  }
}

///|
test "derived captured Pipe binds one retained source producer" {
  // Independently authored from the captured Stage Result contract. The
  // derived relation refers to the capture; it has no second external input.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"capture","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","filter":{"gt":[{"field":"amount"},{"literal":10}]}},{"select":["id","customer_id","status","amount"],"as":"aql_capture_0"}],"results":{"source":{"from":"aql_capture_0","fields":["id","customer_id","status","amount"]}}},{"id":"main","inputs":{"aql_query_source_0":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"aql_query_source_0","select":["id"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  for
    text in [
      "SELECT id FROM (FROM orders |> WHERE amount > 10) AS chosen", "FROM (FROM orders |> WHERE amount > 10) AS chosen |> SELECT id",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      _ => fail("derived input must share the single checked capture")
    }
  }
}

///|
test "query-expression composition uses the existing checked set and CTE owners" {
  for
    text in [
      "(SELECT a FROM left_rows)", "((SELECT a FROM left_rows)) |> WHERE a > 0 |> SELECT a",
      "WITH chosen AS (SELECT a FROM left_rows UNION ALL SELECT c FROM right_rows) SELECT a FROM chosen",
      "SELECT a FROM (SELECT a FROM left_rows UNION ALL SELECT c FROM right_rows) AS chosen",
      "(SELECT a FROM left_rows UNION ALL SELECT c FROM right_rows) |> WHERE a > 0 |> SELECT a",
      "SELECT a FROM left_rows UNION ALL (SELECT c FROM right_rows ORDER BY c LIMIT 1)",
      "SELECT a FROM left_rows UNION ALL (SELECT c FROM right_rows INTERSECT DISTINCT SELECT a FROM left_rows)",
      "FROM left_rows |> SELECT a |> UNION ALL (FROM right_rows |> SELECT c) |> WHERE a > 0 |> SELECT a",
      "WITH base AS (SELECT a FROM left_rows) SELECT a FROM base UNION ALL SELECT a FROM base",
      "WITH base AS (SELECT a FROM left_rows), combined AS (SELECT a FROM base UNION ALL SELECT a FROM base) SELECT a FROM combined",
      "WITH base AS (SELECT a FROM left_rows) SELECT a FROM base UNION ALL SELECT c FROM right_rows",
    ] {
    let program = match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        set_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(_) => fail(text)
    }
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail(text)
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "captured set CTE preserves differing filters after one source capture" {
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  for
    text in [
      "WITH chosen AS (SELECT id FROM orders WHERE amount > 10 UNION ALL SELECT id FROM orders WHERE amount < 5) SELECT id FROM chosen",
      "(SELECT id FROM orders WHERE amount > 10 UNION ALL SELECT id FROM orders WHERE amount < 5) |> SELECT id",
      "WITH large AS (SELECT id FROM orders WHERE amount > 10), small AS (SELECT id FROM orders WHERE amount < 5) SELECT id FROM large UNION ALL SELECT id FROM small",
    ] {
    let program = match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        context,
        construction_limits(),
      ) {
      Ok(program) => program
      Err(_) => fail(text)
    }
    let wire = semantic(program)
    // Independent obligations: broad capture, both retained branch filters,
    // and exactly one external declaration; no predicate from the first arm
    // may remove rows needed by the other arm before capture.
    assert_true(wire.contains("\"filter\":{\"literal\":true}"))
    assert_true(
      wire.contains("\"gt\":[{\"field\":\"amount\"},{\"literal\":10}]"),
    )
    assert_true(
      wire.contains("\"lt\":[{\"field\":\"amount\"},{\"literal\":5}]"),
    )
    assert_eq(wire.split("\"carrier\":\"relation\"").length(), 2)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      _ => fail(text)
    }
  }
}

///|
test "set composition does not leak source scopes or accept forward dependencies" {
  for
    text in [
      "(SELECT a FROM left_rows) |> SELECT left_rows.a", "SELECT a FROM left_rows UNION ALL SELECT c FROM right_rows |> SELECT b",
      "WITH chosen AS (SELECT a FROM left_rows UNION ALL SELECT a FROM later), later AS (SELECT a FROM left_rows) SELECT a FROM chosen",
      "WITH chosen AS (SELECT a FROM left_rows UNION ALL SELECT a FROM chosen) SELECT a FROM chosen",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        set_context(),
        construction_limits(),
      )
      is Err(_),
      msg=text,
    )
  }
}

///|
test "captured set CTE matches an independently authored Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"capture","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","filter":{"literal":true}},{"select":["id","customer_id","status","amount"],"as":"aql_capture_0"}],"results":{"source":{"from":"aql_capture_0","fields":["id","customer_id","status","amount"]}}},{"id":"aql_cte_0_aql_set_term_0","inputs":{"orders":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"orders","filter":{"gt":[{"field":"amount"},{"literal":10}]}},{"select":["id"],"as":"aql_set_output_0"}],"results":{"aql_cte_0_aql_set_term_0":{"from":"aql_set_output_0","fields":["id"]}}},{"id":"aql_cte_0_aql_set_term_1","inputs":{"orders":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"orders","filter":{"lt":[{"field":"amount"},{"literal":5}]}},{"select":["id"],"as":"aql_set_output_1"}],"results":{"aql_cte_0_aql_set_term_1":{"from":"aql_set_output_1","fields":["id"]}}},{"id":"aql_cte_0_aql_set_merge_0","inputs":{"l":{"result":{"stage":"aql_cte_0_aql_set_term_0","result":"aql_cte_0_aql_set_term_0"}},"r":{"result":{"stage":"aql_cte_0_aql_set_term_1","result":"aql_cte_0_aql_set_term_1"}}},"steps":[{"from":"l","append":{"with":"r"},"as":"aql_set_combined_0"}],"results":{"aql_cte_0_aql_set_merge_0":{"from":"aql_set_combined_0","fields":["id"]}}},{"id":"aql_cte_0","inputs":{"set_rows":{"result":{"stage":"aql_cte_0_aql_set_merge_0","result":"aql_cte_0_aql_set_merge_0"}}},"steps":[{"from":"set_rows","select":["id"],"as":"aql_set_final_0"}],"results":{"rows":{"from":"aql_set_final_0","fields":["id"]}}},{"id":"main","inputs":{"chosen":{"result":{"stage":"aql_cte_0","result":"rows"}}},"steps":[{"from":"chosen","select":["id"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let query = @query.parse_query(
    "WITH chosen AS (SELECT id FROM orders WHERE amount > 10 UNION ALL SELECT id FROM orders WHERE amount < 5) SELECT id FROM chosen",
    syntax_limits(),
  ).unwrap()
  let program = compile(
    query,
    { ..fixture_context(), captured_stage: Some("capture"), },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}
