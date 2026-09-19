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
test "computed text measures Unicode scalar and UTF-8 bounds separately" {
  let text = @contract.string_contract(
    nullable=false,
    min_length=Some(1L),
    max_codepoints=Some(1L),
    max_utf8_bytes=Some(4L),
  ).unwrap()
  assert_true(checked_text_value("😀", text) is Some(_))
  assert_true(
    checked_text_value(
      "😀",
      @contract.string_contract(
        nullable=false,
        max_codepoints=Some(1L),
        max_utf8_bytes=Some(3L),
      ).unwrap(),
    )
    is None,
  )
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

///|
test "epoch milliseconds round trip the complete timestamp domain" {
  for
    text in [
      "0000-01-01T00:00:00.000Z", "0000-02-29T23:59:59.999Z", "1900-02-28T12:34:56.789Z",
      "1970-01-01T00:00:00.000Z", "2000-02-29T00:00:00.001Z", "9999-12-31T23:59:59.999Z",
    ] {
    let milliseconds = timestamp_epoch_milliseconds(text).unwrap()
    assert_eq(epoch_milliseconds_timestamp(milliseconds), Some(text))
  }
  let first = timestamp_epoch_milliseconds("0000-01-01T00:00:00.000Z").unwrap()
  let last = timestamp_epoch_milliseconds("9999-12-31T23:59:59.999Z").unwrap()
  assert_true(epoch_milliseconds_timestamp(first - 1L) is None)
  assert_true(epoch_milliseconds_timestamp(last + 1L) is None)
  assert_true(timestamp_epoch_milliseconds("2001-02-29T00:00:00.000Z") is None)
  let contract = @contract.primitive(@contract.TimestampType, nullable=false)
  assert_true(
    checked_timestamp_value("2000-02-29T00:00:00.000Z", contract) is Some(_),
  )
  assert_true(
    checked_timestamp_value("2001-02-29T00:00:00.000Z", contract) is None,
  )
}
