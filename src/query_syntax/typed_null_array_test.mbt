///|
test "typed NULL ARRAY source retains original cast spans and shared int64 annotation" {
  for text in ["CAST(NULL AS ARRAY<INT64>)", "CAST(((NULL)) AS ARRAY<INT64>)"] {
    let parsed = parse_expression(text, expression_limits()).unwrap()
    let root = expression_node(parsed, expression_root(parsed)).unwrap()
    assert_eq(root.start, 0)
    assert_eq(root.end, text.length())
    assert_true(root.kind is Cast(_, CastType::Array(Signed64)))
    assert_true(
      parse_expression(text, {
        ..expression_limits(),
        max_work: expression_work(parsed) - 1,
      })
      is Err(_),
    )
  }
  for text in ["ARRAY<INT64>[]", "ARRAY<INT64>[@value]"] {
    let parsed = parse_expression(text, expression_limits()).unwrap()
    assert_true(
      kind(parsed, expression_root(parsed))
      is ArrayConstructor(_, Some(Signed64)),
    )
  }
}

///|
test "typed NULL ARRAY syntax does not add recursive or unknown annotations" {
  for
    text in [
      "CAST(NULL AS ARRAY)", "CAST(NULL AS ARRAY<ARRAY<INT64>>)", "CAST(NULL AS ARRAY<UNKNOWN>)",
      "ARRAY<ARRAY<INT64>>[]",
    ] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
}
