///|
test "JOIN DISTINCT ORDER uses expressions over evaluated output aliases" {
  for
    source in [
      "SELECT DISTINCT -t.x AS x FROM t JOIN r ON t.x = r.k ORDER BY -x", "FROM t |> JOIN r ON t.x = r.k |> SELECT DISTINCT -t.x AS x |> ORDER BY -x",
      "SELECT DISTINCT -t.x AS x FROM t LEFT JOIN r ON t.x = r.k ORDER BY -x", "SELECT DISTINCT -t.x AS x FROM t CROSS JOIN r ORDER BY -x",
      "WITH chosen AS (SELECT x, y FROM t), keys AS (SELECT k FROM r) SELECT DISTINCT -chosen.x AS x FROM chosen JOIN keys ON chosen.x = keys.k ORDER BY -x",
    ] {
    let result = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(), construction_limits(),
    )
    assert_true(result is Ok(_), msg=source)
    let program = result.unwrap()
    match @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail(source)
    }
    let body = semantic(program)
    assert_true(body.contains("\"distinct\":[\"x\"]"))
    assert_true(body.contains("\"fields\":[\"x\"]"))
  }
}

///|
test "JOIN DISTINCT ORDER cannot revive removed input columns" {
  for
    source in [
      "SELECT DISTINCT -t.x AS x FROM t JOIN r ON t.x = r.k ORDER BY t.x", "SELECT DISTINCT -t.x AS x FROM t JOIN r ON t.x = r.k ORDER BY t.y + 1",
      "SELECT DISTINCT -t.x AS x FROM t JOIN r ON t.x = r.k ORDER BY r.k + 1", "FROM t |> JOIN r ON t.x = r.k |> SELECT DISTINCT -t.x AS x |> ORDER BY t.x + 1",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedOrdering),
      msg=source,
    )
  }
}
