///|
test "accounting windows charge crossing scalars exactly without slicing text" {
  let high = "😀".unsafe_substring(start=0, end=1)
  assert_eq(admit_utf8_window("abcd" + high, 100L, 6), Err(MalformedUtf16(4)))
  assert_eq(admit_utf8_window("", 1L, 3), Err(InvalidLimit))
  for text in ["abcdefghijk", "界界界界", "😀😀😀", "a界😀b"] {
    let expected = match text {
      "abcdefghijk" => 11L
      "a界😀b" => 9L
      _ => 12L
    }
    for window in [4, 5, 6, 7, 10, 13] {
      assert_eq(admit_utf8_window(text, expected, window), Ok(expected))
      assert_eq(
        admit_utf8_window(text, expected - 1L, window),
        Err(LimitExceeded),
      )
      assert_eq(
        admit_utf8_window(text, 9223372036854775807L, window),
        Ok(expected),
      )
    }
  }
}

///|
test "UTF8 diagnostic precedence and offsets do not depend on allowance width or windows" {
  let high = String::from_array([(0xd800).unsafe_to_char()])
  let low = String::from_array([(0xdc00).unsafe_to_char()])
  let cases : Array[(String, Int, Result[Int, Utf8AdmissionIssue])] = [
    ("", -1, Err(InvalidLimit)),
    (high, -1, Err(InvalidLimit)),
    (high, 0, Err(LimitExceeded)),
    (high, 1, Err(MalformedUtf16(0))),
    (low, 1, Err(MalformedUtf16(0))),
    ("a" + high, 1, Err(LimitExceeded)),
    ("a" + high, 2, Err(MalformedUtf16(1))),
    ("界界" + high, 3, Err(LimitExceeded)),
    ("界" + high, 3, Err(MalformedUtf16(1))),
    ("😀a" + low, 10, Err(MalformedUtf16(3))),
    ("界界界" + high, 9, Err(MalformedUtf16(3))),
    ("界界界" + high, 8, Err(LimitExceeded)),
    ("😀😀" + high, 8, Err(MalformedUtf16(4))),
    ("😀😀" + high, 7, Err(LimitExceeded)),
    ("😀😀", 8, Ok(8)),
    ("😀😀", 7, Err(LimitExceeded)),
    ("\u0000\u007f\u0080\u07ff\u0800\uFFFF\u{10000}\u{10ffff}", 20, Ok(20)),
  ]
  for (text, limit, expected) in cases {
    assert_eq(admit_utf8_length(text, limit), expected)
    let wide = match expected {
      Ok(bytes) => Ok(bytes.to_int64())
      Err(issue) => Err(issue)
    }
    assert_eq(admit_utf8_length64(text, limit.to_int64()), wide)
    for window in [4, 5, 6, 7, 8, 9, 10, 13, 2147483647] {
      assert_eq(admit_utf8_window(text, limit.to_int64(), window), wide)
    }
  }
}

///|
test "ASCII prefix accounting preserves mixed-scalar errors at window edges" {
  let high = String::from_array([(0xd800).unsafe_to_char()])
  for window in [4, 5, 6, 7, 13] {
    for prefix in [0, 1, 3, 4, 5, 6, 7, 12, 13, 14, 27] {
      let text = "a".repeat(prefix) + "界😀b"
      let expected = prefix.to_int64() + 8L
      assert_eq(admit_utf8_window(text, expected, window), Ok(expected))
      assert_eq(
        admit_utf8_window(text, expected - 1L, window),
        Err(LimitExceeded),
      )
      assert_eq(
        admit_utf8_window(text + high, expected + 1L, window),
        Err(MalformedUtf16(prefix + 4)),
      )
    }
  }
}
