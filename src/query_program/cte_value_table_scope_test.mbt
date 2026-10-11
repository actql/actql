///|
test "CTE retains scalar value-table kind across an outer alias and JOIN" {
  for
    source in [
      "WITH a AS (FROM UNNEST([1,2]) old_l) SELECT l AS value FROM a AS l ORDER BY value",
      "WITH a AS (FROM UNNEST([1,2]) old_l), b AS (FROM UNNEST([2,3]) old_r) SELECT l AS value FROM a AS l JOIN b AS r ON l=r MAX_OUTPUT_ROWS 10 ORDER BY value",
      "WITH a AS (FROM UNNEST([1,2]) old_l), b AS (FROM UNNEST([2,3]) old_r) FROM a AS `L` |> JOIN b AS r ON ((`L`))=(r) MAX_OUTPUT_ROWS 10 |> SELECT `L` AS value |> ORDER BY value",
    ] {
    let program = match row_on_query(source) {
      Ok(program) => program
      Err(UnsupportedJoin) => fail("UnsupportedJoin: " + source)
      Err(UnsupportedOrdering) => fail("UnsupportedOrdering: " + source)
      Err(Expression(issue)) => fail(@debug.to_string(issue.issue))
      Err(_) => fail("other lowering rejection: " + source)
    }
    assert_false(semantic(program).contains("\"object\":"), msg=source)
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("closed scalar CTE must require no source")
    }
  }
}

///|
test "CTE value-table binding does not expose its former receiver" {
  let result = row_on_query(
    "WITH a AS (FROM UNNEST([1,2]) old_l) SELECT old_l FROM a AS l",
  )
  assert_true(
    result is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "CTE preserves a nullable object value rather than constructing a new row" {
  let program = compile_query_script(
    @query.parse_query_script(
      "WITH a AS (FROM UNNEST(@items) old_l) SELECT l AS value,l.id AS id FROM a AS l ORDER BY id NULLS FIRST,value.label NULLS FIRST",
      syntax_limits(),
    ).unwrap(),
    {
      ..values_context(),
      inputs: [],
      parameter_declarations: Some(unnest_struct_parameters()),
    },
    construction_limits(),
  ).unwrap()
  assert_false(semantic(program).contains("\"object\":"))
  match
    @check.check_parsed(
      program,
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
    _ => fail("closed nullable object CTE")
  }
}

///|
test "CTE OFFSET and explicit SELECT produce ordinary rows" {
  for
    source in [
      "WITH a AS (FROM UNNEST([2,1]) element WITH OFFSET position) SELECT l AS row,l.element AS value,l.position FROM a AS l ORDER BY position",
      "WITH a AS (FROM UNNEST([2,1]) element |> SELECT element AS id) SELECT l AS row,l.id AS value FROM a AS l ORDER BY value",
    ] {
    let program = row_on_query(source).unwrap()
    assert_true(semantic(program).contains("\"object\":"), msg=source)
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("closed ordinary CTE")
    }
  }
}

///|
test "capturing a CTE kind does not export internal value slots" {
  for
    (source, field) in [
      ("FROM UNNEST([2,1]) element", "element"),
      ("WITH a AS (FROM UNNEST([2,1]) old_l) FROM a AS l |> ORDER BY l", "l"),
    ] {
    let program = row_on_query(source).unwrap()
    assert_true(
      semantic(program).contains("\"fields\":[\"" + field + "\"]"),
      msg=source,
    )
  }
}
