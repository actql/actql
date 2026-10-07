///|
test "Pipe grouping-only AGGREGATE retains keys without invented calls" {
  for
    text in [
      "FROM records |> AGGREGATE GROUP BY id", "FROM records AS original |> AGGREGATE GROUP BY original.id, amount |> ORDER BY id",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    guard operation_at(query, 0) is Some(Group(keys, calls, PipeAggregate)) else {
      fail("grouping-only AGGREGATE uses the ordinary Pipe group scope")
    }
    assert_true(!keys.is_empty())
    assert_eq(calls.length(), 0)
  }
}

///|
test "Pipe grouping-only AGGREGATE still requires a grouping clause" {
  for
    text in [
      "FROM records |> AGGREGATE", "FROM records |> AGGREGATE |> SELECT id",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
    )
  }
}

///|
test "Pipe grouping-only AGGREGATE permits an explicit empty key list" {
  let query = parse_query(
    "FROM records |> AGGREGATE GROUP BY ()",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Group(keys, calls, PipeAggregate)) else {
    fail("an empty key list is a global group, not an absent GROUP BY clause")
  }
  assert_eq(keys.length(), 0)
  assert_eq(calls.length(), 0)
}
