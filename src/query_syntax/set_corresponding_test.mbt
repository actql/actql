///|
test "CORRESPONDING defaults to INNER while STRICT retains exact names" {
  for
    text in [
      "SELECT id FROM orders UNION ALL CORRESPONDING SELECT id FROM orders", "SELECT id FROM orders INNER UNION ALL CORRESPONDING SELECT id FROM orders",
      "SELECT id FROM orders UNION ALL CORRESPONDING BY (`ID`) SELECT id FROM orders",
      "FROM orders |> UNION ALL CORRESPONDING (FROM orders)", "FROM orders |> INNER UNION ALL CORRESPONDING BY (id) (FROM orders)",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    let part = set_part_at(query, 0).unwrap()
    assert_true(part.by_name)
    assert_true(part.inner_by_name)
    assert_eq(part.sql_chain, !text.has_prefix("FROM"))
  }
  for
    text in [
      "SELECT id FROM orders UNION ALL STRICT CORRESPONDING SELECT id FROM orders",
      "SELECT id FROM orders UNION ALL STRICT CORRESPONDING BY (id) SELECT id FROM orders",
      "FROM orders |> UNION ALL STRICT CORRESPONDING BY (id) (FROM orders)",
    ] {
    let part = set_part_at(parse_query(text, query_limits()).unwrap(), 0).unwrap()
    assert_true(part.by_name)
    assert_false(part.inner_by_name)
  }
}

///|
test "CORRESPONDING rejects conflicting and malformed modifiers" {
  for
    text in [
      "SELECT id FROM orders INNER UNION ALL STRICT CORRESPONDING SELECT id FROM orders",
      "SELECT id FROM orders UNION ALL STRICT BY NAME SELECT id FROM orders", "SELECT id FROM orders UNION ALL CORRESPONDING ON (id) SELECT id FROM orders",
      "SELECT id FROM orders UNION ALL CORRESPONDING BY () SELECT id FROM orders",
      "FROM orders |> UNION ALL CORRESPONDING BY () (FROM orders)", "SELECT id FROM orders UNION ALL CORRESPONDING SELECT id FROM orders UNION ALL STRICT CORRESPONDING SELECT id FROM orders",
      "SELECT id FROM orders FULL UNION ALL CORRESPONDING SELECT id FROM orders",
      "SELECT id FROM orders LEFT UNION ALL CORRESPONDING SELECT id FROM orders",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}
