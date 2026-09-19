// Generated from independent fixed numeric vectors.
///|
test "independent vector numeric: quantize_positive_zero" {
  let actual = quantize((0x0000000000000000UL).reinterpret_as_double()).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x0000000000000000UL)
}

///|
test "independent vector numeric: quantize_negative_zero" {
  let actual = quantize((0x8000000000000000UL).reinterpret_as_double()).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x0000000000000000UL)
}

///|
test "independent vector numeric: quantize_tie_to_even_lower" {
  let actual = quantize((0x3ff0000010000000UL).reinterpret_as_double()).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x3ff0000000000000UL)
}

///|
test "independent vector numeric: quantize_tie_to_even_upper" {
  let actual = quantize((0x3ff0000030000000UL).reinterpret_as_double()).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x3ff0000040000000UL)
}

///|
test "independent vector numeric: quantize_minimum_binary32_subnormal" {
  let actual = quantize((0x36a0000000000000UL).reinterpret_as_double()).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x36a0000000000000UL)
}

///|
test "independent vector numeric: quantize_half_minimum_subnormal" {
  let actual = quantize((0x3690000000000000UL).reinterpret_as_double()).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x0000000000000000UL)
}

///|
test "independent vector numeric: quantize_maximum_binary32" {
  let actual = quantize((0x47efffffe0000000UL).reinterpret_as_double()).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x47efffffe0000000UL)
}

///|
test "independent vector numeric: quantize_binary32_overflow" {
  assert_eq(quantize((0x47f0000000000000UL).reinterpret_as_double()), Err(NonFinite))
}

///|
test "independent vector numeric: quantize_positive_infinity" {
  assert_eq(quantize((0x7ff0000000000000UL).reinterpret_as_double()), Err(NonFinite))
}

///|
test "independent vector numeric: quantize_nan" {
  assert_eq(quantize((0x7ff8000000000000UL).reinterpret_as_double()), Err(NonFinite))
}

///|
test "independent vector numeric: normalize_three_four" {
  let input = [(0x4008000000000000UL).reinterpret_as_double(), (0x4010000000000000UL).reinterpret_as_double()]
  let mut sum = 0.0
  for component in input {
    sum = squared_norm_step(sum, component).unwrap()
  }
  assert_eq(sum.reinterpret_as_uint64(), 0x4039000000000000UL)
  let divisor = normalization_divisor(sum).unwrap()
  assert_eq(divisor.reinterpret_as_uint64(), 0x4014000000000000UL)
  let output_0 = normalize_component(input[0], divisor).unwrap()
  assert_eq(output_0.reinterpret_as_uint64(), 0x3fe3333340000000UL)
  let output_1 = normalize_component(input[1], divisor).unwrap()
  assert_eq(output_1.reinterpret_as_uint64(), 0x3fe99999a0000000UL)
}

///|
test "independent vector numeric: normalize_sqrt_boundary" {
  let input = [(0x3ff0000000000000UL).reinterpret_as_double(), (0x3ff0000000000000UL).reinterpret_as_double()]
  let mut sum = 0.0
  for component in input {
    sum = squared_norm_step(sum, component).unwrap()
  }
  assert_eq(sum.reinterpret_as_uint64(), 0x4000000000000000UL)
  let divisor = normalization_divisor(sum).unwrap()
  assert_eq(divisor.reinterpret_as_uint64(), 0x3ff6a09e667f3bcdUL)
  let output_0 = normalize_component(input[0], divisor).unwrap()
  assert_eq(output_0.reinterpret_as_uint64(), 0x3fe6a09e60000000UL)
  let output_1 = normalize_component(input[1], divisor).unwrap()
  assert_eq(output_1.reinterpret_as_uint64(), 0x3fe6a09e60000000UL)
}

///|
test "independent vector numeric: normalize_binary32_subnormal" {
  let input = [(0x36a0000000000000UL).reinterpret_as_double()]
  let mut sum = 0.0
  for component in input {
    sum = squared_norm_step(sum, component).unwrap()
  }
  assert_eq(sum.reinterpret_as_uint64(), 0x2d50000000000000UL)
  let divisor = normalization_divisor(sum).unwrap()
  assert_eq(divisor.reinterpret_as_uint64(), 0x36a0000000000000UL)
  let output_0 = normalize_component(input[0], divisor).unwrap()
  assert_eq(output_0.reinterpret_as_uint64(), 0x3ff0000000000000UL)
}

///|
test "independent vector numeric: normalize_zero_vector" {
  let input = [(0x8000000000000000UL).reinterpret_as_double(), (0x0000000000000000UL).reinterpret_as_double()]
  let mut sum = 0.0
  for component in input {
    sum = squared_norm_step(sum, component).unwrap()
  }
  assert_eq(sum.reinterpret_as_uint64(), 0x0000000000000000UL)
  assert_eq(normalization_divisor(sum), Err(ZeroVector))
}

