///|
test "window membership products distinguish zero from overflow at safe integer bounds" {
  for
    (input, factor, expected) in [
      (0L, 9007199254740991L, Some(0L)),
      (1L, 9007199254740991L, Some(9007199254740991L)),
      (9007199254740991L, 1L, Some(9007199254740991L)),
      (3L, 4L, Some(12L)),
      (3002399751580330L, 3L, Some(9007199254740990L)),
      (3002399751580331L, 3L, None),
      (2L, 4503599627370496L, None),
      (9007199254740991L, 9007199254740991L, None),
    ] {
    match expected {
      Some(n) => assert_eq(window_membership_product(input, factor).unwrap(), n)
      None =>
        assert_true(window_membership_product(input, factor) is Err(Overflow))
    }
  }
}
