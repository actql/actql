///|
test "hex word admission is bounded exact and non-normalizing" {
  assert_eq(read_hex_uint64("0000000000000000"), Some(0UL))
  assert_eq(read_hex_uint64("ffffffffffffffff"), Some(0xFFFFFFFFFFFFFFFFUL))
  assert_eq(read_hex_uint64("3FF0000000000000"), Some(0x3FF0000000000000UL))
  assert_eq(read_hex_uint64("8000000000000000"), Some(0x8000000000000000UL))
  for
    value in [
      "", "0", "1", "00000000000000000", "0x00000000000000", "+000000000000000",
      "-000000000000000", "000000000000000 ", "000000000000000g", "００００００００００００００００",
      "000000000000000\n",
    ] {
    assert_true(read_hex_uint64(value) is None)
  }
  for unit in [0xd800, 0xdc00] {
    let malformed = String::from_array([unit.unsafe_to_char()])
    assert_eq(read_hex_uint64("0".repeat(15) + malformed), None)
    assert_eq(read_hex_uint64(malformed + "0".repeat(15)), None)
  }
}
