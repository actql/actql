///|
test "indexed child reads preserve null ownership source order and coordinates" {
  let fields = [
    entry("z/~", node(@source.Null, start=8), start=2),
    entry(
      "a",
      node(@source.Array([node(@source.Bool(true), start=12)])),
      start=10,
    ),
  ]
  let root = admit(node(@source.Object(fields)), budget()).unwrap()
  fields[0] = entry("changed", node(@source.Number(1)))
  assert_eq(object_length(root), Some(2))
  assert_eq(array_length(root), None)
  assert_true(element_at(root, 0) is None)
  let (name, child) = field_at(root, 0).unwrap()
  assert_eq(name, "z/~")
  assert_true(is_null(child))
  assert_eq(cursor_path(child), [@source.Key("z/~")])
  assert_eq(cursor_span(child), mark(8))
  assert_eq(cursor_key_span(child), Some(mark(2)))
  assert_eq(object_length(child), None)
  assert_eq(array_length(child), None)
  let (_, array) = field_at(root, 1).unwrap()
  assert_eq(array_length(array), Some(1))
  let leaf = element_at(array, 0).unwrap()
  assert_eq(boolean(leaf), Ok(true))
  assert_eq(cursor_path(leaf), [@source.Key("a"), @source.Index(0)])
  for i in [-1, 2, 2147483647] {
    assert_true(field_at(root, i) is None)
  }
  for i in [-1, 1, 2147483647] {
    assert_true(element_at(array, i) is None)
  }
  assert_true(field_at(array, 0) is None)
  assert_true(field_at(child, 0) is None)
  assert_true(element_at(child, 0) is None)
}
