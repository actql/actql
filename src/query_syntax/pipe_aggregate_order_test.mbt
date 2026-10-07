///|
test "Pipe aggregate shorthand ordering retains output positions and suffixes" {
  let query = parse_query(
    "FROM pair |> AGGREGATE COUNT(*) AS n DESC NULLS FIRST GROUP AND ORDER BY x AS bucket NULLS LAST, y DESC",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 1) is Some(Order(terms)) else {
    fail(
      "shorthand ordering follows the group with the existing Order operation",
    )
  }
  assert_eq(terms.length(), 3)
  for
    (index, direction, nulls) in [
      (0, "asc", "last"),
      (1, "desc", "last"),
      (2, "desc", "first"),
    ] {
    assert_eq(terms[index].direction, direction)
    assert_eq(terms[index].nulls, nulls)
    assert_true(
      expression_node(terms[index].expression, 0).unwrap().kind is Number(value) &&
      value == (index + 1).to_string(),
    )
  }
}

///|
test "Pipe aggregate shorthand ordering sorts only suffixed items without AND ORDER" {
  let query = parse_query(
    "FROM pair |> AGGREGATE COUNT(*) AS n ASC GROUP BY x, y DESC",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 1) is Some(Order(terms)) else {
    fail("expected a suffix-driven sort")
  }
  assert_eq(terms.length(), 2)
  assert_true(
    expression_node(terms[0].expression, 0).unwrap().kind is Number("2"),
  )
  assert_true(
    expression_node(terms[1].expression, 0).unwrap().kind is Number("3"),
  )
  assert_eq(terms[0].direction, "desc")
  assert_eq(terms[1].direction, "asc")
}

///|
test "Pipe aggregate shorthand ordering leaves unsuffixed and empty grouping unordered" {
  for
    source in [
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x", "FROM pair |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY ()",
    ] {
    assert_eq(operation_count(parse_query(source, query_limits()).unwrap()), 1)
  }
  let global = parse_query(
    "FROM pair |> AGGREGATE COUNT(*) AS n DESC",
    query_limits(),
  ).unwrap()
  guard operation_at(global, 1) is Some(Order(terms)) else {
    fail("global aggregate suffix remains an explicit sort")
  }
  assert_true(
    expression_node(terms[0].expression, 0).unwrap().kind is Number("1"),
  )
}

///|
test "Pipe aggregate shorthand ordering keeps placement and malformed suffix refusals" {
  for
    source in [
      "SELECT x FROM pair GROUP AND ORDER BY x", "SELECT x FROM pair GROUP BY x DESC",
      "FROM pair |> AGGREGATE COUNT(*) AS n NULLS FIRST GROUP BY x", "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x ASC NULLS MIDDLE",
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP AND BY x",
    ] {
    assert_true(
      parse_query(source, query_limits()) is Err({ issue: Syntax(_), .. }),
    )
  }
}

///|
test "Pipe aggregate shorthand ordering counts generated output references in expression budget" {
  let limits = query_limits()
  let small = { ..limits, expression: { ..limits.expression, max_nodes: 1, }, }
  assert_true(
    parse_query("FROM pair |> AGGREGATE GROUP AND ORDER BY x", small)
    is Err({ issue: Syntax("Expression node limit"), .. }),
  )
}
