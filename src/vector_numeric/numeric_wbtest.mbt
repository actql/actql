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

///|
fn score(
  metric : Metric,
  left : Array[Double],
  right : Array[Double],
) -> Double {
  let fold = prepare_score(metric)
  for index in 0..<left.length() {
    score_step(fold, left[index], right[index]).unwrap()
  }
  finish_score(fold).unwrap()
}

///|
test "scores preserve the pinned dimension-order arithmetic" {
  assert_eq(score(Dot, [3.0, 4.0], [4.0, 3.0]), 24.0)
  assert_eq(score(Cosine, [3.0, 4.0], [4.0, 3.0]), 0.96)
  assert_eq(score(L2, [3.0, 4.0], [4.0, 3.0]), -1.4142135623730951)
}

///|
test "scores keep zero and failure boundaries distinct" {
  assert_eq(score(Cosine, [0.0, 0.0], [4.0, 3.0]), 0.0)
  assert_eq(score(L2, [1.0, 1.0], [1.0, 1.0]), 0.0)
  let fold = prepare_score(Dot)
  assert_eq(score_step(fold, 1.0e308, 1.0e308), Err(NonFinite))
}
