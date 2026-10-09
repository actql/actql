///|
test "unaliased unknown columns retain the original failed occurrence" {
  for (text, start, end) in [
    ("SELECT missing", 7, 14),
    ("/*😀*/\r\nSELECT missing", 17, 24),
    ("SELECT `é😀`", 7, 15),
    ("SELECT missing FROM records", 7, 14),
    ("SELECT records.missing FROM records", 7, 22),
    ("SELECT id, missing FROM records", 11, 18),
    ("/* missing */ SELECT missing", 21, 28),
  ] {
    for format in [Format::Sql, Format::Text] {
      let issue = match lower(text, format, Some(test_context()), source_path="submitted.sql") {
        Err(issue) => issue
        Ok(_) => fail("unknown reference must be rejected")
      }
      guard unknown_column_origin(issue) is Some(origin) else {
        fail("the unaliased projection discarded its authored origin: " + text)
      }
      assert_eq(@origin.kind(origin), @origin.Authored)
      let span = @origin.span(origin)
      assert_eq(span.source_path, "submitted.sql")
      assert_eq(span.start_byte, start)
      assert_eq(span.end_byte, end)
    }
  }
}
