///|
test "managed row transfer charges exact UTF-8 bytes" {
  guard managed_row_transfer_bytes("{\"t\":\"ASCII\"}", 13) is Ok(ascii) else {
    fail("ASCII transfer measurement")
  }
  guard managed_row_transfer_bytes("{\"t\":\"日本語\"}", 17) is Ok(japanese) else {
    fail("Japanese transfer measurement")
  }
  guard managed_row_transfer_bytes("{\"t\":\"😀\"}", 12) is Ok(supplementary) else {
    fail("supplementary transfer measurement")
  }
  assert_eq(ascii, 13L)
  assert_eq(japanese, 17L)
  assert_eq(supplementary, 12L)
  assert_true(
    managed_row_transfer_bytes("{\"t\":\"日本語\"}", 16)
    is Err(Configuration(InputUnavailable)),
  )
}
