///|
test "parsed frontend continuation retains the admitted Program and explicit public Result laws" {
  let cases : Array[(String, Format, String)] = [
    ("SELECT 1 AS id", Sql, "main"),
    ("SELECT 1 AS id |> RESULT saved", Text, "saved"),
  ]
  for (text, format, expected) in cases {
    let parsed = parse_query(text, format, source_path="original-query.aql").unwrap()
    let (lowered, source) = lower_parsed_with_source(
      parsed,
      Some(test_context()),
      public_primary=true,
    ).unwrap()
    let program = lowered.program.unwrap()
    assert_eq(@program.exports(program).map(value => value.0), [expected])
    assert_eq(@program.export_count(program), 1)
    assert_true(
      physical_equal(@program.program_body(program), @builder.cursor(source)),
    )
  }
}

///|
test "parsed frontend continuation preserves original authored error spans without another text input" {
  let parsed = parse_query(
    "SELECT missing AS x FROM records",
    Sql,
    source_path="original.sql",
  ).unwrap()
  guard lower_parsed_with_source(parsed, Some(test_context())) is Err(issue) else {
    fail("the original unresolved field must remain invalid")
  }
  let origin = unknown_column_origin(issue).unwrap()
  let span = @origin.span(origin)
  assert_eq(span.source_path, "original.sql")
  assert_eq(span.start_line, 1)
  assert_eq(span.start_column, 8)
  assert_eq(span.end_column, 15)
}
