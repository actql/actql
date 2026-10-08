///|
test "COUNTIF retains DISTINCT and the ordinary predicate in query syntax" {
  for
    text in [
      "SELECT COUNTIF(DISTINCT amount > 0) AS n FROM orders", "FROM orders |> AGGREGATE `cOuNtIf`(DISTINCT amount > 0) AS n",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    guard operation_at(query, 0) is Some(Group(_, projections, _)) else {
      fail("aggregate operation required")
    }
    let call = projections[0].aggregate.unwrap()
    assert_eq(call.function_name, "COUNTIF")
    assert_true(call.distinct)
    assert_true(call.argument is Some(_))
  }
}

///|
test "COUNTIF DISTINCT still requires exactly one authored argument" {
  for
    text in [
      "SELECT COUNTIF(DISTINCT *) FROM orders", "SELECT COUNTIF(DISTINCT) FROM orders",
      "SELECT COUNTIF(DISTINCT amount > 0, id) FROM orders",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
}
