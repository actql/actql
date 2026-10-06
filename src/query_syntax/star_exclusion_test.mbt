///|
test "star exclusion syntax owns quoted names and keeps set EXCEPT separate" {
  let query = parse_query(
    "SELECT * EXCEPT (`a.b`, Mixed) FROM rows",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Select(projections, false)) else {
    fail("expected SELECT")
  }
  assert_eq(projections[0].except_columns, [
    { value: "a.b", quoted: true, },
    { value: "Mixed", quoted: false, },
  ])
  projections[0].except_columns.clear()
  guard operation_at(query, 0) is Some(Select(original, _)) else {
    fail("expected retained SELECT")
  }
  assert_eq(original[0].except_columns.length(), 2)
  assert_true(
    parse_query(
      "SELECT * EXCEPT (id) FROM rows EXCEPT DISTINCT SELECT other FROM rows",
      query_limits(),
    )
    is Ok(_),
  )
}

///|
test "star exclusion syntax rejects incomplete column lists" {
  for
    text in [
      "SELECT * EXCEPT () FROM rows", "SELECT * EXCEPT (id,) FROM rows", "SELECT * EXCEPT (t.id) FROM rows",
      "SELECT * EXCEPT id FROM rows", "SELECT * EXCEPT (id FROM rows",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}
