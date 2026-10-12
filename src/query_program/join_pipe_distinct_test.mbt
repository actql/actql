///|
fn staged_join_pipe_distinct_expected() -> @program.Program {
  // Both consumers share one producer. DISTINCT compares all four evaluated
  // JOIN values before the later projection, including the unselected y slot.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_chain_source_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_chain_source_0":{"from":"t","fields":["x","y"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_1":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}}},"steps":[{"from":"aql_chain_input_0","join":{"with":"aql_chain_input_1","kind":"inner","on":[{"left":"x","right":"x"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.x","aql_chain_column_5":"right.y"}},"as":"aql_chain_join_2"},{"from":"aql_chain_join_2","distinct":["aql_chain_column_2","aql_chain_column_3","aql_chain_column_4","aql_chain_column_5"]},{"sort":[{"field":"aql_chain_column_2","dir":"asc","nulls":"first"}]},{"select":[{"x":"aql_chain_column_2"},{"y":"aql_chain_column_5"}],"as":"aql_chain_result_3"}],"results":{"rows":{"from":"aql_chain_result_3","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}


///|
// Independent current-Unit control: retain the original typed Values and all
// operator bodies. Only their checked binding coordinates change.
fn join_pipe_distinct_expected() -> @program.Program raise {
  check_staged_values_join_oracle(staged_join_pipe_distinct_expected())
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","join":{"with":"aql_script_seed_2","kind":"inner","on":[{"left":"x","right":"x"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.x","aql_chain_column_5":"right.y"}},"as":"aql_chain_join_3"},{"from":"aql_chain_join_3","distinct":["aql_chain_column_2","aql_chain_column_3","aql_chain_column_4","aql_chain_column_5"]},{"sort":[{"field":"aql_chain_column_2","dir":"asc","nulls":"first"}]},{"select":[{"x":"aql_chain_column_2"},{"y":"aql_chain_column_5"}],"as":"aql_chain_result_4"}],"results":{"rows":{"from":"aql_chain_result_4","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}


///|
test "post-JOIN Pipe DISTINCT uses the complete independently checked current row" {
  let expected = join_pipe_distinct_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent DISTINCT JOIN control is closed")
  }
  let actual = compile(
    @query.parse_query(
      "FROM t AS l |> JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10 |> DISTINCT |> SELECT l.x AS x, r.y AS y |> ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "post-JOIN Pipe DISTINCT admits a CROSS JOIN without inventing a predicate" {
  let actual = compile(
    @query.parse_query(
      "FROM t AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10 |> DISTINCT |> SELECT l.x AS x, rr.k AS k |> ORDER BY x, k",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the CROSS DISTINCT control is closed")
  }
}

///|
test "post-JOIN Pipe DISTINCT preserves ranges only until explicit projection" {
  for
    source in [
      "FROM t AS l |> JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10 |> DISTINCT |> SELECT l.x AS x |> DISTINCT |> SELECT l.x",
      "SELECT l.x AS x FROM t AS l JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10 |> DISTINCT |> SELECT l.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=source,
    )
  }
}
