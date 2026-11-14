///|
test "measurement operation scratch includes scalar escaping and decimal output" {
  let inventory = measurement_operation_construction_extent()
  assert_eq(inventory.owned_utf16_units, 27L)
  assert_eq(inventory.max_string_utf16_units, 25L)
  assert_eq(inventory.collections.record_headers, 8L)
  let w = measuring_writer(1000, 10, 2)
  begin_ordered_object(w)
  ordered_key(w, "a\u0001")
  number_value(w, 1.2345678901234567e-200)
  ordered_key(w, "b")
  string_value(w, "\u0002😀")
  end_object(w)
  let (_, nodes, depth) = finish_measurement_usage(w)
  assert_eq((nodes, depth), (3, 1))
}
