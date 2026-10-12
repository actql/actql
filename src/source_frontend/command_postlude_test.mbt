///|
test "SQL and Pipe use the same checked COMMAND postlude without losing effects" {
  let cases : Array[(Format, String, @query.Context)] = [
    (Sql, "SELECT id FROM records |> RESULT selected", test_context()),
    (Text, "FROM records |> SELECT id |> RESULT selected", test_context()),
    (
      Text,
      "WITH ids AS (SELECT id FROM records) FROM ids |> RESULT selected",
      registered_test_context(),
    ),
    (
      Sql,
      "WITH ids AS (SELECT id FROM records) FROM ids |> RESULT selected",
      registered_test_context(),
    ),
  ]
  for (format, query, context) in cases {
    let text = query +
      "; EFFECT upload COMMAND FROM RESULT selected AS t TARGET t.id CONTRACT c INPUT ();"
    assert_true(parse_query(text, format) is Ok(_))
    let lowered = match lower(text, format, Some(context)) {
      Ok(value) => value
      Err(QueryLowering(UnknownColumn)) =>
        fail("COMMAND UnknownColumn: " + text)
      Err(QueryLowering(Expression({ issue: UnknownReference, .. }))) =>
        fail("COMMAND UnknownReference: " + text)
      Err(QueryLowering(UnresolvedRelation(_))) =>
        fail("COMMAND UnresolvedRelation: " + text)
      Err(QueryLowering(UnsupportedEffect)) =>
        fail("COMMAND UnsupportedEffect: " + text)
      Err(QueryLowering(BindingPreparation(MissingSourceCatalog(_)))) =>
        fail("COMMAND MissingSourceCatalog: " + text)
      Err(_) => fail("COMMAND lowering failed: " + text)
    }
    assert_true(lowered.document.contains("\"command\""))
    assert_true(lowered.document.contains("\"target\":{\"field\":\"id\"}"))
    assert_true(lowered.document.contains("\"input\":{}"))
  }
  // A derived captured Source keeps its original Catalog obligation; a visible
  // column name or an attached schema cannot supply Source registration.
  assert_true(
    lower(
      "WITH ids AS (SELECT id FROM records) FROM ids |> RESULT selected; EFFECT upload COMMAND FROM RESULT selected AS t TARGET t.id CONTRACT c INPUT ();",
      Text,
      Some(test_context()),
    )
    is Err(QueryLowering(BindingPreparation(MissingSourceCatalog(_)))),
  )
  assert_true(
    lower(
      "FROM records |> SELECT id |> RESULT selected; EFFECT upload COMMAND FROM RESULT selected AS t TARGET t.id CONTRACT c INPUT ();",
      Sql,
      Some(test_context()),
    )
    is Err(WrongQueryForm),
  )
}
