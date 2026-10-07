///|
test "Pipe grouping-key aliases retain authored names without changing expressions" {
  for
    source in [
      "FROM records |> AGGREGATE COUNT(*) AS n GROUP BY id AS bucket, amount", "FROM records |> AGGREGATE COUNT(*) AS n GROUP BY id bucket, amount",
    ] {
    let query = parse_query(source, query_limits()).unwrap()
    guard operation_at(query, 0) is Some(Group(keys, _, PipeAggregate(names))) else {
      fail("grouping names belong to the Pipe output scope")
    }
    assert_eq(names, [Some({ value: "bucket", quoted: false, }), None])
    assert_eq(keys.length(), 2)
    names.clear()
    guard operation_at(query, 0) is Some(Group(_, _, PipeAggregate(retained))) else {
      fail("the query retains its grouping metadata")
    }
    assert_eq(retained.length(), 2)
  }
}

///|
test "Pipe grouping-key aliases preserve quoting and remain distinct from SQL GROUP BY" {
  let query = parse_query(
    "FROM records |> AGGREGATE GROUP BY id AS `GROUP`",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Group(_, _, PipeAggregate(names))) else {
    fail("the explicit quoted key alias is retained")
  }
  assert_eq(names, [Some({ value: "GROUP", quoted: true, })])
  assert_true(
    parse_query("SELECT id FROM records GROUP BY id AS bucket", query_limits())
    is Err({ issue: Syntax(_), .. }),
  )
}
