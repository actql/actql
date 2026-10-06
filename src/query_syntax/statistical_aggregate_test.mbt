///|
test "statistical calls are recognized as grouped and framed aggregates" {
  for
    name in [
      "VAR_POP", "VAR_SAMP", "VARIANCE", "STDDEV_POP", "STDDEV_SAMP", "STDDEV",
    ] {
    let sql = parse_query(
      "SELECT " + name + "(amount) AS v FROM orders",
      query_limits(),
    ).unwrap()
    guard operation_at(sql, 0) is Some(Group(_, projections, SqlSelect)) else {
      fail("statistical SELECT must create the ordinary Group operation")
    }
    assert_eq(projections[0].aggregate.unwrap().function_name, name)
    let pipe = parse_query(
      "FROM orders |> AGGREGATE " + name + "(amount) AS v",
      query_limits(),
    ).unwrap()
    assert_true(operation_at(pipe, 0) is Some(Group(_, _, PipeAggregate)))
    let window = parse_query(
      "SELECT " +
      name +
      "(amount) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS v FROM orders",
      query_limits(),
    ).unwrap()
    assert_true(operation_at(window, 0) is Some(Analytic(_)))
  }
}

///|
test "statistical arity and aggregate star are syntax errors" {
  for
    text in [
      "SELECT VAR_POP(*) AS v FROM orders", "SELECT VAR_POP() AS v FROM orders",
      "SELECT VAR_POP(amount, id) AS v FROM orders", "FROM orders |> AGGREGATE STDDEV(*) AS v",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
}
