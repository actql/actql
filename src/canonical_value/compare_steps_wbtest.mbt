///|
test "raw UTF-16 fragments preserve order without folding or normalization" {
  let ordered = [
    "", "\n", "\r", "A", "a", "aa", "e\u{0301}", "é", "\u{D7FF}", "😀", "\u{E000}",
  ]
  for i in 0..<ordered.length() {
    for j in 0..<ordered.length() {
      for allowance in [1, 7, 64, 10000] {
        let mut offset = 0
        let mut terminal = false
        for _ in 0..<8 {
          let (result, next, used) = compare_utf16_fragment(
            ordered[i],
            ordered[j],
            offset,
            allowance,
          )
          assert_true(used <= allowance.min(64))
          if result is Some(actual) {
            assert_eq(actual, if i < j { -1 } else if i > j { 1 } else { 0 })
            assert_eq(next, 0)
            terminal = true
            break
          }
          assert_true(next > offset)
          offset = next
        }
        assert_true(terminal)
      }
    }
  }
  let prefix = "x".repeat(63) + "😀" + "x".repeat(64)
  assert_eq(compare_utf16_fragment(prefix, prefix, 0, 10000), (None, 64, 64))
  assert_eq(compare_utf16_fragment(prefix, prefix, 64, 64), (None, 128, 64))
  assert_eq(compare_utf16_fragment(prefix, prefix, 128, 64), (Some(0), 0, 1))
  assert_eq(compare_utf16_fragment("a", "a", 0, 0), (None, 0, 0))
  assert_eq(compare_utf16_fragment("a", "a", -1, 64), (None, -1, 0))
  assert_eq(compare_utf16_fragment("a", "a", 0, -1), (None, 0, 0))
}
