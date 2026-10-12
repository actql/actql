///|
test "SQL and Pipe use the same checked COMMAND postlude without losing effects" {
  let cases : Array[(Format, String)] = [
    (Sql, "SELECT id FROM records |> RESULT selected"),
    (Text, "FROM records |> SELECT id |> RESULT selected"),
    (Text, "WITH ids AS (SELECT id FROM records) FROM ids |> RESULT selected"),
  ]
  for (format, query) in cases {
    let text = query +
      "; EFFECT upload COMMAND FROM RESULT selected AS t TARGET t.id CONTRACT c INPUT ();"
    assert_true(parse_query(text, format) is Ok(_))
    let lowered = match lower(text, format, Some(test_context())) {
      Ok(value) => value
      Err(QueryLowering(UnknownColumn)) =>
        fail("COMMAND UnknownColumn: " + text)
      Err(QueryLowering(Expression({ issue: UnknownReference, .. }))) =>
        fail("COMMAND UnknownReference: " + text)
      Err(QueryLowering(UnresolvedRelation(_))) =>
        fail("COMMAND UnresolvedRelation: " + text)
      Err(QueryLowering(UnsupportedEffect)) =>
        fail("COMMAND UnsupportedEffect: " + text)
      Err(_) => fail("COMMAND lowering failed: " + text)
    }
    assert_true(lowered.document.contains("\"command\""))
    assert_true(lowered.document.contains("\"target\":{\"field\":\"id\"}"))
    assert_true(lowered.document.contains("\"input\":{}"))
  }
  assert_true(
    lower(
      "WITH ids AS (SELECT id FROM records) FROM ids |> RESULT selected; EFFECT upload COMMAND FROM RESULT selected AS t TARGET t.id CONTRACT c INPUT ();",
      Sql,
      Some(test_context()),
    )
    is Err(WrongQueryForm),
  )
}
