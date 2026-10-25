///|
test "compilation caller control recipe is the same immutable owner and one logical tariff" {
  let first = closed_values_compilation_call_controls()
  let second = closed_values_compilation_call_controls()
  assert_true(physical_equal(first, second))
  assert_eq(preparation_representation_cost(first), Some(70272L))
}
