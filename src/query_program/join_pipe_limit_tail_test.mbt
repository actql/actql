///|
fn staged_join_pipe_limit_tail_expected(
  tail : String,
  fields : String,
) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_join_left","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_join_left":{"from":"t","fields":["x","y"]}}},{"id":"aql_join_right","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"}],"results":{"aql_join_right":{"from":"r","fields":["k"]}}},{"id":"main","inputs":{"l":{"result":{"stage":"aql_join_left","result":"aql_join_left"}},"r":{"result":{"stage":"aql_join_right","result":"aql_join_right"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"id":"left.x","amount":"left.y"}},"as":"aql_join_output"},{"from":"aql_join_output","sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_join_sorted"},{"from":"aql_join_sorted","take":{"count":1,"offset":1},"as":"aql_join_taken"},
    ) +
    tail +
    (
      #|],"results":{"rows":{"from":"aql_join_result","fields":
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
fn join_pipe_limit_tail_expected(tail : String, fields : String) -> @program.Program raise {
  check_staged_values_join_oracle(staged_join_pipe_limit_tail_expected(tail, fields))
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"aql_script_seed_2"},{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_2","join":{"with":"aql_script_seed_3","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"id":"left.x","amount":"left.y"}},"as":"aql_join_output_5"},{"from":"aql_join_output_5","sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_join_sorted_11"},{"from":"aql_join_sorted_11","take":{"count":1,"offset":1},"as":"aql_join_taken_12"},
    ) +
    shared_values_specialized_tail_oracle(tail) +
    (
      #|],"results":{"rows":{"from":"aql_join_result_14","fields":
    ) + fields +
    (
      #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}


///|
fn join_pipe_limit_tail_source() -> String {
  "FROM t |> JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 |> SELECT t.x AS id, t.y AS amount |> ORDER BY id |> LIMIT 1 OFFSET 1"
}

///|
test "JOIN Pipe consecutive LIMIT preserves each independent take" {
  let expected = join_pipe_limit_tail_expected(
    "{\"from\":\"aql_join_taken\",\"take\":{\"count\":1,\"offset\":0},\"as\":\"aql_join_result\"}",
    "[\"id\",\"amount\"]",
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    source in [
      join_pipe_limit_tail_source() + " |> LIMIT 1",
      "SELECT t.x AS id, t.y AS amount FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY id LIMIT 1 OFFSET 1 |> LIMIT 1",
    ] {
    let actual = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedJoin) =>
        fail("UnsupportedJoin refused a second supported take")
      Err(_) => fail("another refusal")
    }
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "JOIN Pipe WHERE and projection consume the already limited output" {
  let expected = join_pipe_limit_tail_expected(
    "{\"from\":\"aql_join_taken\",\"filter\":{\"eq\":[{\"field\":\"id\"},{\"literal\":2}]}},{\"select\":[\"id\"],\"as\":\"aql_join_result\"}",
    "[\"id\"]",
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  let actual = match
    compile(
      @query.parse_query(
        join_pipe_limit_tail_source() + " |> WHERE id = 2 |> SELECT id",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedJoin) =>
      fail("UnsupportedJoin refused a current-column tail")
    Err(_) => fail("another refusal")
  }
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "JOIN Pipe limited output does not restore SELECT input ranges" {
  assert_true(
    compile(
      @query.parse_query(
        join_pipe_limit_tail_source() + " |> WHERE t.x = 2 |> SELECT id",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: UnknownReference, .. })),
  )
}

///|
test "JOIN Pipe pure continuation works through the public script lowerer" {
  for
    source in [
      join_pipe_limit_tail_source() + " |> LIMIT 1",
      join_pipe_limit_tail_source() + " |> WHERE id = 2 |> SELECT id",
      "SELECT t.x AS id, t.y AS amount FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 |> ORDER BY id |> LIMIT 1 OFFSET 1 |> LIMIT 1",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("all inputs are independently supplied Values")
    }
    assert_true(semantic(program).contains("\"count\":1,\"offset\":1"))
    assert_true(semantic(program).contains("\"max_output_rows\":10"))
  }
}
