///|
test "subtree constructor geometry reads exact original span excluding adjacent siblings" {
  let source = @source.parse_json_literal(
    "{\"outside\":[1,2,3],\"selected\":{\"a\":[1,\"é\"],\"b\":{\"c\":null}},\"tail\":true}",
    { max_input_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let root = admit(source.node, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
  let selected = field_at(root, 1).unwrap().1
  assert_eq(observe_subtree_construction_geometry(selected), {
    nodes: 6,
    arrays: 1,
    array_items: 2,
    objects: 2,
    fields: 3,
    texts: 1,
    max_object_fields: 2,
    max_key_utf16: 1,
    max_text_utf16: 1,
    total_utf16: 4L,
    work: 12L,
  })
  assert_eq(observe_subtree_size(selected), (6, 3L))
  assert_eq(object_length(root), Some(3))
  assert_eq(field_at(root, 2).unwrap().0, "tail")
}

///|
test "subtree constructor geometry preserves scalar Unicode and empty container quantities" {
  let source = @source.parse_json_literal("[\"😀\",{},[]]", {
    max_input_bytes: 100,
    max_nodes: 10,
    max_depth: 4,
  }).unwrap()
  let root = admit(source.node, {
    max_nodes: 10,
    max_depth: 4,
    max_string_bytes: 100,
    max_total_string_bytes: 100,
  }).unwrap()
  let text = element_at(root, 0).unwrap()
  assert_eq(observe_subtree_construction_geometry(text), {
    nodes: 1,
    arrays: 0,
    array_items: 0,
    objects: 0,
    fields: 0,
    texts: 1,
    max_object_fields: 0,
    max_key_utf16: 0,
    max_text_utf16: 2,
    total_utf16: 2L,
    work: 2L,
  })
  let array = observe_subtree_construction_geometry(root)
  assert_eq(
    (array.nodes, array.arrays, array.array_items, array.objects),
    (4, 2, 3, 1),
  )
  assert_eq(
    (array.fields, array.texts, array.total_utf16, array.work),
    (0, 1, 2L, 6L),
  )
}
