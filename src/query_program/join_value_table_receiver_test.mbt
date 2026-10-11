///|
test "independent JOIN value-table control preserves a scalar result" {
  let p = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.join_value_receiver","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":7}]},"as":"left"},{"values":{"schema":{"element":{"type":"number","nullable":false}},"rows":[{"element":1},{"element":2}]},"as":"right"},{"from":"left","cross_join":{"with":"right","max_output_rows":10,"select":{"value":"right.element"}},"as":"out"}],"results":{"rows":{"from":"out","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed independent scalar JOIN control")
  }
}

///|
test "JOIN right derived value-table alias is its scalar value" {
  let p = match
    compile_query_script(
      @query.parse_query_script(
        "SELECT r AS value FROM (SELECT 7 AS id) l CROSS JOIN (FROM UNNEST([1,2]) element) r MAX_OUTPUT_ROWS 10 ORDER BY value",
        syntax_limits(),
      ).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(p) => p
    Err(UnsupportedOrdering) => fail("UnsupportedOrdering")
    Err(UnsupportedJoin) => fail("UnsupportedJoin")
    Err(UnsupportedCte) => fail("UnsupportedCte")
    Err(AmbiguousColumn) => fail("AmbiguousColumn")
    Err(UnknownColumn) => fail("UnknownColumn")
    Err(Expression(issue)) => fail(@debug.to_string(issue.issue))
    Err(_) => fail("other lowering rejection")
  }
  assert_false(
    semantic(p).contains("\"object\""),
    msg="right scalar receiver must not become a row of private columns",
  )
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed scalar receiver JOIN")
  }
}

///|
test "JOIN ON resolves a right scalar value-table receiver" {
  let p = match
    compile_query_script(
      @query.parse_query_script(
        "SELECT r AS value FROM (SELECT 1 AS id) l JOIN (FROM UNNEST([1,2]) element) r ON l.id=r MAX_OUTPUT_ROWS 10",
        syntax_limits(),
      ).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(p) => p
    Err(UnsupportedOrdering) => fail("UnsupportedOrdering")
    Err(UnsupportedJoin) => fail("UnsupportedJoin")
    Err(UnsupportedCte) => fail("UnsupportedCte")
    Err(AmbiguousColumn) => fail("AmbiguousColumn")
    Err(UnknownColumn) => fail("UnknownColumn")
    Err(Expression(issue)) => fail(@debug.to_string(issue.issue))
    Err(_) => fail("other lowering rejection")
  }
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed scalar ON receiver JOIN")
  }
}

///|
test "JOIN preserves nullable object scalar and OFFSET output kinds on either side" {
  for
    source in [
      "SELECT l AS left_value,r AS right_value FROM (FROM UNNEST([1,2]) old_l) l JOIN (FROM UNNEST([2,3]) old_r) r ON l=r MAX_OUTPUT_ROWS 10 ORDER BY left_value",
      "SELECT r AS value FROM (SELECT 1 AS id,90 AS r) l JOIN (FROM UNNEST([1,2]) old_r) r ON l.id=r MAX_OUTPUT_ROWS 10",
      "SELECT l.id,r AS value FROM (SELECT 1 AS id UNION ALL SELECT 3) l LEFT JOIN (FROM UNNEST([1,2]) old_r) r ON l.id=r MAX_OUTPUT_ROWS 10 ORDER BY l.id",
      "SELECT r AS row,r.element AS value,r.position FROM (SELECT 7 AS id) l CROSS JOIN (FROM UNNEST([1,2]) element WITH OFFSET position) r MAX_OUTPUT_ROWS 10 ORDER BY position",
    ] {
    let p = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        p,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("closed joined value-table source")
    }
  }
  let p = compile_query_script(
    @query.parse_query_script(
      "SELECT r AS value,r.id AS id FROM (SELECT 7 AS key) l CROSS JOIN (FROM UNNEST(@items) old_r) r MAX_OUTPUT_ROWS 10 ORDER BY id NULLS FIRST,value.label NULLS FIRST",
      syntax_limits(),
    ).unwrap(),
    {
      ..values_context(),
      inputs: [],
      parameter_declarations: Some(unnest_struct_parameters()),
    },
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      p,
      check_environment(),
      Some(
        unnest_value_cursor(
          "{\"items\":[{\"id\":2,\"label\":\"kept\"},null,{\"id\":2,\"label\":null}]}",
        ),
      ),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed joined nullable object")
  }
}

///|
test "JOIN does not restore the old derived value receiver or a scalar star" {
  for
    source in [
      "SELECT old_r FROM (SELECT 7 AS id) l CROSS JOIN (FROM UNNEST([1,2]) old_r) r MAX_OUTPUT_ROWS 10",
      "SELECT r.* FROM (SELECT 7 AS id) l CROSS JOIN (FROM UNNEST([1,2]) old_r) r MAX_OUTPUT_ROWS 10",
    ] {
    let result = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    )
    if source.contains("SELECT old_r") {
      assert_true(
        result is Err(Expression({ issue: @expression.UnknownReference, .. })),
        msg=source,
      )
    } else {
      assert_true(result is Err(UnknownColumn), msg=source)
    }
  }
}
