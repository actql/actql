///|
test "whole row reference has an independent checked object Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.whole_row_range","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"element":{"type":"number","nullable":true},"position":{"type":"number","nullable":false}},"rows":[{"element":2,"position":0},{"element":null,"position":1},{"element":2,"position":2}]},"as":"rows"},{"from":"rows","derive":{"row":{"object":{"element":{"field":"element"},"position":{"field":"position"}}}}},{"select":["row",{"value":"element"},"position"]},{"sort":[{"field":"position","dir":"asc","nulls":"first"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["row","value","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed object control")
  }
}

///|
test "ordinary derived range can be selected as its row object" {
  let actual = match
    compile(
      @query.parse_query(
        "SELECT chosen AS row,chosen.element AS value,chosen.position FROM (FROM UNNEST(@items) element WITH OFFSET position) chosen ORDER BY position",
        syntax_limits(),
      ).unwrap(),
      {
        ..values_context(),
        inputs: [],
        parameter_declarations: Some(unnest_parameters()),
      },
      construction_limits(),
    ) {
    Ok(p) => p
    Err(Expression({ issue: @expression.UnknownReference, .. })) =>
      fail("row range: UnknownReference")
    Err(_) => fail("row range: other lowering refusal")
  }
  match
    @check.check_parsed(
      actual,
      check_environment(numeric=true),
      Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("declared offset row")
  }
}

///|
fn checked_whole_row(source : String) -> String raise {
  let p = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => semantic(p)
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed row input")
  }
}

///|
test "ordinary row projection matches an independently authored complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_query_expr_0":{"object":{"x":{"field":"x"},"y":{"field":"y"}}}}},{"select":[{"row":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["row"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(
    checked_whole_row("SELECT r AS row FROM pair r"),
    semantic(expected),
  )
}

///|
test "ordinary row names and parenthesized receivers retain the declared columns" {
  for
    source in [
      "SELECT r FROM pair r", "FROM pair |> AS r |> SELECT r", "FROM pair |> AS `ORDER` |> SELECT `order` AS row",
      "SELECT COALESCE(r,NULL) AS row FROM pair r", "FROM pair |> AS r |> SELECT IF(TRUE,r,NULL) AS row",
      "FROM pair |> AS r |> SELECT x |> ORDER BY IF(TRUE,r,NULL).y",
    ] {
    let body = checked_whole_row(source)
    assert_true(
      body.contains(
        "\"object\":{\"x\":{\"field\":\"x\"},\"y\":{\"field\":\"y\"}}",
      ),
      msg=source,
    )
  }
}

///|
test "row AS captures slots once while SET changes current columns" {
  let before = checked_whole_row(
    "FROM pair |> AS r |> SET x = y |> SELECT r AS row,x AS current",
  )
  assert_true(
    before.contains(
      "\"object\":{\"x\":{\"field\":\"x\"},\"y\":{\"field\":\"y\"}}",
    ),
  )
  let after = checked_whole_row(
    "FROM pair |> SET x = y |> AS r |> SELECT r AS row,x AS current",
  )
  assert_true(after.contains("\"x\":{\"field\":\"aql_pipe_set_2\"}"))
  let edited = checked_whole_row(
    "FROM pair |> AS r |> DROP y |> RENAME x AS z |> SELECT r AS row,z",
  )
  assert_true(
    edited.contains(
      "\"object\":{\"x\":{\"field\":\"x\"},\"y\":{\"field\":\"y\"}}",
    ),
  )
  let rebound = checked_whole_row(
    "FROM pair |> DROP y |> RENAME x AS z |> AS r |> SELECT r AS row,z",
  )
  assert_true(rebound.contains("\"object\":{\"z\":{\"field\":\"x\"}}"))
}

///|
test "an ordinary input range shadows a same-named column" {
  let body = checked_whole_row("FROM pair |> AS x |> SELECT x AS value")
  // Fixed GoogleSQL NameScope::AddNameTarget gives the input range priority.
  assert_true(
    body.contains(
      "\"object\":{\"x\":{\"field\":\"x\"},\"y\":{\"field\":\"y\"}}",
    ),
  )
}

///|
test "removed row ranges cannot be reconstructed from old slots" {
  for
    source in [
      "FROM pair |> AS r |> AS s |> SELECT r AS row", "FROM pair |> AS r |> SELECT x |> WHERE x > 0 |> SELECT r AS row",
      "FROM pair |> AS r |> DROP x |> AS s |> SELECT r AS row", "FROM pair |> AS r |> SELECT DISTINCT x |> ORDER BY IF(TRUE,r,NULL).y",
    ] {
    let result = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    )
    match result {
      Err(Expression({ issue: @expression.UnknownReference, origin: Some(_), })) =>
        ()
      Err(UnsupportedOrdering) => ()
      Err(InvalidQuery) => assert_true(source.contains("SELECT DISTINCT"))
      Err(ExpressionTyping(issue)) =>
        assert_true(issue.kind is @typing.UnknownField("r"))
      Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
      Err(Expression(issue)) =>
        fail(source + ": " + @debug.to_string(issue.issue))
      Err(_) => fail(source + ": other refusal")
      Ok(_) => fail(source + ": accepted")
    }
  }
}

///|
test "ordinary row retains the original value-table column after SET" {
  let p = compile(
    @query.parse_query(
      "FROM (FROM UNNEST(@items) element WITH OFFSET position) chosen |> SET element = position + 10 |> SELECT chosen AS row,element AS value,position |> ORDER BY position",
      syntax_limits(),
    ).unwrap(),
    {
      ..values_context(),
      inputs: [],
      parameter_declarations: Some(unnest_parameters()),
    },
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => {
      guard @check.diagnostic_cause(error)
        is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
        raise @check.diagnostic_cause(error)
      }
      fail(@debug.to_string(issue.kind) + ": " + semantic(p))
    }
    _ => fail("closed immutable value column")
  }
}

///|
test "public script preserves the original value-table row after SET" {
  let script = @query.parse_query_script(
    "FROM (FROM UNNEST(@items) element WITH OFFSET position) chosen |> SET element = position + 10 |> SELECT chosen AS row,element AS value,position |> ORDER BY position",
    syntax_limits(),
  ).unwrap()
  let p = match
    compile_query_script(
      script,
      {
        ..values_context(),
        inputs: [],
        parameter_declarations: Some(unnest_parameters()),
      },
      construction_limits(),
    ) {
    Ok(p) => p
    Err(Expression(issue)) => fail(@debug.to_string(issue.issue))
    Err(UnsupportedCte) => fail("UnsupportedCte")
    Err(UnknownColumn) => fail("UnknownColumn")
    Err(_) => fail("script lowering refusal")
  }
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      Some(unnest_value_cursor("{\"items\":[2,null,2]}")),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => {
      guard @check.diagnostic_cause(error)
        is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
        raise @check.diagnostic_cause(error)
      }
      fail(@debug.to_string(issue.kind) + ": " + semantic(p))
    }
    _ => fail("closed script")
  }
}
