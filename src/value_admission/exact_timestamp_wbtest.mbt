///|
test "exact UTC projection preserves negative epochs and the complete calendar range" {
  for
    (text, seconds, nanoseconds) in [
      ("1970-01-01T00:00:00.000Z", 0L, 0),
      ("1969-12-31T23:59:59.999999999Z", -1L, 999999999),
      ("1970-01-01T00:00:00.000000001Z", 0L, 1),
      ("0000-01-01T00:00:00.000000001Z", -62167219200L, 1),
      ("9999-12-31T23:59:59.999999999Z", 253402300799L, 999999999),
      ("2000-02-29T12:34:56.123456Z", 951827696L, 123456000),
    ] {
    let instant = timestamp_instant(text).unwrap()
    assert_eq(instant.seconds, seconds)
    assert_eq(instant.nanoseconds, nanoseconds)
    assert_eq(epoch_parts_timestamp(seconds, nanoseconds), Some(text))
  }
  assert_eq(
    epoch_parts_timestamp(0L, 123000000),
    Some("1970-01-01T00:00:00.123Z"),
  )
  for
    seconds in [
      -9223372036854775808L, -62167219201L, 253402300800L, 9223372036854775807L,
    ] {
    assert_true(epoch_parts_timestamp(seconds, 0) is None)
  }
  assert_true(epoch_parts_timestamp(0L, -1) is None)
  assert_true(epoch_parts_timestamp(0L, 1000000000) is None)
}

///|
test "canonical exact UTC refuses noncanonical fractions and unchanged invalid spellings" {
  for
    text in [
      "1970-01-01T00:00:00.12Z", "1970-01-01T00:00:00.1230Z", "1970-01-01T00:00:00.123456000Z",
      "1970-01-01T00:00:00.1234567891Z", "1970-01-01t00:00:00.123Z", "1970-01-01T00:00:00.123z",
      "1970-01-01T00:00:00.123+00:00", "1900-02-29T00:00:00.123Z", "2000-01-01T00:00:60.123Z",
      "10000-01-01T00:00:00.123Z",
    ] {
    assert_true(timestamp_instant(text) is None)
    assert_false(valid_timestamp(text))
  }
}

///|
test "exact UTC order agrees across typed bounded author and complete sort keys" {
  let contract = @contract.primitive(@contract.TimestampType, nullable=false)
  let a = checked_timestamp_value("1970-01-01T00:00:00.123Z", contract).unwrap()
  let b = checked_timestamp_value("1970-01-01T00:00:00.123000001Z", contract).unwrap()
  assert_eq(compare_key_values(a, b), Ok(-1))
  assert_eq(compare_author_order_values(a, b), Ok(-1))
  assert_eq(compare_group_key_values(b, a), Ok(1))
  assert_true(
    typed_key_order_text(a).unwrap() < typed_key_order_text(b).unwrap(),
  )
  let limits : Limits = { max_nodes: 2, max_depth: 1, max_text_bytes: 64, }
  assert_true(
    complete_order_key(a, limits).unwrap() <
    complete_order_key(b, limits).unwrap(),
  )
  let expected = "[\"timestamp\",\"1970-01-01T00:00:00.123000000Z\"]"
  assert_eq(complete_order_key(a, limits), Ok(expected))
  for bytes in [expected.length(), expected.length() - 1] {
    let cursor = start_complete_order(a, limits, max_output_bytes=Some(bytes)).unwrap()
    let mut completed = false
    let mut failed = false
    for _ in 0..<100 {
      if !completed && !failed {
        match advance_complete_order(cursor, 1) {
          OrderContinue(..) => ()
          OrderComplete(text, bytes~, ..) => {
            assert_eq(text, expected)
            assert_eq(bytes, expected.length())
            completed = true
          }
          OrderFailed(CompleteOrderLimit, ..) => failed = true
          _ => abort("unexpected sort-token failure")
        }
      }
    }
    assert_eq(completed, bytes == expected.length())
    assert_eq(failed, bytes < expected.length())
  }
  for quantum in [1, 2, 7, 31] {
    let cursor = start_bounded_key_comparison(a, b).unwrap()
    let mut done = false
    for _ in 0..<40 {
      if !done {
        match advance_bounded_key_comparison(cursor, quantum).unwrap() {
          KeyComparisonContinue(work~) => assert_true(work <= quantum)
          KeyComparisonComplete(order~, work~) => {
            assert_eq(order, -1)
            assert_true(work <= quantum)
            done = true
          }
        }
      }
    }
    assert_true(done)
  }
}

///|
test "millisecond helpers refuse exact finer Values instead of truncating" {
  let text = "1969-12-31T23:59:59.999999999Z"
  let contract = @contract.primitive(@contract.TimestampType, nullable=false)
  let value = checked_timestamp_value(text, contract).unwrap()
  assert_true(timestamp_epoch_milliseconds(text) is None)
  assert_true(event_time_milliseconds(value, true) is None)
  assert_eq(timestamp_epoch_milliseconds("1969-12-31T23:59:59.999Z"), Some(-1L))
}
