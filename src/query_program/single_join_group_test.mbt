///|
test "single JOIN GROUP agrees with an independent complete Program" {
  // This fixture uses existing join/group/filter/sort/select contracts. The
  // authored ceiling is 10; physical names only bind the scoped input values.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_chain_source_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_chain_source_0":{"from":"t","fields":["x","y"]}}},{"id":"aql_chain_source_1","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"}],"results":{"aql_chain_source_1":{"from":"r","fields":["k"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_1":{"result":{"stage":"aql_chain_source_1","result":"aql_chain_source_1"}}},"steps":[{"from":"aql_chain_input_0","join":{"with":"aql_chain_input_1","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.k"}},"as":"aql_chain_join_2"},{"from":"aql_chain_join_2","group":{"by":["aql_chain_column_2"],"aggregates":{"n":{"fn":"count"}}}},{"filter":{"gt":[{"field":"n"},{"literal":0}]}},{"sort":[{"field":"aql_chain_column_2","dir":"asc","nulls":"first"}]},{"select":[{"x":"aql_chain_column_2"},"n"],"as":"aql_chain_result_3"}],"results":{"rows":{"from":"aql_chain_result_3","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent single-JOIN Values inputs must be closed")
  }
  let generated = compile(
    @query.parse_query(
      "SELECT t.x, COUNT(*) AS n FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 GROUP BY t.x HAVING n > 0 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
}

///|
test "single JOIN GROUP preserves script and CTE binding paths" {
  for
    source in [
      "SELECT t.x, COUNT(*) AS n FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 GROUP BY t.x HAVING COUNT(*) > 0 ORDER BY x",
      "WITH a AS (SELECT x, y FROM t), b AS (SELECT k FROM r) SELECT a.x, COUNT(*) AS n FROM a JOIN b ON a.x = b.k MAX_OUTPUT_ROWS 10 GROUP BY a.x HAVING n > 0 ORDER BY x",
      "WITH a AS (SELECT x, y FROM t), b AS (SELECT k FROM r), summary AS (SELECT a.x, COUNT(*) AS n FROM a JOIN b ON a.x = b.k MAX_OUTPUT_ROWS 10 GROUP BY a.x HAVING n > 0) SELECT x, n FROM summary ORDER BY x",
      "WITH a AS (SELECT x FROM t) SELECT x, COUNT(*) AS n FROM a GROUP BY x HAVING n > 0 ORDER BY x",
    ] {
    for
      program in [
        compile(
          @query.parse_query(source, syntax_limits()).unwrap(),
          join_order_context(),
          construction_limits(),
        ).unwrap(),
        compile_query_script(
          @query.parse_query_script(source, syntax_limits()).unwrap(),
          join_order_context(),
          construction_limits(),
        ).unwrap(),
      ] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        Rejected(error) => raise @check.diagnostic_cause(error)
        _ =>
          fail(
            "grouped JOIN and zero-JOIN CTE Values inputs must remain closed",
          )
      }
    }
  }
}

///|
test "single JOIN GROUP retains concrete key and scope refusals" {
  for
    source in [
      "SELECT t.x, COUNT(*) AS n FROM t JOIN r ON t.x > r.k MAX_OUTPUT_ROWS 10 GROUP BY t.x",
      "SELECT t.x, COUNT(*) AS n FROM t FULL JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 GROUP BY t.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedJoin),
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT t.y, COUNT(*) AS n FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 GROUP BY t.x",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}
