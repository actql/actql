///|
// Actual non-JS backing, not a normal Resource admission or a heap/RSS bound.
// Existing arrays and live token identities survive exact capacity growth.
test "exact selected census backing avoids a later geometric allocation and preserves token order" {
  let slots : OriginalTokenSlots[Ref[Int]] = original_token_slots(capacity=6)
  let original = Ref(100)
  slots.push(original)
  let same_slots = slots.slots
  let same_order = slots.order
  slots.reserve_capacity(20)
  assert_true(physical_equal(slots.slots, same_slots))
  assert_true(physical_equal(slots.order, same_order))
  assert_eq(slots.slots.capacity(), 20)
  assert_eq(slots.order.capacity(), 20)
  assert_true(physical_equal(slots[0], original))
  for index in 1..<20 {
    slots.push(Ref(index))
  }
  assert_eq(slots.slots.capacity(), 20)
  assert_eq(slots.order.capacity(), 20)
  assert_true(physical_equal(slots.remove(0), original))
  let replacement = Ref(200)
  slots.push(replacement)
  assert_true(physical_equal(slots[19], replacement))
  assert_eq(slots.slots.capacity(), 20)
  assert_eq(slots.order.capacity(), 20)
}
