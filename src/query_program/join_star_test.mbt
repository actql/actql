///|
test "unqualified JOIN star uses the existing joined row scope" {
  let generated = compile(
    @query.parse_query(
      "SELECT * FROM t AS l JOIN r ON l.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY k",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(generated).contains("\"fields\":[\"x\",\"y\",\"k\"]"))
  assert_true(
    @check.check_parsed(generated, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "multiple USING keys follow authored order without losing qualified ranges" {
  let generated = compile(
    @query.parse_query(
      "SELECT *, l.x AS original, r.x AS joined FROM t AS l JOIN t AS r USING (y, x) MAX_OUTPUT_ROWS 10 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(generated).contains(
      "\"fields\":[\"y\",\"x\",\"original\",\"joined\"]",
    ),
  )
  assert_true(
    @check.check_parsed(generated, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "JOIN star keeps duplicate output refusal and validates duplicate USING names" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * FROM t AS l JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * FROM t AS l JOIN t AS r USING (x, `X`) MAX_OUTPUT_ROWS 10",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedJoin),
  )
}

///|
test "LEFT USING star keeps its key first and both qualified input meanings" {
  let generated = compile(
    @query.parse_query(
      "WITH left_rows AS (SELECT y, x FROM t), right_keys AS (SELECT x FROM t) SELECT * FROM left_rows AS l LEFT JOIN right_keys AS r USING (x) MAX_OUTPUT_ROWS 10 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(generated).contains("\"fields\":[\"x\",\"y\"]"))
  assert_true(
    @check.check_parsed(generated, check_environment(), None, check_limits())
    is Checked(_),
  )
}
