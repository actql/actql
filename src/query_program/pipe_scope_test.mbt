///|
test "Pipe AS replaces old ranges and can rebind the same name" {
  for
    source in [
      "FROM pair AS before |> SET x = y |> AS later |> SELECT later.x AS new_x, later.y AS y",
      "FROM pair AS before |> SET x = y |> AS before |> SELECT before.x AS new_x, before.y AS y",
      "FROM pair AS before |> SET x = y |> AS `BEFORE` |> SELECT `before`.`X` AS new_x, `Before`.`Y` AS y",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      semantic(program).contains(
        "\"select\":[{\"new_x\":\"aql_pipe_set_2\"},\"y\"]",
      ),
    )
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("Values inputs are closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "Pipe AS removes initial and intermediate names from every reference scope" {
  for
    source in [
      "FROM pair AS before |> AS later |> SELECT before.x", "FROM pair AS before |> AS later |> SELECT before.x + 1 AS x",
      "FROM pair AS before |> AS later |> WHERE before.x = 1 |> SELECT x", "FROM pair AS before |> AS later |> SELECT x |> ORDER BY before.x",
      "FROM pair |> AS later |> SELECT pair.x", "FROM pair AS before |> AS middle |> AS later |> SELECT middle.x",
      "FROM pair AS before |> AS later |> SELECT x |> WHERE before.x = 1", "FROM pair AS before |> AS later |> SELECT x |> SELECT before.x",
      "FROM pair AS before |> AS later |> SELECT x |> EXTEND before.x AS z", "FROM pair AS before |> DROP x |> AS later |> SELECT later.x",
      "FROM pair AS before |> RENAME x AS z |> AS later |> SELECT later.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(_),
      msg=source,
    )
  }
}

///|
test "Pipe AS replacement survives SELECT with valid current column expressions" {
  for
    source in [
      "FROM pair AS before |> AS later |> SELECT later.x AS x |> WHERE x > 0 |> SELECT x",
      "FROM pair AS before |> AS later |> SELECT later.x AS x |> EXTEND x + 1 AS z |> SELECT z, x",
      "FROM pair AS before |> AS later |> SELECT later.x AS x |> SET x = x + 1 |> SELECT x",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("Values inputs are closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "Pipe AS sees only current names after DROP and RENAME" {
  let program = compile(
    @query.parse_query(
      "FROM pair AS before |> DROP y |> RENAME x AS z |> AS later |> SELECT later.z AS z",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(program).contains("\"select\":[{\"z\":\"x\"}]"))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("Values inputs are closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}
