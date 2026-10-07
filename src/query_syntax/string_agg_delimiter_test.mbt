///|
test "STRING_AGG delimiter default preserves the following filter and order" {
  for
    source in [
      "SELECT STRING_AGG(name WHERE id > 0 ORDER BY id) AS names FROM records", "FROM records |> AGGREGATE STRING_AGG(name WHERE id > 0 ORDER BY id) AS names",
    ] {
    let query = parse_query(source, query_limits()).unwrap()
    match operation_at(query, 0) {
      Some(Group(_, projections, _)) => {
        let aggregate = projections[0].aggregate.unwrap()
        assert_eq(aggregate.delimiter, Some(","))
        assert_true(aggregate.filter is Some(_))
        assert_eq(aggregate.order_by.length(), 1)
      }
      _ => fail(source)
    }
  }
}

///|
test "STRING_AGG authored delimiters are not replaced by the default" {
  for (delimiter, expected) in [("''", ""), ("'|'", "|"), ("'\\n'", "\n")] {
    let query = parse_query(
      "SELECT STRING_AGG(name, " +
      delimiter +
      " ORDER BY id) AS names FROM records",
      query_limits(),
    ).unwrap()
    match operation_at(query, 0) {
      Some(Group(_, projections, _)) =>
        assert_eq(projections[0].aggregate.unwrap().delimiter, Some(expected))
      _ => fail("expected aggregate")
    }
  }
}

///|
test "STRING_AGG invalid explicit delimiters retain typed syntax refusal" {
  for
    source in [
      "SELECT STRING_AGG(name, 1 ORDER BY id) AS names FROM records", "SELECT STRING_AGG(name, @p ORDER BY id) AS names FROM records",
      "SELECT STRING_AGG(name, ORDER BY id) AS names FROM records",
    ] {
    match parse_query(source, query_limits()) {
      Err({ issue: Syntax(reason), .. }) =>
        assert_eq(reason, "STRING_AGG delimiter must be literal")
      _ => fail(source)
    }
  }
}
