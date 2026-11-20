///|
test "standalone set retains the right original row namespace before final order" {
  let source = "SELECT STRUCT(1 AS f0_, 2 AS n) AS row FROM pair UNION ALL (FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> AS captured |> SELECT captured AS row) ORDER BY row.f0_"
  let query = @query.parse_query(source, syntax_limits()).unwrap()
  match compile(query, pair_context(), construction_limits()) {
    Err(UnknownColumn) => ()
    Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
    Err(issue) =>
      fail(
        "wrong set row namespace refusal: " + infer_defaults_issue_tag(issue),
      )
    Ok(_) => fail("right-hand anonymous DATA member became a set SQL member")
  }
}

///|
test "standalone set namespace follows positional and BY NAME mappings" {
  let left = "SELECT STRUCT(1 AS f0_, 2 AS n) AS protected, STRUCT(3 AS f0_, 4 AS n) AS plain FROM pair"
  let right = "(FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> AS captured |> SELECT STRUCT(3 AS f0_, 4 AS n) AS plain, captured AS protected)"
  for
    (modifier, field) in [
      ("", "plain"),
      (" BY NAME", "protected"),
      (" BY NAME ON (plain, protected)", "protected"),
    ] {
    let source = left +
      " UNION ALL" +
      modifier +
      " " +
      right +
      " ORDER BY " +
      field +
      ".f0_"
    match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(issue) =>
        fail("wrong aligned set refusal: " + infer_defaults_issue_tag(issue))
      Ok(_) => fail("a set mapped the wrong original row namespace: " + source)
    }
  }
}

///|
test "standalone set keeps legal named fields and returned whole row data" {
  let left = "SELECT STRUCT(1 AS f0_, 2 AS n) AS protected, STRUCT(3 AS f0_, 4 AS n) AS plain FROM pair"
  let right = "(FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> AS captured |> SELECT STRUCT(3 AS f0_, 4 AS n) AS plain, captured AS protected)"
  for
    (modifier, field, fields) in [
      ("", "protected", ["protected", "plain"]),
      (" BY NAME", "plain", ["protected", "plain"]),
      (" BY NAME ON (plain, protected)", "plain", ["plain", "protected"]),
    ] {
    let source = left +
      " UNION ALL" +
      modifier +
      " " +
      right +
      " ORDER BY " +
      field +
      ".f0_"
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
        fail("the aligned set operands remain closed original Values")
    }
  }
  let program = compile(
    @query.parse_query(
      "SELECT STRUCT(1 AS f0_, 2 AS n) AS row FROM pair UNION ALL (FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> AS captured |> SELECT captured AS row) ORDER BY row.n",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(anonymous_result_fields(program), ["row"])
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("both original row values remain complete")
  }
}

///|
test "standalone set window checks original members before argument and output reuse" {
  for
    tail in [
      "LAG(row.f0_) OVER (ORDER BY row.n)", "(LAG(row) OVER (ORDER BY row.n)).f0_",
    ] {
    let source = "SELECT STRUCT(1 AS f0_, 2 AS n) AS row FROM pair UNION ALL (FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> AS captured |> SELECT captured AS row) ORDER BY " +
      tail
    match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(issue) =>
        fail(
          "wrong set window member refusal: " + infer_defaults_issue_tag(issue),
        )
      Ok(_) =>
        fail("set window reuse lost the original anonymous member: " + source)
    }
  }
}

///|
test "standalone set window retains legal named arguments and result members" {
  for
    tail in [
      "LAG(row.n) OVER (ORDER BY row.n)", "(LAG(row) OVER (ORDER BY row.n)).n",
    ] {
    let source = "SELECT STRUCT(1 AS f0_, 2 AS n) AS row FROM pair UNION ALL (FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 |> AS captured |> SELECT captured AS row) ORDER BY " +
      tail
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let first = compile(query, pair_context(), construction_limits()).unwrap()
    let second = compile(query, pair_context(), construction_limits()).unwrap()
    assert_eq(anonymous_result_fields(first), ["row"])
    assert_eq(semantic(first), semantic(second))
  }
}
