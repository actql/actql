///|
test "Pipe UNPIVOT preserves the NULL modifier columns and fresh range" {
  for
    (modifier, include_nulls) in [
      ("", false),
      ("EXCLUDE NULLS ", false),
      ("INCLUDE NULLS ", true),
    ] {
    let query = parse_query(
      "FROM rows |> UNPIVOT " +
      modifier +
      "(amount FOR `month name` IN (`Jan`, feb)) AS reshaped",
      query_limits(),
    ).unwrap()
    guard operation_at(query, 0) is Some(Unpivot(clause)) else {
      fail("UNPIVOT must remain an authored operation")
    }
    assert_eq(clause.include_nulls, include_nulls)
    assert_eq(clause.value_column.value, "amount")
    assert_eq(clause.name_column.value, "month name")
    assert_eq(clause.columns.map(column => column.value), ["Jan", "feb"])
    assert_true(clause.columns[0].quoted)
    assert_true(
      operation_at(query, 1) is Some(Alias({ value: "reshaped", .. })),
    )
  }
}

///|
test "UNPIVOT is a composable pure Pipe operation in declarations and SELECT tails" {
  for
    text in [
      "SELECT x, y FROM rows |> UNPIVOT(v FOR k IN (x,y))", "WITH reshaped AS (FROM rows |> UNPIVOT(v FOR k IN (x,y))) SELECT v,k FROM reshaped",
      "FROM rows |> UNPIVOT(v FOR k IN (x,y)) |> WHERE v > 0 |> SELECT v,k",
    ] {
    assert_true(parse_query(text, query_limits()) is Ok(_), msg=text)
  }
}

///|
test "UNPIVOT does not reinterpret expressions qualified columns or unsupported clauses" {
  for
    text in [
      "FROM rows |> UNPIVOT(v FOR k IN ())", "FROM rows |> UNPIVOT(v FOR k IN (x + 1))",
      "FROM rows |> UNPIVOT(v FOR k IN (rows.x))", "FROM rows |> UNPIVOT(v FOR k IN (x AS 'first'))",
      "FROM rows |> UNPIVOT((v,w) FOR k IN ((x,y)))", "FROM rows |> UNPIVOT NULLS (v FOR k IN (x))",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
}
