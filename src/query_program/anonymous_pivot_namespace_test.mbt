///|
test "PIVOT rejects the actual private anonymous grouping argument" {
  let source = "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> EXTEND 'A' AS axis |> PIVOT(COUNT(aql_group_output_4) FOR axis IN ('A' AS hit))"
  match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ) {
    Err(UnknownColumn) => ()
    Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
    Err(issue) =>
      fail(
        "wrong PIVOT anonymous argument refusal: " +
        infer_defaults_issue_tag(issue),
      )
    Ok(_) =>
      fail("PIVOT consumed the private anonymous grouping slot by spelling")
  }
}

///|
test "PIVOT authored axis resolves through the original optional SQL names" {
  let source = "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> PIVOT(COUNT(n) FOR aql_group_output_4 IN ('A' AS hit))"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

///|
test "PIVOT retains anonymous implicit index values and genuine named operands" {
  for
    (source, fields) in [
      (
        "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> EXTEND 'A' AS axis |> PIVOT(COUNT(n) FOR axis IN ('A' AS hit))",
        ["f0_", "hit"],
      ),
      (
        "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> EXTEND 'A' AS axis |> PIVOT(COUNT(n) FOR axis IN ('A' AS hit)) |> SELECT *",
        ["f0_", "hit"],
      ),
      (
        "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 AS f0_ |> EXTEND 'A' AS axis |> PIVOT(COUNT(f0_) FOR axis IN ('A' AS hit))",
        ["n", "hit"],
      ),
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(anonymous_result_fields(program), fields, msg=source)
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("named PIVOT and anonymous index controls remain closed")
    }
  }
  for
    tail in [
      "SELECT aql_group_output_4", "AS result |> SELECT result.f0_", "AS result |> SELECT (result).f0_",
    ] {
    let source = "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> EXTEND 'A' AS axis |> PIVOT(COUNT(n) FOR axis IN ('A' AS hit)) |> " +
      tail
    match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(_) => fail("wrong retained PIVOT index refusal: " + source)
      Ok(_) => fail("PIVOT index metadata became a SQL alias: " + source)
    }
  }
}
