///|
test "FROM UNPIVOT binds its authored table before the outer query" {
  for modifier in ["", "INCLUDE NULLS ", "EXCLUDE NULLS "] {
    let query = parse_query(
      "SELECT shaped.value,shaped.label FROM rows original UNPIVOT " +
      modifier +
      "(value FOR label IN(x,`Y`)) AS shaped",
      query_limits(),
    ).unwrap()
    assert_eq(query_binding_count(query), 1)
    let body = query_binding_at(query, 0).unwrap().query
    assert_eq(relation_alias(body).unwrap().value, "original")
    guard operation_at(body, 0) is Some(Unpivot(clause)) else {
      fail("table postfix must use the existing UNPIVOT operation")
    }
    assert_eq(clause.include_nulls, modifier == "INCLUDE NULLS ")
    assert_eq(clause.column_sets.map(columns => columns[0].value), ["x", "Y"])
    assert_true(clause.column_sets[1][0].quoted)
    assert_eq(relation_alias(query).unwrap().value, "shaped")
  }
}

///|
test "FROM UNPIVOT rejects expressions qualified inputs and uncovered forms" {
  for
    source in [
      "SELECT * FROM rows UNPIVOT(value FOR label IN(rows.x))", "SELECT * FROM rows UNPIVOT(value FOR label IN(x+1))",
      "SELECT * FROM rows UNPIVOT(value FOR label IN(x AS id))",
    ] {
    assert_true(
      parse_query(source, query_limits()) is Err({ issue: Syntax(_), .. }),
    )
  }
}
