///|
test "DISTINCT JOIN ORDER derives from an evaluated output alias" {
  let wire = checked_join_order(
    "SELECT DISTINCT -t.x AS x FROM t JOIN r ON t.x = r.k ORDER BY -x",
  )
  // One SELECT negate and one ORDER negate; the latter consumes output x.
  assert_eq(wire.split("\"negate\":").length(), 3)
  assert_true(wire.contains("\"distinct\":[\"x\"]"))
  assert_true(wire.contains("\"fields\":[\"x\"]"))
}

///|
test "DISTINCT JOIN ORDER retains a directly selected qualified input" {
  for
    source in [
      "SELECT DISTINCT t.x AS score FROM t JOIN r ON t.x = r.k ORDER BY t.x + 1",
      "FROM t |> JOIN r ON t.x = r.k |> SELECT DISTINCT t.x AS score |> ORDER BY -score",
    ] {
    let wire = checked_join_order(source)
    assert_true(wire.contains("\"distinct\":[\"score\"]"))
    assert_true(wire.contains("\"fields\":[\"score\"]"))
  }
}

///|
test "CTE DISTINCT JOIN ORDER uses the same projected scope" {
  ignore(
    checked_join_order(
      "WITH chosen AS (SELECT x, y FROM t) SELECT DISTINCT -l.x AS x FROM chosen AS l JOIN chosen AS r ON l.x = r.x ORDER BY -x",
    ),
  )
}

///|
test "DISTINCT JOIN ORDER matches an independent complete ordinary Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_join_left","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_join_left":{"from":"t","fields":["x","y"]}}},{"id":"aql_join_right","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"}],"results":{"aql_join_right":{"from":"r","fields":["k"]}}},{"id":"main","inputs":{"l":{"result":{"stage":"aql_join_left","result":"aql_join_left"}},"r":{"result":{"stage":"aql_join_right","result":"aql_join_right"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":4,"select":{"score":"left.x"}},"as":"aql_join_output"},{"from":"aql_join_output","distinct":["score"],"as":"aql_join_unique"},{"from":"aql_join_unique","derive":{"aql_join_sort_4":{"add":[{"field":"score"},{"literal":1}]}},"as":"aql_join_order_derived"},{"from":"aql_join_order_derived","sort":[{"field":"aql_join_sort_4","dir":"asc","nulls":"first"}],"as":"aql_join_sorted"},{"from":"aql_join_sorted","select":["score"],"as":"aql_join_visible"}],"results":{"rows":{"from":"aql_join_visible","fields":["score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent Values Program must be closed")
  }
  let actual = checked_join_order(
    "SELECT DISTINCT t.x AS score FROM t JOIN r ON t.x = r.k ORDER BY t.x + 1",
  )
  assert_eq(actual, semantic(expected))
}

///|
test "DISTINCT JOIN ORDER does not recover dropped operand columns" {
  for
    source in [
      "SELECT DISTINCT t.x AS score FROM t JOIN r ON t.x = r.k ORDER BY t.y + 1",
      "SELECT DISTINCT -t.x AS x FROM t JOIN r ON t.x = r.k ORDER BY t.x", "SELECT DISTINCT -t.x AS x FROM t JOIN r ON t.x = r.k ORDER BY t.x + 1",
      "WITH chosen AS (SELECT x, y FROM t) SELECT DISTINCT -l.x AS x FROM chosen AS l JOIN chosen AS r ON l.x = r.x ORDER BY l.x + 1",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedOrdering),
      msg=source,
    )
  }
}

///|
test "DISTINCT JOIN ORDER shares a helper without expanding SELECT" {
  let wire = checked_join_order(
    "SELECT DISTINCT t.x + 1 AS score FROM t JOIN r ON t.x = r.k ORDER BY -score, -score DESC LIMIT 1",
  )
  assert_eq(wire.split("\"add\":").length(), 2)
  assert_eq(wire.split("\"negate\":").length(), 2)
  assert_true(wire.contains("\"distinct\":[\"score\"]"))
  assert_true(wire.contains("\"take\":{\"count\":1,\"offset\":0}"))
}

///|
test "DISTINCT JOIN ORDER uses the nullable selected property slot" {
  let program = compile(
    @query.parse_query(
      "SELECT DISTINCT l.payload.score AS score FROM objects AS l JOIN others AS r ON l.id = r.id ORDER BY score + 1 NULLS LAST",
      syntax_limits(),
    ).unwrap(),
    join_property_context(),
    construction_limits(),
  ).unwrap()
  check_join_property(program)
  let wire = semantic(program)
  assert_eq(wire.split("\"property\":").length(), 2)
  assert_true(wire.contains("\"add\":[{\"field\":\"score\"},{\"literal\":1}]"))
  assert_true(wire.contains("\"distinct\":[\"score\"]"))
  assert_true(wire.contains("\"fields\":[\"score\"]"))
}
