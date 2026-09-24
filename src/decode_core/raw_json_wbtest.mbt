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

///|
test "flat physical column admission matches generic raw JSON" {
  let span : @span.Span = {
    start_byte: 0,
    end_byte: 16,
    start_line: 1,
    end_line: 1,
    start_column: 1,
    end_column: 17,
    source_path: "<column>",
  }
  let values = match @json.parse("[\"é\",null,true,\"z\"]") {
    Array(values) => values
    _ => abort("invalid test column")
  }
  let limits : Limits = {
    max_nodes: 5,
    max_depth: 1,
    max_string_bytes: 2,
    max_total_string_bytes: 3,
  }
  let flat = admit_raw_scalar_column(values, span, limits).unwrap()
  let generic = admit_raw_json(Json::array(values), span, limits).unwrap()
  assert_eq(admission_usage(flat), admission_usage(generic))
  assert_eq(text(element_at(flat, 0).unwrap()), Ok("é"))
  assert_true(is_null(element_at(flat, 1).unwrap()))
  assert_eq(boolean(element_at(flat, 2).unwrap()), Ok(true))
  for
    changed in [
      { ..limits, max_nodes: 4, },
      { ..limits, max_depth: 0, },
      { ..limits, max_total_string_bytes: 2, },
    ] {
    let flat = admit_raw_scalar_column(values, span, changed).unwrap_err()
    let generic = admit_raw_json(Json::array(values), span, changed).unwrap_err()
    assert_eq(flat, generic)
  }
  let invalid = [@json.parse("1")]
  assert_eq(
    admit_raw_scalar_column(invalid, span, limits).unwrap_err().kind,
    WrongType,
  )
}
