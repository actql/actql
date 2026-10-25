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

///|
test "hash writer explicit live key inventory preserves general fallback and depth backing" {
  assert_eq(hash_writer_live_key_inventory(140,10),hash_writer_construction_inventory(140,10))
  let narrow=hash_writer_live_key_inventory(140,10).unwrap()
  let general=hash_writer_construction_inventory(500308,10).unwrap()
  assert_eq(general.record_headers-narrow.record_headers,3L*(500308L-140L))
  assert_eq(general.reference_slots-narrow.reference_slots,10L*(500308L-140L))
  assert_eq(general.scalar_words-narrow.scalar_words,12L*(500308L-140L))
  assert_true(hash_writer_live_key_inventory(0,10).unwrap().record_headers>hash_writer_live_key_inventory(0,0).unwrap().record_headers)
  assert_true(hash_writer_live_key_inventory(-1,10) is None)
}
