///|
// Actual non-JS backing, not a normal Resource admission or a heap/RSS bound.
// The scalar ordinal view grows exactly; the builtin Map owns its bucket growth.
test "exact scalar census backing and indexed originals preserve token order across growth" {
  let slots : OriginalTokenSlots[Ref[Int]] = original_token_slots(capacity=6)
  let original = Ref(100)
  slots.push(original, 100)
  let same_values = slots.values
  let same_order = slots.order
  slots.reserve_capacity(20)
  assert_true(physical_equal(slots.values, same_values))
  assert_true(physical_equal(slots.order, same_order))
  assert_eq(slots.order.capacity(), 20)
  assert_true(physical_equal(slots[0], original))
  for index in 1..<20 {
    slots.push(Ref(index), index)
  }
  assert_true(physical_equal(slots.values, same_values))
  assert_eq(slots.order.capacity(), 20)
  assert_true(slots.remove_original(100, original))
  let replacement = Ref(200)
  slots.push(replacement, 200)
  assert_true(physical_equal(slots[19], replacement))
  assert_true(slots.values.capacity() >= 20)
  assert_eq(slots.order.capacity(), 20)
  slots.clear()
  slots.shrink_to_fit()
  assert_true(slots.is_empty())
  assert_false(physical_equal(slots.values, same_values))
  assert_true(same_values.is_empty())
}
