///|
test "initial keyed Definition view accounts for records WeakMap entries and bounds before allocation" {
  let units = keyed_initial_definition_view_representation()
  assert_eq(@execution.preparation_representation_cost(units), Some(288L))
  assert_eq(units.owned_utf16_units, 0L)
  assert_eq(units.owned_wire_bytes, 0L)
}
