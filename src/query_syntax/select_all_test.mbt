///|
test "explicit SELECT ALL uses ordinary duplicate-preserving projection" {
  for
    text in [
      "SELECT ALL amount, id FROM orders", "FROM orders |> SELECT ALL amount, id",
      "SELECT ALL * FROM orders", "FROM orders |> SELECT ALL *", "SELECT ALL 1 AS id",
      "SELECT ALL 1 AS id |> SELECT ALL id",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_true(operation_at(query, 0) is Some(Select(_, false)), msg=text)
  }
  for
    text in [
      "SELECT DISTINCT id FROM orders", "FROM orders |> SELECT DISTINCT id",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_true(operation_at(query, 0) is Some(Select(_, true)), msg=text)
  }
}

///|
test "SELECT quantifiers cannot be combined or repeated" {
  for
    text in [
      "SELECT ALL DISTINCT id FROM orders", "SELECT DISTINCT ALL id FROM orders",
      "SELECT ALL ALL id FROM orders", "FROM orders |> SELECT ALL DISTINCT id", "FROM orders |> SELECT DISTINCT ALL id",
      "FROM orders |> SELECT ALL ALL id",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
}
