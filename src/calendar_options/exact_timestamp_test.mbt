///|
test "Calendar exact Timestamp range preserves logical precision and chronological order" {
  let millisecond = "2000-01-01T00:00:00.000Z"
  let finer = "2000-01-01T00:00:00.000000001Z"
  assert_eq(@calendar_options.validate_range(millisecond, finer), Ok(()))
  assert_eq(
    @calendar_options.validate_range(finer, millisecond),
    Err(@calendar_options.ReversedRange),
  )
  assert_eq(@calendar_options.validate_range(finer, finer), Ok(()))
}

///|
fn exact_calendar_source(start : String, end : String) -> @decode.Cursor {
  let text = "{\"start\":\"" +
    start +
    "\",\"end\":\"" +
    end +
    "\",\"unit\":\"day\",\"timezone\":\"UTC\"}"
  let parsed = @source.parse_json(text, {
    max_input_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  @decode.admit(parsed, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 100,
    max_total_string_bytes: 1000,
  }).unwrap()
}

///|
test "Calendar exact Timestamp literal admission retains valid original endpoints" {
  let start = "2000-01-01T00:00:00.000Z"
  let end = "2000-01-01T00:00:00.000000001Z"
  let admitted = @calendar_options.read(
    Series,
    exact_calendar_source(start, end),
    None,
    { max_work: 1000, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  guard @calendar_options.input(admitted)
    is Range(start=Literal(a), end=Literal(z)) else {
    fail("the same original literal endpoints must remain available")
  }
  assert_eq(a, start)
  assert_eq(z, end)
}

///|
test "Calendar exact reversed literal range refuses without UTF16 ordering" {
  match
    @calendar_options.read(
      Series,
      exact_calendar_source(
        "2000-01-01T00:00:00.000000001Z", "2000-01-01T00:00:00.000Z",
      ),
      None,
      { max_work: 1000, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
    ) {
    Err(issue) => assert_eq(issue.kind, @calendar_options.ReversedRange)
    _ => fail("exactly reversed original endpoints must refuse")
  }
}

///|
test "Calendar endpoint admission keeps malformed finer strings invalid" {
  for
    text in [
      "2000-01-01T00:00:00.0000Z", "2000-01-01T00:00:00.1234567891Z", "2000-01-01T00:00:00.123+00:00",
      "1900-02-29T00:00:00.123456789Z",
    ] {
    match
      @calendar_options.read(
        Series,
        exact_calendar_source(text, "2000-01-02T00:00:00.000Z"),
        None,
        { max_work: 1000, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
      ) {
      Err(issue) => assert_eq(issue.kind, @calendar_options.InvalidTimestamp)
      _ => fail("this extension must not admit unrelated timestamp spellings")
    }
  }
}
