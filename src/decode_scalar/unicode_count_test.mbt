///|
test "Unicode scalar count is exact and rejects isolated surrogates" {
  for
    pair in [
      ("", 0),
      ("abc", 3),
      ("é", 1),
      ("e\u{0301}", 2),
      ("日本😀", 3),
      ("\r\n", 2),
    ] {
    assert_eq(unicode_scalar_count(pair.0), Some(pair.1))
  }
  let high = "😀".unsafe_substring(start=0, end=1)
  let low = "😀".unsafe_substring(start=1, end=2)
  for text in [high, low, high + "x", high + high, low + high] {
    assert_eq(unicode_scalar_count(text), None)
  }
  assert_eq(unicode_scalar_count(high + low), Some(1))
}
