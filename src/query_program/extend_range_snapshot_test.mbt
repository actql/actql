///|
fn extend_range_snapshot_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"z":{"add":[{"field":"x"},{"literal":1}]}}},{"select":[{"original":"x"},"z"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["original","z"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "first EXTEND keeps original range columns and current derived columns" {
  let expected = extend_range_snapshot_expected()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    text in [
      "FROM pair AS old |> EXTEND x + 1 AS z |> SELECT old.x AS original, z", "FROM pair AS `old` |> EXTEND x + 1 AS z |> SELECT `OLD`.`X` AS original, z",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "first EXTEND cannot add a derived column to the original range" {
  for
    tail in [
      "SELECT old.z", "SELECT old.z + 1 AS z", "WHERE old.z > 0 |> SELECT z", "EXTEND old.z + 1 AS another |> SELECT another",
    ] {
    let text = "FROM pair AS old |> EXTEND x + 1 AS z |> " + tail
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=text,
    )
  }
}

///|
test "first EXTEND cannot sort by a derived column through the old range" {
  assert_true(
    compile(
      @query.parse_query(
        "FROM pair AS old |> EXTEND x + 1 AS z |> ORDER BY old.z |> SELECT z",
        syntax_limits(),
      ).unwrap(),
      pair_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: UnknownReference, .. })),
  )
}

///|
test "AS after EXTEND explicitly binds the derived column" {
  let actual = compile(
    @query.parse_query(
      "FROM pair AS old |> EXTEND x + 1 AS z |> AS current |> SELECT current.x AS original, current.z AS z",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(extend_range_snapshot_expected()))
}

///|
test "existing JOIN range refusals retain exact current invalid-input causes" {
  for prefix in ["DROP x", "RENAME x AS current"] {
    assert_true(
      compile(
        @query.parse_query(
          "FROM t |> AS l |> " +
          prefix +
          " |> JOIN r AS rr ON " +
          "x" +
          " = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.x AS original",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=prefix,
    )
  }
  // AS replaces the old lexical range before ON/SELECT resolution.
  assert_true(
    compile(
      @query.parse_query(
        "FROM t |> AS l |> SET x = x + 10 |> AS fresh |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.x AS original",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ) is Err(UnknownColumn),
  )
  // The WITH body does not export its internal range into the outer JOIN.
  assert_true(
    compile(
      @query.parse_query(
        "WITH chosen AS (FROM t |> AS l |> SET x = x + 10) FROM chosen |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.x AS original",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ) is Err(AmbiguousColumn),
  )
}
