///|
test "grouped extrema retain the authored DISTINCT modifier in syntax" {
  for
    text in [
      "SELECT MIN(DISTINCT amount) AS low, MAX(DISTINCT amount) AS high FROM orders",
      "FROM orders |> AGGREGATE `mIn`(DISTINCT amount) AS low, `mAx`(DISTINCT amount) AS high",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    guard operation_at(query, 0) is Some(Group(_, projections, _)) else {
      fail("extrema stay ordinary aggregate calls")
    }
    assert_eq(projections.length(), 2)
    for projection in projections {
      assert_true(projection.aggregate.unwrap().distinct)
    }
  }
}

///|
test "DISTINCT extrema do not admit empty arguments star or extra operands" {
  for
    text in [
      "SELECT MIN(DISTINCT *) FROM orders", "SELECT MAX(DISTINCT *) FROM orders",
      "SELECT MIN(DISTINCT) FROM orders", "SELECT MAX(DISTINCT amount, id) FROM orders",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
}
