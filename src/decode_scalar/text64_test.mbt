///|
test "wide UTF8 admission preserves exact counts without narrowing allowance" {
  for limit in [2147483648L, 9007199254740991L, 9223372036854775807L] {
    assert_eq(admit_utf8_length64("aé日😀", limit), Ok(10L))
    assert_eq(admit_utf8_length64("", limit), Ok(0L))
  }
  for text in ["", "a", "界", "😀", "aé日😀", "\n\r"] {
    for limit = -1; limit <= 16; limit = limit + 1 {
      match admit_utf8_length(text, limit) {
        Ok(size) =>
          assert_eq(
            admit_utf8_length64(text, limit.to_int64()),
            Ok(size.to_int64()),
          )
        Err(issue) =>
          assert_eq(admit_utf8_length64(text, limit.to_int64()), Err(issue))
      }
    }
  }
  assert_eq(
    admit_utf8_length64("", -9223372036854775807L - 1L),
    Err(InvalidLimit),
  )
  let malformed = "😀".unsafe_substring(start=0, end=1)
  assert_eq(
    admit_utf8_length64(malformed, 9223372036854775807L),
    Err(MalformedUtf16(0)),
  )
  assert_eq(admit_utf8_length64("😀", 3L), Err(LimitExceeded))
  for sample in [("a", 1), ("界", 3), ("😀", 4)] {
    let (unit, width) = sample
    let text = unit.repeat(1048576 / width + 2)
    let expected = (1048576 / width + 2) * width
    assert_eq(
      admit_utf8_length64(text, expected.to_int64()),
      Ok(expected.to_int64()),
    )
    assert_eq(
      admit_utf8_length64(text, expected.to_int64() - 1L),
      Err(LimitExceeded),
    )
    assert_eq(
      admit_utf8_length64(text, 9223372036854775807L),
      Ok(expected.to_int64()),
    )
  }
}
