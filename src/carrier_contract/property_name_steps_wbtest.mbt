///|
test "Graph name fragments preserve admitted identity without whole-string copies" {
  let left = "A".repeat(129) + "😀"
  let right = "a".repeat(129) + "😀"
  assert_eq(graph_name_identity(left), graph_name_identity(right))
  assert_eq(
    compare_property_name_fragment(left, right, 0, 1000),
    (None, 64, 64),
  )
  assert_eq(
    compare_property_name_fragment(left, right, 64, 64),
    (None, 128, 64),
  )
  assert_eq(
    compare_property_name_fragment(left, right, 128, 64),
    (Some(0), 0, 3),
  )
  for (a, b) in [("a", "A"), ("é", "É"), ("é", "é"), ("😀", "😁")] {
    let (order, _, _) = compare_property_name_fragment(a, b, 0, 64)
    assert_eq(
      order == Some(0),
      graph_name_identity(a) == graph_name_identity(b),
    )
  }
  assert_eq(compare_property_name_fragment(left, right, 0, 0), (None, 0, 0))
  assert_eq(compare_property_name_fragment(left, right, -1, 64), (None, -1, 0))
  assert_eq(compare_property_name_fragment("", "", 0, 64), (Some(0), 0, 0))
}
