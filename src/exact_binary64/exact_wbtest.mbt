///|
test "support comparison keeps exact binary64 weights" {
  assert_eq(support_at_least([0.1], [0.1, 0.2], 1.0 / 3.0, 4096), Ok(true))
  assert_eq(support_at_least([0.1], [0.1, 0.2], 0.5, 4096), Ok(false))
  assert_eq(support_at_least([], [1.0], 5.0e-324, 4096), Ok(false))
}

///|
test "weighted mean rounds once after exact products" {
  assert_eq(weighted_mean([(6.0, 1.0)], 4096), Ok(6.0))
  assert_eq(weighted_mean([(6.0, 1.0), (0.0, 2.0)], 4096), Ok(2.0))
  assert_eq(
    weighted_mean([(1.0, 1.0), (2.0, 1.0)], 4096)
    .unwrap()
    .reinterpret_as_uint64(),
    0x3ff8000000000000UL,
  )
}

///|
test "weighted mean handles subnormal ties and overflow" {
  let least = 0x0000000000000001UL.reinterpret_as_double()
  assert_eq(
    weighted_mean([(least, 1.0), (0.0, 1.0)], 4096)
    .unwrap()
    .reinterpret_as_uint64(),
    0x0000000000000000UL,
  )
  assert_eq(
    weighted_mean([(least, 3.0), (0.0, 1.0)], 4096)
    .unwrap()
    .reinterpret_as_uint64(),
    0x0000000000000001UL,
  )
  let largest = 0x7fefffffffffffffUL.reinterpret_as_double()
  assert_eq(weighted_mean([(largest, 1.0)], 4096), Ok(largest))
}

///|
test "exact arithmetic rejects invalid domains and bit growth" {
  assert_eq(weighted_mean([], 4096), Err(ZeroDenominator))
  assert_eq(weighted_mean([(1.0, -1.0)], 4096), Err(NegativeWeight))
  assert_eq(
    weighted_mean([(0x7ff0000000000000UL.reinterpret_as_double(), 1.0)], 4096),
    Err(NonFinite),
  )
  assert_eq(weighted_mean([(1.0, 1.0)], 8), Err(BitLimit))
}

///|
test "weighted mean matches independent exact-rational vectors" {
  let vectors = [
    (
      [0x3ff0000000000000UL, 0x4000000000000000UL],
      [0x3ff0000000000000UL, 0x3ff0000000000000UL],
      0x3ff8000000000000UL,
    ),
    (
      [0x3ff0000000000001UL, 0x3fefffffffffffffUL],
      [0x3fd0000000000000UL, 0x3fe8000000000000UL],
      0x3ff0000000000000UL,
    ),
    (
      [0x0010000000000000UL, 0x0000000000000001UL],
      [0x3ff0000000000000UL, 0x3ff0000000000000UL],
      0x0008000000000000UL,
    ),
    (
      [0x7fefffffffffffffUL, 0x3ff0000000000000UL],
      [0x0000000000000001UL, 0x3ff0000000000000UL],
      0x3ff0000000000004UL,
    ),
    (
      [0xbff0000000000000UL, 0x4000000000000000UL],
      [0x4008000000000000UL, 0x4010000000000000UL],
      0x3fe6db6db6db6db7UL,
    ),
    (
      [0xc010000000000000UL, 0x4010000000000000UL],
      [0x3ff0000000000000UL, 0x3ff0000000000000UL],
      0x0000000000000000UL,
    ),
    (
      [0x3eb0c6f7a0b5ed8dUL, 0x444b1ae4d6e2ef50UL],
      [0x3fb999999999999aUL, 0x3e7ad7f29abcaf48UL],
      0x430c6bf3495dcf3fUL,
    ),
  ]
  for (value_bits, weight_bits, expected) in vectors {
    let values = []
    for index in 0..<value_bits.length() {
      values.push(
        (
          value_bits[index].reinterpret_as_double(),
          weight_bits[index].reinterpret_as_double(),
        ),
      )
    }
    assert_eq(
      weighted_mean(values, 4096).unwrap().reinterpret_as_uint64(),
      expected,
    )
  }
}
