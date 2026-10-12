///|
fn staged_join_pipe_edit_expected(
  tail : String,
  fields : String,
) -> @program.Program {
  // Independent ordinary JOIN, evaluated-value edits and projection. The two
  // input definitions and all explicit key/ceiling premises are retained.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_chain_source_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_chain_source_0":{"from":"t","fields":["x","y"]}}},{"id":"aql_chain_source_1","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"}],"results":{"aql_chain_source_1":{"from":"r","fields":["k"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_1":{"result":{"stage":"aql_chain_source_1","result":"aql_chain_source_1"}}},"steps":[{"from":"aql_chain_input_0","join":{"with":"aql_chain_input_1","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.k"}},"as":"aql_chain_join_2"},
    ) +
    tail +
    (
      #|],"results":{"rows":{"from":"aql_chain_result_3","fields":
    ) +
    fields +
    (
      #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
// Build the complete current topology from the original named Values and
// unchanged authored continuation. Binding names follow the installed seed
// roles; no compiler output is used to generate this control.
fn join_pipe_edit_expected(
  tail : String,
  fields : String,
) -> @program.Program raise {
  check_staged_values_join_oracle(staged_join_pipe_edit_expected(tail, fields))
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"aql_script_seed_2"},{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_2","join":{"with":"aql_script_seed_3","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.k"}},"as":"aql_chain_join_4"},
    ) +
    shared_values_chain_tail_oracle(tail) +
    (
      #|],"results":{"rows":{"from":"aql_chain_result_5","fields":
    ) +
    fields +
    (
      #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn check_join_pipe_edit(
  source : String,
  expected : @program.Program,
) -> Unit raise {
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent JOIN edit control is closed")
  }
  let query = @query.parse_query(source, syntax_limits()).unwrap()
  let scripted = compile_query_script(
    @query.single_query_script(query),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(scripted, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the script JOIN edit uses the normal closed Program")
  }
  let actual = compile(query, join_order_context(), construction_limits()).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "post-JOIN SET keeps the original range value and edits the current column" {
  let expected = join_pipe_edit_expected(
    "{\"from\":\"aql_chain_join_2\",\"derive\":{\"aql_pipe_set_3\":{\"add\":[{\"field\":\"aql_chain_column_3\"},{\"literal\":10}]}}},{\"sort\":[{\"field\":\"aql_chain_column_3\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"current\":\"aql_pipe_set_3\"},{\"original\":\"aql_chain_column_3\"},{\"matched\":\"aql_chain_column_4\"}],\"as\":\"aql_chain_result_3\"}",
    "[\"current\",\"original\",\"matched\"]",
  )
  check_join_pipe_edit(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SET y = y + 10 |> SELECT y AS current, l.y AS original, rr.k AS matched |> ORDER BY original",
    expected,
  )
}

///|
test "post-JOIN DROP removes current columns while retaining surviving range slots" {
  let expected = join_pipe_edit_expected(
    "{\"from\":\"aql_chain_join_2\",\"sort\":[{\"field\":\"aql_chain_column_3\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"original\":\"aql_chain_column_3\"},{\"matched\":\"aql_chain_column_4\"}],\"as\":\"aql_chain_result_3\"}",
    "[\"original\",\"matched\"]",
  )
  check_join_pipe_edit(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> DROP y |> SELECT l.y AS original, rr.k AS matched |> ORDER BY original",
    expected,
  )
}

///|
test "post-JOIN EXTEND derives a new current slot without extending the old range" {
  let expected = join_pipe_edit_expected(
    "{\"from\":\"aql_chain_join_2\",\"derive\":{\"aql_pipe_extend_3\":{\"add\":[{\"field\":\"aql_chain_column_3\"},{\"literal\":10}]}}},{\"sort\":[{\"field\":\"aql_chain_column_3\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"current\":\"aql_pipe_extend_3\"},{\"original\":\"aql_chain_column_3\"},{\"matched\":\"aql_chain_column_4\"}],\"as\":\"aql_chain_result_3\"}",
    "[\"current\",\"original\",\"matched\"]",
  )
  check_join_pipe_edit(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> EXTEND y + 10 AS current |> SELECT current, l.y AS original, rr.k AS matched |> ORDER BY original",
    expected,
  )
}

///|
test "post-JOIN edits retain exact current-target and range failures" {
  let prefix = "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> "
  for tail in ["DROP y |> SELECT y", "EXTEND y + 10 AS z |> SELECT l.z"] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(prefix + tail, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=tail,
    )
  }
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        prefix + "SET missing = 1 |> SELECT l.x",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        "FROM t AS l |> JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10 |> SET x = 1 |> SELECT l.x",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
}
