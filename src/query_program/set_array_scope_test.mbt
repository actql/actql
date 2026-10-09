///|
fn independent_set_array_program() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    correlated_unnest_seed() +
    "," +
    (
      #|{"from":"parents","append":{"with":"parents"},"as":"combined"},{"from":"combined","derive":{"children":{"field":"items"}}},{"unnest":{"column":"children","as":"element","with_index":"position"}},{"filter":{"not":{"is_null":{"field":"element"}}}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"position","dir":"asc","nulls":"first"}]},{"select":["id","element","position"]},{"take":{"count":3,"offset":0},"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["id","element","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "correlated UNNEST after Pipe UNION retains the normal owner operations" {
  let expected = independent_set_array_program()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent ARRAY append and expansion must be closed")
  }
  let query = @query.parse_query(
    "FROM parents |> SELECT id, items |> UNION ALL (FROM parents |> SELECT id, items) |> CROSS JOIN UNNEST(items) element WITH OFFSET position |> WHERE element IS NOT NULL |> SELECT id, element, position |> ORDER BY id, position |> LIMIT 3",
    syntax_limits(),
  ).unwrap()
  let actual = match
    compile(query, correlated_unnest_context(), construction_limits()) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("set ARRAY output scope: UnsupportedProjection")
    Err(UnsupportedSet) => fail("set ARRAY output scope: UnsupportedSet")
    Err(UnsupportedJoin) => fail("set ARRAY output scope: UnsupportedJoin")
    Err(_) => fail("set ARRAY output scope: unexpected lowering failure")
  }
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("set ARRAY expansion must retain its checked input")
  }
  let wire = semantic(actual)
  assert_eq(wire.split("\"append\":").length(), 2)
  assert_eq(wire.split("\"unnest\":").length(), 2)
  assert_true(wire.contains("\"is_null\""))
  assert_true(wire.contains("\"count\":3"))
  assert_true(wire.contains("\"fields\":[\"id\",\"element\",\"position\"]"))
}

///|
test "correlated UNNEST star after Pipe UNION uses the admitted ARRAY schema" {
  let query = @query.parse_query(
    "FROM parents |> SELECT id, items |> UNION ALL (FROM parents |> SELECT id, items) |> CROSS JOIN UNNEST(items) element WITH OFFSET position |> SELECT * EXCEPT (items) |> ORDER BY id, position",
    syntax_limits(),
  ).unwrap()
  let actual = match
    compile(query, correlated_unnest_context(), construction_limits()) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail("set ARRAY star: UnsupportedProjection")
    Err(_) => fail("set ARRAY star: unexpected lowering failure")
  }
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("set ARRAY star must have the common checked contract")
  }
  assert_true(
    semantic(actual).contains("\"fields\":[\"id\",\"element\",\"position\"]"),
  )
}

///|
test "CTE ARRAY aliases and retained chains supply the actual star schema" {
  for
    text in [
      "WITH chosen AS (SELECT id, items AS children FROM parents) SELECT * EXCEPT (children) FROM chosen CROSS JOIN UNNEST(children) element WITH OFFSET position ORDER BY id, position",
      "WITH first AS (SELECT id, items FROM parents), chosen AS (SELECT id, items AS children FROM first) FROM chosen |> CROSS JOIN UNNEST(children) element WITH OFFSET position |> SELECT * EXCEPT (children) |> ORDER BY id, position",
      "WITH parents AS (SELECT id, [9] AS items FROM parents) FROM parents |> CROSS JOIN UNNEST(items) element WITH OFFSET position |> SELECT * EXCEPT (items) |> ORDER BY id, position",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      correlated_unnest_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("retained ARRAY schema must remain checked")
    }
    assert_true(
      semantic(actual).contains("\"fields\":[\"id\",\"element\",\"position\"]"),
    )
  }
}

///|
test "CTE closed object star keeps nullable fields and the parameter declaration" {
  let text = "WITH chosen AS (SELECT element AS payload, position FROM UNNEST(@items) element WITH OFFSET position) SELECT payload.*, position FROM chosen ORDER BY position"
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(unnest_struct_parameters()),
    },
    construction_limits(),
  ).unwrap()
  for values in ["[]", "null", "[{\"id\":2,\"label\":null},null]"] {
    match
      @check.check_parsed(
        actual,
        check_environment(),
        Some(unnest_value_cursor("{\"items\":" + values + "}")),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("retained nullable object must remain checked")
    }
  }
  assert_true(
    semantic(actual).contains("\"fields\":[\"id\",\"label\",\"position\"]"),
  )
}

///|
test "retained CTE schema does not restore a dropped column or range" {
  for
    text in [
      "WITH chosen AS (SELECT id FROM parents) FROM chosen |> CROSS JOIN UNNEST(items) element |> SELECT *",
      "WITH chosen AS (SELECT id, items FROM parents) FROM chosen p |> SELECT id, items |> CROSS JOIN UNNEST(p.items) element |> SELECT *",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        correlated_unnest_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
}
