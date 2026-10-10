///|
test "terminal positional aggregate expressions do not require output aliases" {
  // The named controls distinguish anonymous-output handling from COUNT
  // support. Each source-free operand starts with one row; COUNT is one.
  for
    (named, anonymous) in [
      (
        "SELECT 0 AS n UNION ALL SELECT COUNT(*) AS n", "SELECT 0 AS n UNION ALL SELECT COUNT(*)",
      ),
      (
        "SELECT 0 AS n UNION ALL SELECT COUNT(*) + 1 AS n", "SELECT 0 AS n UNION ALL SELECT COUNT(*) + 1",
      ),
    ] {
    for source in [named, anonymous] {
      let generated = match
        compile(
          match @query.parse_query(source, syntax_limits()) {
            Ok(query) => query
            Err(_) => fail(source + ": syntax rejection")
          },
          { ..values_context(), inputs: [], },
          construction_limits(),
        ) {
        Ok(program) => program
        Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
        Err(UnsupportedAggregate) => fail(source + ": UnsupportedAggregate")
        Err(UnsupportedGrouping) => fail(source + ": UnsupportedGrouping")
        Err(_) => fail(source + ": another lowering rejection")
      }
      match
        @check.check_parsed(
          generated,
          check_environment(numeric=true),
          None,
          check_limits(),
        ) {
        Checked(_) => ()
        Rejected(issue) => raise @check.diagnostic_cause(issue)
        _ => fail("source-free set operands have no acquisition dependency")
      }
      assert_true(
        semantic(generated).contains("\"fields\":[\"n\"]"),
        msg=source,
      )
    }
  }
}

///|
test "anonymous aggregate physical outputs never become public or BY NAME aliases" {
  for
    source in [
      "SELECT COUNT(*)", "SELECT 0 AS n UNION ALL BY NAME SELECT COUNT(*)",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        { ..values_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedProjection),
      msg=source,
    )
  }
}

///|
test "positional anonymous aggregate slots retain COUNT argument identity and empty global rows" {
  for
    source in [
      "(SELECT COUNT(*) AS sales, 'Q1' AS quarter UNION ALL SELECT COUNT(*), 'Q2' WHERE FALSE) |> PIVOT(MAX(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))",
      "(SELECT COUNT(*) AS sales, COUNT(CAST(NULL AS FLOAT64)) AS other, 'Q1' AS quarter UNION ALL SELECT COUNT(*), COUNT(CAST(NULL AS FLOAT64)), 'Q2') |> PIVOT(MAX(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))",
    ] {
    let generated = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        generated,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("source-free aggregate operands are closed")
    }
  }
}

///|
test "anonymous aggregate physical slots cannot be addressed by authored HAVING" {
  let source = "SELECT 0 AS n UNION ALL SELECT COUNT(*) HAVING aql_set_aggregate_1 > 0"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
    msg=source,
  )
}
