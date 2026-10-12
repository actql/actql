///|
test "common CSV escape preserves independent bytes and logical work across quanta" {
  let text = "é😀,;\r\n\"\\N"
  let expected = "\"é😀,;\r\n\"\"\\N\""
  // 16 UTF-8 bytes: two framing quotes, 2+4 for Unicode, two delimiters,
  // CRLF, the doubled data quote and literal backslash/N. Nine data scalars.
  for quantum in [1, 7, 64] {
    let cursor = start_csv_quoted_text(text, 16).unwrap()
    let actual = StringBuilder()
    let mut work = 0
    let mut done = false
    for _ in 0..<20 {
      let (piece, complete, used) = advance_csv_quoted_text(cursor, quantum).unwrap()
      assert_true(used > 0 && used <= quantum)
      assert_true(@utf8.encode(piece).length() <= 4 * quantum)
      actual.write_string(piece)
      work += used
      if complete {
        done = true
        break
      }
    }
    assert_true(done && cursor.text is None)
    assert_eq(actual.to_string(), expected)
    assert_eq(@utf8.encode(expected).length(), 16)
    assert_eq(cursor.bytes, 16)
    assert_eq(work, 11)
    assert_true(
      advance_csv_quoted_text(cursor, quantum)
      is Err(DeliverySerializationClosed),
    )
    cancel_csv_quoted_text(cursor)
    cancel_csv_quoted_text(cursor)
    assert_eq(cursor.bytes, 16)
  }
}

///|
test "common CSV escape enforces one-short bytes and retains data without normalization" {
  for
    (text, expected) in [
      ("", "\"\""),
      ("e\u{301}", "\"e\u{301}\""),
      ("plain", "\"plain\""),
    ] {
    let bytes = @utf8.encode(expected).length()
    let exact = start_csv_quoted_text(text, bytes).unwrap()
    let (output, complete, _) = advance_csv_quoted_text(exact, 64).unwrap()
    assert_true(complete)
    assert_eq(output, expected)
    assert_eq(exact.bytes, bytes)
    let short = start_csv_quoted_text(text, bytes - 1).unwrap()
    assert_true(
      advance_csv_quoted_text(short, 64)
      is Err(DeliverySerializationOutputLimit),
    )
    assert_true(short.text is None)
    assert_true(
      advance_csv_quoted_text(short, 64) is Err(DeliverySerializationClosed),
    )
  }
}

///|
test "common CSV escape cancellation and invalid scalars cannot finalize a partial field" {
  for
    (text, nul) in [
      ("x\u{0}y", true),
      (String::from_array([(0xd800).unsafe_to_char()]), false),
    ] {
    let cursor = start_csv_quoted_text(text, 100).unwrap()
    assert_eq(advance_csv_quoted_text(cursor, 1), Ok(("\"", false, 1)))
    let failure = advance_csv_quoted_text(cursor, 64)
    assert_true(
      if nul {
        failure is Err(DeliverySerializationNul)
      } else {
        failure is Err(DeliverySerializationInvalidRow)
      },
    )
    assert_true(cursor.text is None)
    assert_true(
      advance_csv_quoted_text(cursor, 1) is Err(DeliverySerializationClosed),
    )
  }
  let cursor = start_csv_quoted_text(String::make(10000, 'a'), 20000).unwrap()
  assert_eq(advance_csv_quoted_text(cursor, 1), Ok(("\"", false, 1)))
  cancel_csv_quoted_text(cursor)
  assert_true(cursor.text is None)
  assert_eq(cursor.bytes, 1)
  assert_true(
    advance_csv_quoted_text(cursor, 64) is Err(DeliverySerializationClosed),
  )
}
