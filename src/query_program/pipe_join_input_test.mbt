///|
test "projected Pipe JOIN agrees with an independent complete existing Program" {
  // One additional ordinary projection binds the left producer. Source-free
  // Values, both DATA producers, the cross join and Result remain shared IR.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_0"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_3","derive":{"aql_query_expr_0":{"literal":2}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_2"},{"from":"aql_data_0","select":["id"],"as":"aql_script_cte_5"},{"from":"aql_script_cte_5","cross_join":{"with":"aql_data_2","max_output_rows":10,"select":{"a":"left.id","b":"right.id"}},"as":"aql_join_output_7"},{"from":"aql_join_output_7","select":["a","b"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent Values inputs are closed")
  }
  for
    body in [
      "FROM lefts |> SELECT id |> AS l |> CROSS JOIN rights AS r MAX_OUTPUT_ROWS 10 |> SELECT l.id AS a, r.id AS b",
      "SELECT id FROM lefts |> AS l |> CROSS JOIN rights AS r MAX_OUTPUT_ROWS 10 |> SELECT l.id AS a, r.id AS b",
      "FROM lefts AS old |> SELECT id |> AS discarded |> AS `L` |> CROSS JOIN rights AS r MAX_OUTPUT_ROWS 10 |> SELECT l.id AS a, r.id AS b",
    ] {
    let program = checked_data_join(
      "DATA lefts = SELECT 1 AS id; DATA rights = SELECT 2 AS id; DATA paired = " +
      body +
      "; FROM paired |> SELECT a, b",
      { ..fixture_context(), inputs: [], },
    )
    assert_eq(semantic(program), semantic(expected))
  }
}

///|
test "Pipe JOIN prefix keeps evaluated fields predicates limits and rebound ranges" {
  for
    text in [
      "FROM t AS old |> SELECT x + 10 AS id, y |> AS l |> WHERE l.id > 11 |> ORDER BY id |> LIMIT 1 |> JOIN r AS rr ON l.id = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.id, l.y, rr.k |> ORDER BY id",
      "FROM t AS old |> SELECT x AS id |> SET id = id + 1 |> AS l |> JOIN r AS rr ON l.id = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.id, rr.k",
      "FROM t AS old |> SELECT x AS id |> AS l |> SET id = id + 1 |> AS fresh |> JOIN r AS rr ON fresh.id = rr.k MAX_OUTPUT_ROWS 10 |> SELECT fresh.id, rr.k",
      "WITH base AS (SELECT x, y FROM t) FROM base AS old |> SELECT x AS id |> AS l |> JOIN r AS rr ON l.id = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.id, rr.k",
      "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> WHERE rr.k > 1 |> JOIN r AS s ON rr.k = s.k MAX_OUTPUT_ROWS 10 |> SELECT l.x",
    ] {
    for
      program in [
        match
          compile(
            @query.parse_query(text, syntax_limits()).unwrap(),
            join_order_context(),
            construction_limits(),
          ) {
          Ok(program) => program
          Err(UnsupportedCte) => fail("standalone UnsupportedCte: " + text)
          Err(UnsupportedJoin) => fail("standalone UnsupportedJoin: " + text)
          Err(Expression(_)) => fail("standalone Expression: " + text)
          Err(_) => fail("standalone: " + text)
        },
        match
          compile_query_script(
            @query.parse_query_script(text, syntax_limits()).unwrap(),
            join_order_context(),
            construction_limits(),
          ) {
          Ok(program) => program
          Err(UnsupportedCte) => fail("script UnsupportedCte: " + text)
          Err(UnsupportedJoin) => fail("script UnsupportedJoin: " + text)
          Err(Expression(_)) => fail("script Expression: " + text)
          Err(_) => fail("script: " + text)
        },
      ] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        Rejected(error) => raise @check.diagnostic_cause(error)
        _ => fail("closed JOIN prefix must not introduce acquisition")
      }
      let wire = semantic(program)
      assert_true(wire.contains("\"max_output_rows\":10"))
      if text.contains("LIMIT 1") {
        assert_true(
          wire.contains("\"gt\":[{\"field\":\"id\"},{\"literal\":11}]"),
        )
        assert_true(wire.contains("\"take\":{\"count\":1,\"offset\":0}"))
        assert_eq(wire.split("\"add\":").length(), 2)
      }
    }
  }
}

///|
test "projected Pipe JOIN cannot revive removed columns or displaced aliases" {
  for
    text in [
      "FROM t AS old |> SELECT x AS id |> AS l |> JOIN r AS rr ON old.x = rr.k |> SELECT l.id",
      "FROM t AS old |> SELECT x AS id |> AS l |> JOIN r AS rr ON l.y = rr.k |> SELECT l.id",
      "FROM t |> SELECT x AS id |> AS old |> AS l |> JOIN r AS rr ON old.id = rr.k |> SELECT l.id",
      "FROM t |> SELECT x AS id |> AS l |> JOIN r AS l ON l.id = l.k |> SELECT id",
    ] {
    let result = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    if text.contains("AS l ON") {
      assert_true(result is Err(AmbiguousRelation), msg=text)
    } else {
      assert_true(result is Err(AmbiguousColumn), msg=text)
    }
  }
  // An old range snapshot after a value change is not faithfully representable
  // by one visible producer. Keep this current gap explicit, not misbound.
  assert_true(
    @query.parse_query(
      "FROM t |> AS l |> SET x = 2 |> JOIN r AS rr ON l.x = rr.k |> SELECT x",
      syntax_limits(),
    )
    is Err(_),
  )
}
