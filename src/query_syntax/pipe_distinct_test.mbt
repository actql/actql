///|
test "Pipe DISTINCT is a separate operation rather than SELECT star" {
  for
    source in [
      "FROM rows |> DISTINCT", "SELECT id FROM rows |> DISTINCT", "WITH c AS (FROM rows |> DISTINCT) FROM c |> DISTINCT",
    ] {
    let query = parse_query(source, query_limits()).unwrap()
    let mut found = false
    for index in 0..<operation_count(query) {
      if operation_at(query, index) is Some(Distinct) {
        found = true
      }
    }
    assert_true(found)
  }
}

///|
test "Pipe DISTINCT rejects arguments and modifiers" {
  for
    source in [
      "FROM rows |> DISTINCT id", "FROM rows |> DISTINCT(id)", "FROM rows |> DISTINCT ALL",
      "FROM rows |> DISTINCT BY id",
    ] {
    assert_true(parse_query(source, query_limits()) is Err(_), msg=source)
  }
}
