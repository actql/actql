///|
test "Pipe PIVOT retains aggregate columns values aliases and prefix" {
  let query = parse_query(
    "FROM rows |> PIVOT(MIN(r.amount) AS m FOR r.status IN ('z' AS last, \"a\" first)) AS current",
    query_limits(),
  ).unwrap()
  match operation_at(query, 0) {
    Some(Pivot(clause)) => {
      assert_eq(clause.function_name, "MIN")
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
      "FROM rows |> PIVOT(COUNT(*) FOR status IN ('open'))", "FROM rows |> PIVOT(SUM(MAX(amount)) FOR status IN ('open'))",
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
test "PIVOT scalar argument AST keeps column references separately from the evaluated output" {
  let query = parse_query(
    "FROM rows |> PIVOT(SUM(r.amount + 1) FOR r.status IN ('open'))",
    query_limits(),
  ).unwrap()
  match operation_at(query, 0) {
    Some(Pivot(clause)) => {
      assert_true(clause.argument.is_empty())
      assert_true(clause.argument_expression is Some(_))
      assert_eq(clause.column.map(part => part.value), ["r", "status"])
    }
    _ => fail("expected PIVOT expression")
  }
}

///|
test "PIVOT scalar argument cannot contain another aggregate call" {
  assert_true(
    parse_query(
      "FROM rows |> PIVOT(SUM(AVG(amount) + 1) FOR status IN ('open'))",
      query_limits(),
    )
    is Err({ issue: Syntax("PIVOT argument cannot contain an aggregate"), .. }),
  )
}
