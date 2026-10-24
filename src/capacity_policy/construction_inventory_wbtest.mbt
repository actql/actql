///|
test "policy constructor inventory bounds all optional original scalar fields" {
  let inventory = policy_construction_inventory().unwrap()
  let values : Map[String, Int64] = {}
  for field in fields {
    values[field] = 9007199254740991L
  }
  for field in optional_fields {
    values[field] = 9007199254740991L
  }
  let original : Policy = { cid: "borrowed", values, }
  let writer = @encode.writer(10000, 100, 2)
  emit(original, writer)
  let wire = @encode.finish(writer)
  assert_true(wire.length() <= inventory.source_wire_bytes_upper)
  assert_eq(values.length(), inventory.map_entries_upper)
  assert_eq(values.capacity(), inventory.map_backing_slots_upper)
  let mut units = "version".length() + "actql-capacity-host-policy/0.1".length()
  for field in fields {
    units += field.length()
  }
  for field in optional_fields {
    units += field.length()
  }
  assert_eq(units, inventory.source_text_utf16_upper)
  // Reconcile retained logical owners with actual Map occupancy/capacity.
  let n = values.length().to_int64()
  let capacity = values.capacity().to_int64()
  assert_true(inventory.record_headers >= 4L + 3L * n)
  assert_true(inventory.reference_slots >= 4L + 5L * n)
  assert_true(inventory.scalar_words >= 5L + 5L * n + capacity)
}
