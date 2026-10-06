///|
test "RIGHT JOIN commutes into a bounded common LEFT JOIN with SQL range slots" {
  let generated = compile(
    @query.parse_query(
      "SELECT l.x, r.k FROM t AS l RIGHT OUTER JOIN r ON l.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY k",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(generated)
  assert_true(wire.contains("\"from\":\"aql_chain_input_1\""))
  assert_true(wire.contains("\"with\":\"aql_chain_input_0\""))
  assert_true(wire.contains("\"kind\":\"left\""))
  assert_true(wire.contains("\"on\":[{\"left\":\"k\",\"right\":\"x\"}]"))
  assert_true(wire.contains("\"aql_chain_column_2\":\"right.x\""))
  assert_true(wire.contains("\"aql_chain_column_4\":\"left.k\""))
  assert_true(wire.contains("\"max_output_rows\":10"))
  match
    @check.check_parsed(generated, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independently bounded Values inputs are closed")
  }
}

///|
test "RIGHT USING exposes the preserved key but retains both qualified slots" {
  let generated = compile(
    @query.parse_query(
      "SELECT x, l.x AS original, r.x AS preserved FROM t AS l RIGHT JOIN t AS r USING (x) MAX_OUTPUT_ROWS 10 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(generated)
  assert_true(wire.contains("{\"x\":\"aql_chain_column_4\"}"))
  assert_true(wire.contains("{\"original\":\"aql_chain_column_2\"}"))
  assert_true(wire.contains("{\"preserved\":\"aql_chain_column_4\"}"))
  assert_true(
    @check.check_parsed(generated, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "RIGHT JOIN preserves later ON scopes bounds and alias ORDER" {
  for
    source in [
      "SELECT l.x AS key, r.k FROM t AS l RIGHT JOIN r ON l.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY key + 1",
      "SELECT l.x AS key, r.k FROM t AS l RIGHT JOIN r ON r.k = l.x MAX_OUTPUT_ROWS 10 WHERE l.x > 0 ORDER BY key",
      "SELECT l.x, r.k FROM t AS l LEFT JOIN r ON l.x = r.k MAX_OUTPUT_ROWS 10 RIGHT JOIN r AS s ON l.x = s.k MAX_OUTPUT_ROWS 10 ORDER BY l.x",
      "SELECT l.x, r.k FROM t AS l RIGHT JOIN r ON l.x = r.k MAX_OUTPUT_ROWS 10 LEFT JOIN r AS s ON r.k = s.k MAX_OUTPUT_ROWS 10 ORDER BY r.k",
      "FROM t AS l |> WHERE x > 0 |> RIGHT JOIN r ON l.x = r.k MAX_OUTPUT_ROWS 10 |> SELECT l.x, r.k |> ORDER BY k",
    ] {
    let generated = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        generated,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("bounded RIGHT JOIN inputs are closed: " + source)
    }
  }
}
