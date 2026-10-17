///|
test "target order retains original indexes and exact canonical data keys" {
  assert_eq(
    derive_effect_target_row_inventory(
      ["\"c-key\"", "\"b-key\"", "\"a-key\""],
      3,
      128,
      16,
      4,
    ).unwrap(),
    [2, 1, 0],
  )
  assert_eq(
    derive_effect_target_row_inventory(
      ["{\"b\":1,\"a\":2}", "{\"a\":1}"],
      2,
      128,
      16,
      4,
    ).unwrap(),
    [1, 0],
  )
  // NFC and NFD are different data, not a duplicate operational identity.
  assert_eq(
    derive_effect_target_row_inventory(["\"é\"", "\"é\""], 2, 128, 16, 4).unwrap(),
    [1, 0],
  )
}

///|
test "duplicate canonical target identity is refused rather than collapsed" {
  assert_true(
    derive_effect_target_row_inventory(
      ["{\"b\":1,\"a\":2}", "{\"a\":2,\"b\":1}"],
      2,
      128,
      16,
      4,
    )
    is Err(InvalidMember),
  )
  assert_true(
    derive_effect_target_row_inventory(["\"a\"", "\"a\""], 2, 128, 16, 4)
    is Err(InvalidMember),
  )
}

///|
test "target inventory preserves byte node depth and row bounds" {
  assert_true(
    derive_effect_target_row_inventory(["\"a\""], 0, 128, 16, 4)
    is Err(Encoding),
  )
  assert_true(
    derive_effect_target_row_inventory(["\"é\""], 1, 3, 16, 4) is Err(Encoding),
  )
  assert_true(
    derive_effect_target_row_inventory(["{\"a\":{\"b\":1}}"], 1, 128, 16, 1)
    is Err(_),
  )
  assert_true(
    derive_effect_target_row_inventory(["{\"a\":1}"], 1, 128, 1, 4) is Err(_),
  )
  assert_true(
    derive_effect_target_row_inventory(["{\"a\":1,\"a\":2}"], 1, 128, 16, 4)
    is Err(InvalidMember),
  )
}
