///|
test "Pipe RENAME can introduce ambiguous current names without rebinding ranges" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","select":[{"original":"x"},{"retained":"y"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["original","retained"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    source in [
      "FROM pair AS old |> RENAME x AS y |> SELECT old.x AS original, old.y AS retained",
      "FROM pair AS `old` |> RENAME `X` AS `Y` |> SELECT `OLD`.`X` AS original, `OLD`.`Y` AS retained",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "Pipe RENAME preserves unrelated duplicate JOIN names until projection" {
  // Independent RIGHT JOIN: x is one USING key; both y values remain distinct.
  // Both consumers import one captured producer, rather than recapturing t.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_chain_source_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_chain_source_0":{"from":"t","fields":["x","y"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_1":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}}},"steps":[{"from":"aql_chain_input_1","join":{"with":"aql_chain_input_0","kind":"left","on":[{"left":"x","right":"x"}],"max_output_rows":10,"select":{"aql_chain_column_2":"right.x","aql_chain_column_3":"right.y","aql_chain_column_4":"left.x","aql_chain_column_5":"left.y"}},"as":"aql_chain_join_2"},{"from":"aql_chain_join_2","select":[{"key":"aql_chain_column_4"},{"left_y":"aql_chain_column_3"},{"right_y":"aql_chain_column_5"}],"as":"aql_chain_result_3"}],"results":{"rows":{"from":"aql_chain_result_3","fields":["key","left_y","right_y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  let actual = compile(
    @query.parse_query(
      "FROM t AS l |> RIGHT JOIN t AS r USING (x) MAX_OUTPUT_ROWS 10 |> RENAME x AS key |> SELECT key, l.y AS left_y, r.y AS right_y",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Pipe RENAME refuses an ambiguous target even when a later SELECT hides it" {
  for target in ["x", "X", "`x`", "`X`"] {
    assert_true(
      compile(
        @query.parse_query(
          "FROM t AS l |> RIGHT JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10 |> RENAME " +
          target +
          " AS key |> SELECT l.x AS left_x, r.x AS right_x",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=target,
    )
  }
}

///|
test "Pipe RENAME cannot publish duplicate output names or rename missing targets" {
  assert_true(
    compile(
      @query.parse_query("FROM pair |> RENAME x AS y", syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
  for names in ["missing AS z", "x AS z, X AS other"] {
    let result = compile(
      @query.parse_query(
        "FROM pair |> RENAME " + names + " |> SELECT y",
        syntax_limits(),
      ).unwrap(),
      pair_context(),
      construction_limits(),
    )
    if names == "missing AS z" {
      assert_true(result is Err(UnknownColumn), msg=names)
    } else {
      assert_true(result is Err(DuplicateOutput), msg=names)
    }
  }
}

///|
test "Pipe RENAME INNER JOIN script routing uses the shared current-row scope" {
  let source = "FROM t AS l |> JOIN (SELECT 2 AS x) AS r ON l.x = r.x MAX_OUTPUT_ROWS 10 |> RENAME y AS current |> SELECT current, l.x AS original, r.x AS matched |> ORDER BY original"
  let result = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  )
  let actual = match result {
    Ok(program) => program
    Err(UnsupportedJoin) => fail("projection-only JOIN cannot process RENAME")
    Err(UnsupportedCte) =>
      fail("specialized JOIN requires SELECT before RENAME")
    Err(_) => fail("another script routing refusal")
  }
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent INNER JOIN script has closed inputs")
  }
}
