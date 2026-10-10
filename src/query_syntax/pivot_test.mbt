///|
test "Pipe PIVOT retains aggregate columns values aliases and prefix" {
  let query = parse_query(
    "FROM rows |> PIVOT(MIN(r.amount) AS m FOR r.status IN ('z' AS last, \"a\" first)) AS current",
    query_limits(),
  ).unwrap()
  match operation_at(query, 0) {
    Some(Pivot(clause)) => {
      assert_eq(clause.function_name, "MIN")
      assert_false(clause.count_star)
      assert_eq(clause.argument.map(part => part.value), ["r", "amount"])
      assert_eq(clause.column.map(part => part.value), ["r", "status"])
      assert_eq(clause.prefix.unwrap().value, "m")
      assert_eq(clause.values.map(pair => (pair.0, pair.1.unwrap().value)), [
        ("z", "last"),
        ("a", "first"),
      ])
    }
    _ => fail("expected a retained pivot")
  }
  assert_true(operation_at(query, 1) is Some(Alias(_)))
}

///|
test "Pipe PIVOT rejects unsupported shapes without changing their meaning" {
  for
    source in [
      "FROM rows |> PIVOT(SUM(*) FOR status IN ('open'))", "FROM rows |> PIVOT(SUM(amount + 1) FOR status IN ('open'))",
      "FROM rows |> PIVOT(COUNT(DISTINCT amount) FOR status IN ('open'))", "FROM rows |> PIVOT(COUNT(amount), MIN(amount) FOR status IN ('open'))",
      "FROM rows |> PIVOT(COUNT(amount) FOR status IN ())", "FROM rows |> PIVOT(COUNT(amount) FOR status IN (@p))",
      "FROM rows |> PIVOT(COUNT(amount) FOR status IN (NULL))", "FROM rows |> PIVOT(COUNT(amount) FOR status IN (1))",
    ] {
    assert_true(
      parse_query(source, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=source,
    )
  }
}

///|
test "PIVOT COUNT star keeps its distinct argument role and the axis path" {
  let query = parse_query(
    "FROM rows |> PIVOT(COUNT(*) AS n FOR r.status IN ('open' AS first))",
    query_limits(),
  ).unwrap()
  match operation_at(query, 0) {
    Some(Pivot(clause)) => {
      assert_eq(clause.function_name, "COUNT")
      assert_true(clause.count_star)
      assert_true(clause.argument.is_empty())
      assert_eq(clause.column.map(part => part.value), ["r", "status"])
      assert_eq(clause.prefix.unwrap().value, "n")
    }
    _ => fail("COUNT star must remain a PIVOT")
  }
}
