///|
test "QUALIFY recognizes decoded quoted names in the existing window table" {
  for
    call in [
      "`ROW_NUMBER`()", "`rAnK`()", "`DENSE_RANK`()", "`LAG`(x, 1)", "`LEAD`(x, 1)",
      "`FIRST_VALUE`(x)", "`LAST_VALUE`(x)", "`\\x52OW_NUMBER`()",
    ] {
    let query = parse_query(
      "SELECT x FROM t QUALIFY " +
      call +
      " OVER (ORDER BY y) IS NOT NULL ORDER BY x",
      query_limits(),
    ).unwrap()
    match operation_at(query, 0) {
      Some(Analytic(projections)) => {
        let windows = projections.filter(projection => {
          projection.analytic is Some(_)
        })
        assert_eq(windows.length(), 1)
        let expression = windows[0].analytic.unwrap().expression.unwrap()
        assert_true(
          expression_node(expression, expression_root(expression)).unwrap().kind
          is Call([{ quoted: true, .. }], _),
        )
      }
      _ => fail("decoded name must use the existing hidden analytic projection")
    }
  }
}

///|
test "QUALIFY quoted names still require a call and the existing OVER boundary" {
  for name in ["ROW_NUMBER", "`ROW_NUMBER`"] {
    assert_true(
      parse_query("SELECT x FROM t QUALIFY " + name + " = 1", query_limits())
      is Err({ issue: Syntax("QUALIFY requires a window function"), .. }),
    )
    assert_true(
      parse_query("SELECT x FROM t QUALIFY " + name + "() = 1", query_limits())
      is Err({ issue: Syntax("QUALIFY window call requires OVER"), .. }),
    )
  }
  assert_true(
    parse_query(
      "SELECT x FROM t QUALIFY `unknown_window`() OVER (ORDER BY y) = 1",
      query_limits(),
    )
    is Err({ issue: Syntax("QUALIFY requires a window function"), .. }),
  )
  let columns = parse_query(
    "SELECT x AS `ROW_NUMBER`, ROW_NUMBER() OVER (ORDER BY y) AS n FROM t QUALIFY `ROW_NUMBER` = 2",
    query_limits(),
  ).unwrap()
  match operation_at(columns, 0) {
    Some(Analytic(projections)) =>
      assert_eq(
        projections
        .filter(projection => projection.analytic is Some(_))
        .length(),
        1,
      )
    _ => fail("a quoted column must not add a hidden function call")
  }
}
