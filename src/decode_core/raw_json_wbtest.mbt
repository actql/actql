///|
test "raw physical JSON admission preserves text and exact budgets" {
  let span : @span.Span = {
    start_byte: 0,
    end_byte: 32,
    start_line: 1,
    end_line: 1,
    start_column: 1,
    end_column: 33,
    source_path: "<physical>",
  }
  let value = @json.parse("{\"x\":[\"e\\u0301\\r\\n\",null]}")
  let limits : Limits = {
    max_nodes: 4,
    max_depth: 2,
    max_string_bytes: 5,
    max_total_string_bytes: 6,
  }
  let cursor = admit_raw_json(value, span, limits).unwrap()
  assert_eq(admission_usage(cursor), {
    nodes: 4,
    depth: 2,
    largest_string_bytes: 5,
    total_string_bytes: 6,
  })
  let object = open_object(cursor).unwrap()
  let array = required(object, "x").unwrap()
  assert_eq(text(element_at(array, 0).unwrap()), Ok("e\u0301\r\n"))
  assert_true(is_null(element_at(array, 1).unwrap()))
  for
    (changed, expected_path) in [
      ({ ..limits, max_nodes: 3, }, [@source.Key("x")]),
      ({ ..limits, max_depth: 1, }, [@source.Key("x")]),
      (
        { ..limits, max_total_string_bytes: 5, },
        [@source.Key("x"), @source.Index(0)],
      ),
    ] {
    guard admit_raw_json(value, span, changed) is Err(issue) else {
      fail("expected raw JSON budget rejection")
    }
    assert_eq(issue.kind, BudgetExceeded)
    assert_eq(issue.path, expected_path)
    assert_eq(issue.span, span)
  }
}