///|
test "independent vector numeric: normalize_nonfinite_component" {
  let input = [(0x7ff0000000000000UL).reinterpret_as_double()]
  assert_eq(squared_norm_step(0.0, input[0]), Err(NonFinite))
}

///|
test "independent vector numeric: score_dot" {
  let left = [(0x4008000000000000UL).reinterpret_as_double(), (0x4010000000000000UL).reinterpret_as_double()]
  let right = [(0x4010000000000000UL).reinterpret_as_double(), (0x4008000000000000UL).reinterpret_as_double()]
  let fold = prepare_score(Dot)
  for index in 0..<left.length() {
    score_step(fold, left[index], right[index]).unwrap()
  }
  let actual = finish_score(fold).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x4038000000000000UL)
}

///|
test "independent vector numeric: score_cosine" {
  let left = [(0x4008000000000000UL).reinterpret_as_double(), (0x4010000000000000UL).reinterpret_as_double()]
  let right = [(0x4010000000000000UL).reinterpret_as_double(), (0x4008000000000000UL).reinterpret_as_double()]
  let fold = prepare_score(Cosine)
  for index in 0..<left.length() {
    score_step(fold, left[index], right[index]).unwrap()
  }
  let actual = finish_score(fold).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x3feeb851eb851eb8UL)
}

///|
test "independent vector numeric: score_negative_l2_sqrt_boundary" {
  let left = [(0x4008000000000000UL).reinterpret_as_double(), (0x4010000000000000UL).reinterpret_as_double()]
  let right = [(0x4010000000000000UL).reinterpret_as_double(), (0x4008000000000000UL).reinterpret_as_double()]
  let fold = prepare_score(L2)
  for index in 0..<left.length() {
    score_step(fold, left[index], right[index]).unwrap()
  }
  let actual = finish_score(fold).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0xbff6a09e667f3bcdUL)
}

///|
test "independent vector numeric: score_dimension_order_rounding" {
  let left = [(0x4190000000000000UL).reinterpret_as_double(), (0x3ff0000000000000UL).reinterpret_as_double(), (0xc190000000000000UL).reinterpret_as_double()]
  let right = [(0x41a0000000000000UL).reinterpret_as_double(), (0x3ff0000000000000UL).reinterpret_as_double(), (0x41a0000000000000UL).reinterpret_as_double()]
  let fold = prepare_score(Dot)
  for index in 0..<left.length() {
    score_step(fold, left[index], right[index]).unwrap()
  }
  let actual = finish_score(fold).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x0000000000000000UL)
}

///|
test "independent vector numeric: score_subnormal_dot" {
  let left = [(0x36a0000000000000UL).reinterpret_as_double()]
  let right = [(0x3ff0000000000000UL).reinterpret_as_double()]
  let fold = prepare_score(Dot)
  for index in 0..<left.length() {
    score_step(fold, left[index], right[index]).unwrap()
  }
  let actual = finish_score(fold).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x36a0000000000000UL)
}

///|
test "independent vector numeric: score_cosine_zero_vector" {
  let left = [(0x0000000000000000UL).reinterpret_as_double(), (0x8000000000000000UL).reinterpret_as_double()]
  let right = [(0x4010000000000000UL).reinterpret_as_double(), (0x4008000000000000UL).reinterpret_as_double()]
  let fold = prepare_score(Cosine)
  for index in 0..<left.length() {
    score_step(fold, left[index], right[index]).unwrap()
  }
  let actual = finish_score(fold).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x0000000000000000UL)
}

///|
test "independent vector numeric: score_l2_positive_zero" {
  let left = [(0x3ff0000000000000UL).reinterpret_as_double(), (0x3ff0000000000000UL).reinterpret_as_double()]
  let right = [(0x3ff0000000000000UL).reinterpret_as_double(), (0x3ff0000000000000UL).reinterpret_as_double()]
  let fold = prepare_score(L2)
  for index in 0..<left.length() {
    score_step(fold, left[index], right[index]).unwrap()
  }
  let actual = finish_score(fold).unwrap()
  assert_eq(actual.reinterpret_as_uint64(), 0x0000000000000000UL)
}

///|
test "independent vector numeric: score_nonfinite_component" {
  let left = [(0x7ff8000000000000UL).reinterpret_as_double()]
  let right = [(0x3ff0000000000000UL).reinterpret_as_double()]
  let fold = prepare_score(Dot)
  assert_eq(score_step(fold, left[0], right[0]), Err(NonFinite))
}
