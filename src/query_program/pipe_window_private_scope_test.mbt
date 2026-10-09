///|
fn checked_pipe_private_window(text : String, field : String) -> String raise {
  let program = match
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      select_window_private_context(field),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(Expression(diagnostic)) =>
      fail(text + ": " + @debug.to_string(diagnostic.issue))
    Err(_) => fail(text + ": unexpected lowering refusal")
  }
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent schema is closed")
  }
  semantic(program)
}

///|
test "Pipe WHERE window does not confuse a schema-only public name" {
  for field in ["aql_pipe_where_window_0", "AQL_PIPE_WHERE_WINDOW_0"] {
    let body = checked_pipe_private_window(
      "FROM records |> AS r |> WHERE ROW_NUMBER() OVER (ORDER BY id) = 1 |> ORDER BY id",
      field,
    )
    assert_true(body.contains("\"fields\":[\"id\",\"" + field + "\"]"))
    // Two inputs reserve the private analytic output at slot 2.
    assert_true(
      body.contains(
        "\"eq\":[{\"field\":\"aql_analytic_output_2\"},{\"literal\":1}]",
      ),
    )
  }
}

///|
test "Pipe EXTEND window does not confuse a schema-only public name" {
  for field in ["aql_select_window_0", "AQL_SELECT_WINDOW_0"] {
    let body = checked_pipe_private_window(
      "FROM records |> AS r |> EXTEND ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos |> ORDER BY id DESC",
      field,
    )
    assert_true(body.contains("\"fields\":[\"id\",\"" + field + "\",\"pos\"]"))
    // EXTEND reserves pos in addition to the two inputs.
    assert_true(
      body.contains(
        "\"add\":[{\"field\":\"aql_analytic_output_3\"},{\"literal\":1}]",
      ),
    )
  }
}

///|
test "Pipe SET window does not confuse a schema-only public name" {
  for field in ["aql_pipe_set_window_0", "AQL_PIPE_SET_WINDOW_0"] {
    let body = checked_pipe_private_window(
      "FROM records |> AS r |> SET id = ROW_NUMBER() OVER (ORDER BY id) + 10 |> ORDER BY id DESC",
      field,
    )
    assert_true(body.contains("\"fields\":[\"id\",\"" + field + "\"]"))
    assert_true(
      body.contains(
        "\"add\":[{\"field\":\"aql_analytic_output_2\"},{\"literal\":10}]",
      ),
    )
  }
}

///|
test "Pipe private window consumers keep authored and immutable inputs" {
  for
    (text, field) in [
      (
        "FROM records |> AS r |> WHERE ROW_NUMBER() OVER (ORDER BY r.id) = 1 |> ORDER BY id",
        "aql_pipe_where_window_0",
      ),
      (
        "FROM records |> AS r |> EXTEND ROW_NUMBER() OVER (ORDER BY aql_select_window_0) + 1 AS pos |> ORDER BY id DESC",
        "aql_select_window_0",
      ),
      (
        "FROM records |> AS r |> SET id = ROW_NUMBER() OVER (ORDER BY id) + 10 |> SELECT r.id AS original, * |> ORDER BY id DESC",
        "aql_pipe_set_window_0",
      ),
    ] {
    ignore(checked_pipe_private_window(text, field))
  }
}

///|
test "Pipe consumers do not expose a private physical window to the next scope" {
  for
    (operation, field, slot) in [
      (
        "WHERE ROW_NUMBER() OVER (ORDER BY id) = 1", "aql_pipe_where_window_0", "aql_analytic_output_2",
      ),
      (
        "EXTEND ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos", "aql_select_window_0",
        "aql_analytic_output_3",
      ),
      (
        "SET id = ROW_NUMBER() OVER (ORDER BY id) + 10", "aql_pipe_set_window_0",
        "aql_analytic_output_2",
      ),
    ] {
    let query = @query.parse_query(
      "FROM records |> AS r |> " + operation + " |> SELECT " + slot,
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile(
        query,
        select_window_private_context(field),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
    )
  }
}
