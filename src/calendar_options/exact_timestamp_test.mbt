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
test "Calendar exact Timestamp literal admission retains valid original endpoints" {
  let text =
    #|{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-01T00:00:00.000000001Z","unit":"day","timezone":"UTC"}
  let parsed = @source.parse_json(text, {
    max_input_bytes: 1000, max_nodes: 100, max_depth: 10,
  }).unwrap()
  let source = @decode.admit(parsed, {
    max_nodes: 100, max_depth: 10, max_string_bytes: 100,
    max_total_string_bytes: 1000,
  }).unwrap()
  assert_true(
    @calendar_options.read(Series, source, None, {
      max_work: 1000, max_nodes: 100, max_depth: 10, max_text_bytes: 1000,
    }) is Ok(_),
  )
}
