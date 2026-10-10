///|
test "SQL and Pipe use the same checked COMMAND postlude without losing effects" {
  let cases : Array[(Format, String)] = [
    (Sql, "SELECT id FROM records |> RESULT selected"),
    (Text, "FROM records |> SELECT id |> RESULT selected"),
    (Text, "DATA ids = SELECT id FROM records; FROM ids |> RESULT selected"),
  ]
  for (format, query) in cases {
    let text = query +
      "; EFFECT upload COMMAND FROM RESULT selected AS t TARGET t.id CONTRACT c INPUT ();"
    assert_true(parse_query(text, format) is Ok(_))
    let lowered = lower(text, format, Some(test_context())).unwrap()
    assert_true(lowered.document.contains("\"command\""))
    assert_true(lowered.document.contains("\"target\":{\"field\":\"id\"}"))
    assert_true(lowered.document.contains("\"input\":{}"))
  }
  assert_true(
    lower(
      "DATA ids = SELECT id FROM records; FROM ids |> RESULT selected; EFFECT upload COMMAND FROM RESULT selected AS t TARGET t.id CONTRACT c INPUT ();",
      Sql,
      Some(test_context()),
    )
    is Err(WrongQueryForm),
  )
}
