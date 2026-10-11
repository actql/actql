///|
/// Compile-only codec boundary. This does not open crypto or disclose a key.
test "holder Review custody key requires exactly canonical 32 bytes" {
  let key = holder_effect_review_key("00".repeat(31) + "ff").unwrap()
  assert_eq(key.length(), 32)
  assert_eq(key[0], b'\x00')
  assert_eq(key[31], b'\xff')
  for
    invalid in [
      "",
      "00".repeat(31),
      "00".repeat(33),
      "00".repeat(31) + "FF",
      "00".repeat(31) + "gg",
      "00".repeat(32) + "\n",
    ] {
    assert_true(holder_effect_review_key(invalid) is None)
  }
}
