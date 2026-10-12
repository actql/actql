///|
fn staged_join_current_row_expected(
  tail : String,
  fields : String,
) -> @program.Program {
  // Independent JOIN followed by the authored operations in their original
  // order. The right key and ceiling do not change to admit the continuation.
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
fn join_current_row_expected(tail : String, fields : String) -> @program.Program raise {
  check_staged_values_join_oracle(staged_join_current_row_expected(tail, fields))
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"aql_script_seed_2"},{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_2","join":{"with":"aql_script_seed_3","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.k"}},"as":"aql_chain_join_4"},
    ) +
    shared_values_chain_tail_oracle(tail) +
    (
      #|],"results":{"rows":{"from":"aql_chain_result_5","fields":
    ) + fields +
    (
      #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}


///|
fn check_join_current_row(
  source : String,
  expected : @program.Program,
) -> Unit raise {
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent JOIN current-row control is closed")
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
    _ => fail("the current-row script retains the ordinary closed inputs")
  }
  let actual = compile(query, join_order_context(), construction_limits()).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "JOIN current-row ORDER and LIMIT precede projection" {
  let expected = join_current_row_expected(
    "{\"from\":\"aql_chain_join_2\",\"sort\":[{\"field\":\"aql_chain_column_3\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"take\":{\"count\":1,\"offset\":0}},{\"select\":[{\"x\":\"aql_chain_column_2\"},{\"y\":\"aql_chain_column_3\"}],\"as\":\"aql_chain_result_3\"}",
    "[\"x\",\"y\"]",
  )
  check_join_current_row(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> ORDER BY l.y |> LIMIT 1 |> SELECT l.x AS x, l.y AS y",
    expected,
  )
}

///|
test "JOIN current-row WHERE after LIMIT cannot move before the take" {
  let expected = join_current_row_expected(
    "{\"from\":\"aql_chain_join_2\",\"sort\":[{\"field\":\"aql_chain_column_3\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"take\":{\"count\":1,\"offset\":0}},{\"filter\":{\"eq\":[{\"field\":\"aql_chain_column_4\"},{\"literal\":1}]}},{\"select\":[{\"x\":\"aql_chain_column_2\"},{\"y\":\"aql_chain_column_3\"}],\"as\":\"aql_chain_result_3\"}",
    "[\"x\",\"y\"]",
  )
  check_join_current_row(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> ORDER BY l.y |> LIMIT 1 |> WHERE rr.k = 1 |> SELECT l.x AS x, l.y AS y",
    expected,
  )
}

///|
test "JOIN current-row consecutive WHERE retains each predicate" {
  let expected = join_current_row_expected(
    "{\"from\":\"aql_chain_join_2\",\"filter\":{\"gt\":[{\"field\":\"aql_chain_column_2\"},{\"literal\":0}]}},{\"filter\":{\"eq\":[{\"field\":\"aql_chain_column_4\"},{\"literal\":2}]}},{\"sort\":[{\"field\":\"aql_chain_column_2\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"x\":\"aql_chain_column_2\"}],\"as\":\"aql_chain_result_3\"}",
    "[\"x\"]",
  )
  check_join_current_row(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> WHERE l.x > 0 |> WHERE rr.k = 2 |> SELECT l.x AS x |> ORDER BY x",
    expected,
  )
}

///|
test "JOIN current-row AS binds the full evaluated visible row" {
  let expected = join_current_row_expected(
    "{\"from\":\"aql_chain_join_2\",\"sort\":[{\"field\":\"aql_chain_column_2\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[{\"x\":\"aql_chain_column_2\"}],\"as\":\"aql_chain_result_3\"}",
    "[\"x\"]",
  )
  check_join_current_row(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> AS joined |> SELECT joined.x AS x |> ORDER BY x",
    expected,
  )
}

///|
test "JOIN current-row query without SELECT retains all visible columns" {
  let expected = join_current_row_expected(
    "{\"from\":\"aql_chain_join_2\",\"sort\":[{\"field\":\"aql_chain_column_3\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"take\":{\"count\":1,\"offset\":0}},{\"select\":[{\"x\":\"aql_chain_column_2\"},{\"y\":\"aql_chain_column_3\"},{\"k\":\"aql_chain_column_4\"}],\"as\":\"aql_chain_result_3\"}",
    "[\"x\",\"y\",\"k\"]",
  )
  check_join_current_row(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> ORDER BY l.y |> LIMIT 1",
    expected,
  )
}

///|
test "JOIN current-row AS does not restore either input range" {
  for
    source in [
      "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> AS joined |> WHERE l.x > 0 |> SELECT joined.x AS x",
      "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> AS joined |> ORDER BY rr.k |> SELECT joined.x AS x",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    assert_true(
      compile(query, join_order_context(), construction_limits())
      is Err(Expression({ issue: UnknownReference, .. })),
    )
    assert_true(
      compile_query_script(
        @query.single_query_script(query),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
    )
  }
}
