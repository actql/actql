///|
test "nearest identity matching keeps qualification separate from spelling" {
  let plain = @schema.Unqualified("left.id")
  let left = @schema.Qualified(@schema.Left, "id")
  let right = @schema.Qualified(@schema.Right, "id")
  assert_false(nearest_same_name_role(plain, left))
  assert_false(nearest_same_name_role(left, right))
  assert_true(nearest_same_name_role(left, left))
  assert_true(nearest_same_name_role(plain, @schema.Unqualified("other")))
  // The shared comparator intentionally compares reference spelling only.
  // Its equal result must not erase the separate typed-name role check.
  let (order, _, _) = @schema.compare_reference_fragment(plain, left, 0, 64)
  assert_eq(order, Some(0))
}
