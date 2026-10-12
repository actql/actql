///|
test "explicit Graph refusal retains the authored operand in SQL and Text" {
  for
    (text, start, end) in [
      ("WITH e AS (SELECT 1 AS id) FROM GRAPH e", 38, 39),
      (
        "/*😀*/\r\nWITH e AS (SELECT 1 AS id), unused AS (FROM GRAPH e) SELECT 1 AS answer",
        60, 61,
      ),
    ] {
    for format in [Format::Sql, Format::Text] {
      guard lower(
          text,
          format,
          Some(test_context()),
          source_path="submitted.sql",
        )
        is Err(QueryLowering(GraphExpected(Some(origin)))) else {
        fail("The explicit operand must fail before admission: " + text)
      }
      assert_eq(@origin.kind(origin), @origin.Authored)
      let span = @origin.span(origin)
      assert_eq(span.source_path, "submitted.sql")
      assert_eq(span.start_byte, start)
      assert_eq(span.end_byte, end)
    }
  }
}
