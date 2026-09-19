///|
test "normalization follows ordered f32 admission and f64 folds" {
  let mut sum = 0.0
  sum = squared_norm_step(sum, 3.0).unwrap()
  sum = squared_norm_step(sum, 4.0).unwrap()
  let divisor = normalization_divisor(sum).unwrap()
  assert_eq(divisor, 5.0)
  assert_eq(normalize_component(3.0, divisor), Ok(0.6000000238418579))
  assert_eq(normalize_component(4.0, divisor), Ok(0.800000011920929))
}

///|
test "normalization rejects zero and non-finite quantized components" {
  assert_eq(normalization_divisor(0.0), Err(ZeroVector))
  assert_eq(quantize(1.0 / 0.0), Err(NonFinite))
  assert_eq(quantize(3.402823669209385e38 * 2.0), Err(NonFinite))
  assert_eq(quantize(-0.0), Ok(0.0))
}
