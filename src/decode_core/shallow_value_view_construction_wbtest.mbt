///|
test "shallow view quote includes detached array Cursors and original object Map" {
  // Independently expanded constructor families: array 9H31R8W and object
  // 17H43R48W for these widths. Neither branch borrows the other's storage.
  assert_eq(
    shallow_value_view_construction_extent(3, 2),
    Some({ record_headers: 26L, reference_slots: 74L, scalar_words: 56L, }),
  )
  assert_true(shallow_value_view_construction_extent(-1, 0) is None)
  assert_true(shallow_value_view_construction_extent(0, -1) is None)
  let parsed = @source.parse_json_literal("{\"a\":[1,2,3],\"b\":null}", {
    max_input_bytes: 100,
    max_nodes: 20,
    max_depth: 5,
  }).unwrap()
  let root = admit(parsed.node, {
    max_nodes: 20,
    max_depth: 5,
    max_string_bytes: 100,
    max_total_string_bytes: 100,
  }).unwrap()
  guard view(root) is ObjectValue(object) else { fail("object view") }
  let original_array = lookup(object, "a").unwrap()
  guard view(original_array) is ArrayValue(children) else { fail("array view") }
  assert_eq(children.length(), 3)
  assert_eq(tree_index(root, children[2]), Some(4))
  children.clear()
  assert_eq(array_length(original_array), Some(3))
  assert_eq(object_length(root), Some(2))
}
