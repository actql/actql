///|
test "Pipe SET refuses an ambiguous current target before lowering its value" {
  for target in ["x", "X", "`x`", "`X`"] {
    for expression in ["99", "ROW_NUMBER() OVER (ORDER BY r.x)"] {
      let source = "FROM t AS l |> RIGHT JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10 |> SET " +
        target +
        " = " +
        expression +
        " |> SELECT l.x AS left_x, r.x AS right_x"
      let result = compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      match result {
        Err(AmbiguousColumn) => ()
        Err(DuplicateOutput) => fail("DuplicateOutput: " + source)
        Err(UnsupportedJoin) => fail("UnsupportedJoin: " + source)
        Err(UnsupportedCte) => fail("UnsupportedCte: " + source)
        Err(Expression(_)) => fail("Expression: " + source)
        Err(_) => fail("another refusal: " + source)
        Ok(program) => fail("ambiguous SET accepted: " + semantic(program))
      }
    }
  }
}

///|
test "Pipe SET preserves one current target and its immutable JOIN range" {
  // Independent RIGHT JOIN -> derive -> projection. The common right input
  // is preserved via a left JOIN; only the current x slot is replaced.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_chain_source_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_chain_source_0":{"from":"t","fields":["x","y"]}}},{"id":"aql_chain_source_1","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"}],"results":{"aql_chain_source_1":{"from":"r","fields":["k"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_1":{"result":{"stage":"aql_chain_source_1","result":"aql_chain_source_1"}}},"steps":[{"from":"aql_chain_input_1","join":{"with":"aql_chain_input_0","kind":"left","on":[{"left":"k","right":"x"}],"max_output_rows":10,"select":{"aql_chain_column_2":"right.x","aql_chain_column_3":"right.y","aql_chain_column_4":"left.k"}},"as":"aql_chain_join_2"},{"from":"aql_chain_join_2","derive":{"aql_pipe_set_3":{"literal":99}}},{"select":[{"replaced":"aql_pipe_set_3"},{"original":"aql_chain_column_2"},{"matched":"aql_chain_column_4"}],"as":"aql_chain_result_3"}],"results":{"rows":{"from":"aql_chain_result_3","fields":["replaced","original","matched"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent scalar SET control has closed inputs")
  }
  let actual = compile(
    @query.parse_query(
      "FROM t AS l |> RIGHT JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SET x = 99 |> SELECT x AS replaced, l.x AS original, rr.k AS matched",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Pipe SET counts USING's one coalesced target instead of operand ranges" {
  let source = "FROM t AS l |> RIGHT JOIN t AS r USING (x) MAX_OUTPUT_ROWS 10 |> SET x = 99 |> SELECT x AS replaced, l.x AS left_x, r.x AS right_x"
  let program = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the coalesced USING target is closed")
  }
}
