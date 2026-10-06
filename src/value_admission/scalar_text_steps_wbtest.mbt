///|
test "scalar spelling cursor preserves counts bytes and bounded progress" {
  let text = String::make(63, 'a') + "😀" + String::make(65, 'é')
  let checked = checked_text_value(
    text,
    @contract.primitive(@contract.StringType, nullable=false),
  ).unwrap()
  // 129 scalar values, 130 UTF-16 units and 197 preserved UTF-8 bytes.
  // One node, three Text frames (the first crosses the surrogate boundary)
  // and one terminal frame, not a full synchronous scalar scan.
  for (limit, success) in [(197, true), (196, false)] {
    let cursor = start_scalar_text(checked, limit).unwrap()
    let mut polls = 0
    let mut terminal = false
    while !terminal && polls < 6 {
      polls += 1
      match advance_scalar_text(cursor) {
        ScalarTextContinue => assert_true(polls < 5)
        ScalarTextComplete(actual, count, bytes) => {
          assert_true(success)
          assert_eq(actual, text)
          assert_eq(count, 129)
          assert_eq(bytes, 197)
          assert_eq(polls, 5)
          terminal = true
        }
        ScalarTextFailed => {
          assert_false(success)
          assert_eq(polls, 4)
          terminal = true
        }
      }
    }
    assert_true(terminal)
    assert_true(cursor.text is None)
    assert_true(cursor.recheck is None)
    assert_true(advance_scalar_text(cursor) is ScalarTextFailed)
  }
  assert_eq(canonical_scalar_text(checked, 197), Some(text))
  assert_eq(canonical_scalar_text(checked, 196), None)
}

///|
test "scalar spelling cancellation releases its borrowed text and recheck" {
  let text = String::make(1024, 'x')
  let cursor = start_scalar_text(
    checked_text_value(
      text,
      @contract.primitive(@contract.StringType, nullable=false),
    ).unwrap(),
    1024,
  ).unwrap()
  assert_true(advance_scalar_text(cursor) is ScalarTextContinue)
  assert_true(advance_scalar_text(cursor) is ScalarTextContinue)
  cancel_scalar_text(cursor)
  cancel_scalar_text(cursor)
  assert_true(cursor.text is None)
  assert_true(cursor.recheck is None)
  assert_true(advance_scalar_text(cursor) is ScalarTextFailed)
  assert_eq(text.length(), 1024)
}

///|
test "scalar spelling short path keeps raw values and typed rejection" {
  for
    (wire, expected, count, bytes) in [
      ("\"e\\u0301\\r\\n\"", "e\u{0301}\r\n", 4, 5),
      ("\"é\\r\\n\"", "é\r\n", 3, 4),
    ] {
    let value = admitted_scalar(
      "{\"type\":\"string\",\"nullable\":false}", wire,
    )
    let cursor = start_scalar_text(value, bytes).unwrap()
    guard advance_scalar_text(cursor)
      is ScalarTextComplete(actual, characters, length) else {
      abort("short scalar spelling did not complete")
    }
    assert_eq(actual, expected)
    assert_eq(characters, count)
    assert_eq(length, bytes)
  }
  assert_true(
    start_scalar_text(
      admitted_scalar("{\"type\":\"string\",\"nullable\":true}", "null"),
      100,
    )
    is None,
  )
}
