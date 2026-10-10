///|
test "Pipe UNPIVOT has an independent checked common Program control" {
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","unpivot":{"columns":["x","y"],"keep":[],"name_column":"column_name","value_column":"amount"}},{"select":["amount","column_name"],"as":"reshaped"}],"results":{"rows":{"from":"reshaped","fields":["amount","column_name"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(control, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("the independent Values control is closed")
  }
}

///|
test "Pipe UNPIVOT connects the existing operation without rewriting its input" {
  let actual = compile(
    @query.parse_query(
      "FROM pair |> UNPIVOT INCLUDE NULLS (amount FOR column_name IN (x, y))",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("UNPIVOT introduces no new input acquisition")
  }
}

///|
test "Pipe UNPIVOT has a complete independently authored lowering and output order" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","select":[{"aql_unpivot_input_0":"x"},{"aql_unpivot_input_1":"y"}]},{"unpivot":{"columns":["aql_unpivot_input_0","aql_unpivot_input_1"],"keep":[],"name_column":"aql_unpivot_name_2","value_column":"aql_unpivot_value_3"}},{"derive":{"aql_unpivot_label_4":{"if":[{"eq":[{"field":"aql_unpivot_name_2"},{"literal":"aql_unpivot_input_0"}]},{"literal":"x"},{"literal":"y"}]}}},{"select":[{"amount":"aql_unpivot_value_3"},{"column_name":"aql_unpivot_label_4"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["amount","column_name"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "FROM pair |> UNPIVOT INCLUDE NULLS (amount FOR column_name IN (x,y))", "FROM pair |> UNPIVOT INCLUDE NULLS (amount FOR column_name IN (`X`,`Y`)) AS current |> SELECT current.amount, current.column_name",
      "FROM pair |> UNPIVOT INCLUDE NULLS (amount FOR column_name IN (x,y)) current |> SELECT *",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}

///|
test "UNPIVOT default NULL exclusion is one ordinary filter before the explicit sort" {
  for modifier in ["", "EXCLUDE NULLS "] {
    let actual = compile(
      @query.parse_query(
        "FROM pair |> UNPIVOT " +
        modifier +
        "(amount FOR column_name IN (x,y)) |> ORDER BY amount DESC |> LIMIT 1",
        syntax_limits(),
      ).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    let wire = semantic(actual)
    let filter = "\"filter\":{\"not\":{\"is_null\":{\"field\":\"aql_unpivot_value_3\"}}}"
    assert_true(wire.contains(filter))
    assert_true(
      wire.contains(
        "\"sort\":[{\"dir\":\"desc\",\"field\":\"aql_unpivot_value_3\",\"nulls\":\"last\"}]",
      ),
      msg=wire,
    )
    assert_true(wire.contains("\"take\":{\"count\":1,\"offset\":0}"))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) =>
        fail("UNPIVOT and its filter are ordinary closed operations")
    }
  }
}

///|
test "UNPIVOT reads current slots and removes consumed columns and old ranges" {
  for
    text in [
      "FROM pair AS old |> UNPIVOT(v FOR k IN (x,y)) |> SELECT old.x", "FROM pair |> UNPIVOT(v FOR k IN (x,y)) |> SELECT x",
      "FROM pair |> UNPIVOT(v FOR k IN (x,y)) |> ORDER BY pair.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=text,
    )
  }
  let actual = compile(
    @query.parse_query(
      "FROM pair AS old |> SET x = 99 |> RENAME y AS january |> UNPIVOT INCLUDE NULLS(v FOR k IN (x,january)) |> SELECT v,k",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(actual)
  assert_true(wire.contains("{\"aql_unpivot_input_0\":\"aql_pipe_set_2\"}"))
  assert_true(wire.contains("\"literal\":\"january\""))
  assert_false(wire.contains("\"literal\":\"aql_pipe_set_2\""))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "UNPIVOT leaves exact type validation to the common checker" {
  let actual = compile(
    @query.parse_query(
      "FROM orders |> UNPIVOT(v FOR k IN (status,amount))",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Rejected(_),
  )
  for
    (text, issue) in [
      ("FROM pair |> UNPIVOT(v FOR k IN (missing))", "unknown"),
      ("FROM pair |> UNPIVOT(x FOR k IN (x,y))", "duplicate"),
      ("FROM pair |> UNPIVOT(v FOR V IN (x,y))", "duplicate"),
    ] {
    let result = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    )
    assert_true(
      match (result, issue) {
        (Err(UnknownColumn), "unknown") => true
        (Err(DuplicateOutput), "duplicate") => true
        _ => false
      },
      msg=text,
    )
  }
}
