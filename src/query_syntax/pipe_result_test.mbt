///|
test "RESULT preserves authored names and operation placement" {
  let query = parse_query(
    "FROM records |> RESULT `Original Rows` |> WHERE id > 0 |> RESULT active;",
    query_limits(),
  ).unwrap()
  assert_eq(operation_count(query), 3)
  assert_true(
    operation_at(query, 0)
    is Some(RetainResult({ value: "Original Rows", quoted: true, })),
  )
  assert_true(operation_at(query, 1) is Some(Where(_)))
  assert_true(
    operation_at(query, 2)
    is Some(RetainResult({ value: "active", quoted: false, })),
  )
}

///|
test "RESULT obeys lexical and syntax resource admission" {
  for source in ["FROM records |> RESULT", "FROM records |> RESULT 'saved'"] {
    assert_true(parse_query(source, query_limits()) is Err(_))
  }
  let text = "FROM records |> RESULT saved |> RESULT final"
  assert_true(
    parse_query(text, { ..query_limits(), max_syntax_nodes: 1, }) is Err(_),
  )
  assert_true(parse_query(text, { ..query_limits(), max_work: 1, }) is Err(_))
  assert_true(
    parse_query(text, {
      ..query_limits(),
      lexical: { ..limits(), max_tokens: 3, },
    })
    is Err(_),
  )
}
