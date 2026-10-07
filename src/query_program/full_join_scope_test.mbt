///|
test "FULL joined-row scope retains explicit checked identity premises" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_chain_source_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"assert_rows":{"unique_by":["x"]},"as":"t_keyed"}],"results":{"aql_chain_source_0":{"from":"t_keyed","fields":["x","y"]}}},{"id":"aql_chain_source_1","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"},{"assert_rows":{"unique_by":["k"]},"as":"r_keyed"}],"results":{"aql_chain_source_1":{"from":"r_keyed","fields":["k"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_1":{"result":{"stage":"aql_chain_source_1","result":"aql_chain_source_1"}}},"steps":[{"from":"aql_chain_input_0","join":{"with":"aql_chain_input_1","kind":"full","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.k"}},"as":"aql_chain_join_2"},{"sort":[{"field":"aql_chain_column_4","dir":"asc","nulls":"last"}]},{"select":[{"x":"aql_chain_column_2"},{"y":"aql_chain_column_3"},{"k":"aql_chain_column_4"}],"as":"aql_chain_result_3"}],"results":{"rows":{"from":"aql_chain_result_3","fields":["x","y","k"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Closure(Joins(MissingEvidence(index))) =>
          fail("missing join identity evidence at " + index.to_string())
        cause => raise cause
      }
    _ => fail("independent FULL inputs must retain genuine identity evidence")
  }
  let generated = compile_query_script(
    @query.parse_query_script(
      "DATA lefts = FROM t |> ASSERT UNIQUE BY (x); DATA rights = FROM r |> ASSERT UNIQUE BY (k); SELECT * FROM lefts AS t FULL JOIN rights AS r ON t.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY k NULLS LAST",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(generated, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("FULL source inputs must retain their checked key obligations")
  }
  assert_true(semantic(generated).contains("\"kind\":\"full\""))
}

///|
test "unkeyed FULL joined-row scope keeps the common identity refusal" {
  let generated = compile(
    @query.parse_query(
      "SELECT t.x, COUNT(*) AS n FROM t FULL JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 GROUP BY t.x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(generated, check_environment(), None, check_limits()) {
    Rejected(error) =>
      assert_true(
        @check.diagnostic_cause(error) is Closure(Joins(MissingEvidence(_))),
      )
    _ => fail("FULL must not invent a key for a Values producer")
  }
}

///|
test "FULL shared scope retains unsupported USING and invalid ON refusals" {
  for
    source in [
      "SELECT * FROM t AS l FULL JOIN t AS r USING (x) MAX_OUTPUT_ROWS 10", "SELECT * FROM t FULL JOIN r ON t.x > r.k MAX_OUTPUT_ROWS 10",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedJoin),
      msg=source,
    )
  }
}
