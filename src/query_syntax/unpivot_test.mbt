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
    assert_eq(clause.value_columns[0].value, "amount")
    assert_eq(clause.name_column.value, "month name")
    assert_eq(clause.column_sets.map(columns => columns[0].value), [
      "Jan", "feb",
    ])
    assert_true(clause.column_sets[0][0].quoted)
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
      "FROM rows |> UNPIVOT(v FOR k IN (rows.x))", "FROM rows |> UNPIVOT(v FOR k IN (x AS alias))",
      "FROM rows |> UNPIVOT NULLS (v FOR k IN (x))",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
}

///|
test "UNPIVOT row labels preserve decoded literals and omitted labels" {
  for
    source in [
      "FROM rows |> UNPIVOT(v FOR k IN(x AS 'first',x \"second\",y))", "SELECT * FROM rows UNPIVOT(v FOR k IN(x AS 'first',x \"second\",y))",
    ] {
    let query = parse_query(source, query_limits()).unwrap()
    let body = if cte_count(query) == 1 {
      cte_at(query, 0).unwrap().query
    } else {
      query
    }
    guard operation_at(body, 0) is Some(Unpivot(clause)) else {
      fail("UNPIVOT must retain occurrence labels")
    }
    assert_eq(clause.row_labels, [
      Some(TextLabel("first")),
      Some(TextLabel("second")),
      None,
    ])
  }
}

///|
test "UNPIVOT row labels reject expressions mixed types and missing integer labels" {
  for
    source in [
      "FROM rows |> UNPIVOT(v FOR k IN(x AS 'first' || 'last'))", "FROM rows |> UNPIVOT(v FOR k IN(x AS 1.5))",
      "FROM rows |> UNPIVOT(v FOR k IN(x AS 1,y AS 'second'))", "FROM rows |> UNPIVOT(v FOR k IN(x AS 1,y))",
    ] {
    assert_true(
      parse_query(source, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=source,
    )
  }
}
