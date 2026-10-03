///|
test "resumable identity comparison preserves canonical UTF-16 order and resets on completion" {
  for
    (left, right, expected) in [
      ("", "", 0),
      ("", "a", -1),
      ("a", "", 1),
      ("a", "ab", -1),
      ("ab", "a", 1),
      ("ab", "ab", 0),
      ("ab", "ac", -1),
      ("ac", "ab", 1),
      ("😀", "\u{e000}", -1),
      ("\u{e000}", "😀", 1),
      ("x".repeat(160) + "b", "x".repeat(160) + "a", 1),
    ] {
    let mut position = 0
    let mut completed = false
    for _ in 0..<(left.length() + right.length() + 1) {
      let (order, next) = graph_identity_compare_unit(left, right, position)
      if order is Some(order) {
        assert_eq(order, expected)
        assert_eq(order, @canonical.compare_utf16(left, right))
        assert_eq(next, 0)
        completed = true
        break
      }
      assert_eq(next, position + 1)
      position = next
    }
    assert_true(completed)
  }
}
