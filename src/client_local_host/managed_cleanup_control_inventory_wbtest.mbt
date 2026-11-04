///|
test "managed cleanup inventory uses central tariff once per physical output" {
  assert_eq(client_local_cleanup_retained_bytes(), 584L)
  assert_eq(
    @execution.preparation_representation_cost(managed_cleanup_control_units),
    Some(584L),
  )
  assert_eq(managed_cleanup_control_units.owned_utf16_units, 0L)
  assert_eq(managed_cleanup_control_units.owned_wire_bytes, 0L)
  assert_true(
    physical_equal(managed_cleanup_control_units, managed_cleanup_control_units),
  )
}
