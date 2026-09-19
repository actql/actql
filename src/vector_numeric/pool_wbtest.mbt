///|
fn pool_bits(
  reduction : PoolMethod,
  values : Array[UInt64],
) -> Result[UInt64, Issue] {
  let fold = prepare_pool(reduction)
  for bits in values {
    match pool_step(fold, bits.reinterpret_as_double()) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  finish_pool(fold).map(value => value.reinterpret_as_uint64())
}

///|
test "pool sum uses a binary64 fold before final binary32 quantization" {
  assert_eq(
    pool_bits(Sum, [
      0x4170000000000000UL, 0x3ff0000000000000UL, 0xc170000000000000UL,
    ]),
    Ok(0x3ff0000000000000UL),
  )
}

///|
test "pool mean rounds the completed average to binary32" {
  assert_eq(
    pool_bits(Mean, [0x3ff0000000000000UL, 0x4000000000000000UL]),
    Ok(0x3ff8000000000000UL),
  )
}

///|
test "pool max compares quantized inputs and canonicalizes zero" {
  assert_eq(
    pool_bits(Max, [0x8000000000000000UL, 0x0000000000000000UL]),
    Ok(0x0000000000000000UL),
  )
}

///|
test "pool rejects empty and nonfinite folds" {
  assert_eq(finish_pool(prepare_pool(Sum)), Err(InvalidMemberCount))
  let fold = prepare_pool(Max)
  assert_eq(
    pool_step(fold, 0x7ff0000000000000UL.reinterpret_as_double()),
    Err(NonFinite),
  )
}
