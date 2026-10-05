///|
test "valid nested calls retain an expression construction budget diagnostic" {
  let context = bind_query_context(
    [],
    "sha256:" + "1".repeat(64),
    program_id="public.expression.budget",
  ).unwrap()
  let source = "/*😀*/\r\nSELECT " +
    "COALESCE(".repeat(40) +
    "1" +
    ", 1)".repeat(40) +
    " AS n"
  let formats : Array[Format] = [Sql, Text]
  for format in formats {
    assert_true(parse_query(source, format) is Ok(_))
    assert_true(
      lower(source, format, Some(context))
      is Err(QueryLowering(Expression({ issue: Construction(DepthLimit), .. }))),
    )
  }
}
