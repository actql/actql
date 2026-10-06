///|
test "public SQL and Text routes preserve explicit ALL" {
  for format in [Format::Sql, Format::Text] {
    let result = lower(
      "SELECT ALL id FROM records",
      format,
      Some(test_context()),
    ).unwrap()
    assert_true(result.program is Some(_))
    assert_false(result.document.contains("\"distinct\""))
    assert_true(result.document.contains("\"select\":[\"id\"]"))
    assert_true(
      lower("SELECT ALL DISTINCT id FROM records", format, Some(test_context()))
      is Err(QuerySyntax({ issue: Syntax(_), .. })),
    )
  }
  assert_true(
    lower("FROM records |> SELECT ALL id", Text, Some(test_context())) is Ok(_),
  )
}
