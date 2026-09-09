///|
test "UTF-16 errors are distinct from resource rejection" {
  let high = "😀".unsafe_substring(start=0, end=1)
  let low = "😀".unsafe_substring(start=1, end=2)
  for text in [high, low, high + "a", high + high] {
    assert_eq(admit_utf8_length(text, 100), Err(MalformedUtf16(0)))
    assert_eq(utf8_length_within(text, 100), None)
  }
  assert_eq(admit_utf8_length("a" + high, 100), Err(MalformedUtf16(1)))
  assert_eq(admit_utf8_length(high + low, 4), Ok(4))
  assert_eq(admit_utf8_length(high + low, 3), Err(LimitExceeded))
  assert_eq(admit_utf8_length("", -1), Err(InvalidLimit))
}

///|
test "UTF-8 admission exact widths and bounded totals" {
  for
    pair in [
      ("", 0),
      ("abc", 3),
      ("é", 2),
      ("日本", 6),
      ("😀", 4),
      ("aé日😀", 10),
    ] {
    let (text, size) = pair
    assert_eq(utf8_length_within(text, size), Some(size))
    assert_eq(utf8_length_within(text, size + 1), Some(size))
    assert_eq(utf8_length_within(text, size - 1), None)
    assert_eq(utf8_length_within(text, 2147483647), Some(size))
  }
}
