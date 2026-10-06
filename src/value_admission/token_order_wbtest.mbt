///|
test "bounded canonical tokens retain independent UTF16 order and exact work" {
  let prefix = "[\"text\",\"" + "x".repeat(512)
  // UTF-16 compares the high surrogate D800 before E000. The common prefix
  // contributes 521 units; a differing next unit contributes one more.
  for
    (left, right, expected, units) in [
      ("[]", "[]", 0, 2),
      ("1", "10", -1, 1),
      (prefix + "a\"]", prefix + "b\"]", -1, 522),
      (prefix + "b\"]", prefix + "a\"]", 1, 522),
      (prefix + "𐀀\"]", prefix + "\ue000\"]", -1, 522),
      (prefix + "𐀀\"]", prefix + "𐀁\"]", -1, 523),
      (prefix + "a\"]", prefix + "a\"]", 0, 524),
      ("10", "1", 1, 1),
    ] {
    for quantum in [1, 7, 256] {
      let active = start_bounded_token_comparison(left, right)
      let mut work = 0
      for _ in 0..<1024 {
        match advance_bounded_key_comparison(active, quantum).unwrap() {
          KeyComparisonContinue(work=used) => {
            assert_true(used > 0 && used <= quantum)
            work += used
          }
          KeyComparisonComplete(order~, work=used) => {
            work += used
            assert_eq(order, expected)
            assert_eq(work, units)
            assert_true(active.null_order is None)
            assert_true(
              advance_bounded_key_comparison(active, 1) is Err(InvalidKey),
            )
            break
          }
        }
      } nobreak {
        abort("finite token comparison did not complete")
      }
      if units > 1 {
        let short = start_bounded_token_comparison(left, right)
        assert_true(
          advance_bounded_key_comparison(short, units - 1)
          is Ok(KeyComparisonContinue(work=used)) &&
          used == units - 1,
        )
        assert_true(
          advance_bounded_key_comparison(short, 1)
          is Ok(KeyComparisonComplete(order~, work=1)) &&
          order == expected,
        )
      }
    }
  }
}
