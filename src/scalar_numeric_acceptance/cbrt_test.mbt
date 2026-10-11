// Fixed independent decimal brackets. Their exact binary64 endpoint cubes enclose
// the exact binary64 input; no host Math or product output supplies expectations.

///|
test "cbrt finite positive and negative values satisfy independent cube brackets" {
  for
    (input, lower, upper) in [
      (2.0, 1.25992104989487, 1.25992104989488),
      (3.0, 1.44224957030740, 1.44224957030742),
      (10.0, 2.15443469003188, 2.15443469003189),
      (0.5, 0.79370052598409, 0.79370052598411),
      (27.0, 2.99999999999999, 3.00000000000001),
      (125.0, 4.99999999999999, 5.00000000000001),
      (5.0e-324, 1.70318393600325e-108, 1.70318393600327e-108),
      (2.225073858507201e-308, 2.81264428523625e-103, 2.81264428523628e-103),
      (2.2250738585072014e-308, 2.81264428523625e-103, 2.81264428523628e-103),
      (1.7976931348623157e308, 5.64380309412235e102, 5.64380309412238e102),
    ] {
    for (value, lo, hi) in [(input, lower, upper), (-input, -upper, -lower)] {
      guard @execution.unary(@lower.Cbrt, @execution.Number(value))
        is Ok(@execution.Number(actual)) else {
        fail("finite cbrt failed")
      }
      assert_true(actual > lo && actual < hi)
    }
  }
}

///|
test "cbrt preserves exact power of two roots and canonicalizes both zero signs" {
  for
    (input, expected) in [
      (0.0, 0.0),
      (-0.0, 0.0),
      (1.0, 1.0),
      (-1.0, -1.0),
      (8.0, 2.0),
      (-8.0, -2.0),
      (0.125, 0.5),
      (-0.125, -0.5),
      (64.0, 4.0),
    ] {
    guard @execution.unary(@lower.Cbrt, @execution.Number(input))
      is Ok(@execution.Number(actual)) else {
      fail("cbrt exact identity failed")
    }
    assert_eq(actual.reinterpret_as_uint64(), expected.reinterpret_as_uint64())
  }
}
