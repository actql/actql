///|
test "finite admission preserves bits without canonicalizing or rounding" {
  for
    bits in [
      0UL, 0x8000000000000000UL, 1UL, 0x8000000000000001UL, 0x7FEFFFFFFFFFFFFFUL,
      0xFFEFFFFFFFFFFFFFUL, 0x3FF0000000000001UL,
    ] {
    guard read_finite_number(bits.reinterpret_as_double()) is Some(value) else {
      fail("finite word rejected")
    }
    assert_eq(value.reinterpret_as_uint64(), bits)
  }
  for
    bits in [
      0x7FF0000000000000UL, 0xFFF0000000000000UL, 0x7FF8000000000000UL, 0x7FF0000000000001UL,
    ] {
    assert_true(read_finite_number(bits.reinterpret_as_double()) is None)
  }
}
