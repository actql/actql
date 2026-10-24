///|
test "hash writer construction inventory is finite monotone and refuses negative bounds" {
  assert_true(hash_writer_construction_inventory(-1, 0) is None)
  assert_true(hash_writer_construction_inventory(0, -1) is None)
  let empty = hash_writer_construction_inventory(0, 0).unwrap()
  let one = hash_writer_construction_inventory(1, 1).unwrap()
  assert_true(one.record_headers > empty.record_headers)
  assert_true(one.reference_slots > empty.reference_slots)
  assert_true(one.scalar_words > empty.scalar_words)
  assert_eq(one.owned_wire_bytes, empty.owned_wire_bytes)
  assert_eq(one.owned_utf16_units, empty.owned_utf16_units)
  assert_true(hash_writer_construction_inventory(2147483647, 2147483647) is Some(_))
}
