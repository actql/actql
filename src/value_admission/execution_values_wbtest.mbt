///|
test "computed scalar constructors preserve exact contracts" {
  let boolean = @contract.primitive(@contract.BooleanType, nullable=false)
  let text = @contract.string_contract(
    nullable=false,
    min_length=Some(4L),
    max_codepoints=Some(4L),
    max_utf8_bytes=Some(4L),
  ).unwrap()
  assert_true(checked_boolean_value(true, boolean) is Some(_))
  assert_true(checked_boolean_value(true, text) is None)
  assert_true(checked_text_value("keep", text) is Some(_))
  assert_true(checked_text_value("mark!", text) is None)
}

///|
test "event clocks use the declared numeric or UTC encoding" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let timestamp = @contract.primitive(@contract.TimestampType, nullable=false)
  let numeric : CheckedValue = { contract: number, value: Number(12.5), }
  let utc : CheckedValue = {
    contract: timestamp,
    value: Timestamp("1970-01-01T00:00:01.250Z"),
  }
  assert_eq(event_time_milliseconds(numeric, false), Some(12.5))
  assert_eq(event_time_milliseconds(utc, true), Some(1250.0))
  assert_true(event_time_milliseconds(numeric, true) is None)
  assert_true(event_time_milliseconds(utc, false) is None)
}
