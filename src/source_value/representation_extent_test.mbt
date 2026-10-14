///|
test "Source extent includes original key and value spans without normalization" {
  let root = parse_json_bytes_preserving(
    @utf8.encode("{\"e\\u0301\":[\"😀\",1,null],\"x\":{}}"),
    limits(),
    source_path="j.json",
  ).unwrap()
  let extent = representation_extent(root, 6, 2, 53).unwrap()
  // Six Nodes and two Fields each retain a span and its six-unit source path.
  // Original keys have three units in total; the astral value has two.
  assert_eq(extent.nodes, 6L)
  assert_eq(extent.fields, 2L)
  assert_eq(extent.spans, 8L)
  assert_eq(extent.strings, 11L)
  assert_eq(extent.text_utf16_units, 53L)
  assert_eq(extent.arrays, 1L)
  assert_eq(extent.objects, 2L)
  assert_true(extent.max_frame_slots > 0L)
  assert_true(representation_extent(root, 6, 2, 52) is Err(TextLimit))
  guard root.value is Object(fields) && fields[0].value.value is Array(items) else {
    fail("expected original object/array")
  }
  assert_eq(fields[0].key, "e\u0301")
  assert_true(items[0].value is String("😀"))
  assert_eq(extent.array_backing_slots, items.capacity().to_int64())
  guard fields[1].value.value is Object(empty) else { fail("expected object") }
  assert_eq(
    extent.object_backing_slots,
    fields.capacity().to_int64() + empty.capacity().to_int64(),
  )
}

///|
test "Source extent counts spare backing and repeated original occurrences" {
  let leaf = parsed("null")
  let items = Array::make(17, leaf)
  for _ in 0..<15 {
    ignore(items.pop())
  }
  let root : Node = { value: Array(items), span: leaf.span, }
  let extent = representation_extent(root, 3, 1, 1000000).unwrap()
  assert_eq(extent.nodes, 3L)
  assert_eq(extent.spans, 3L)
  assert_eq(extent.array_backing_slots, items.capacity().to_int64())
  assert_true(extent.array_backing_slots >= 2L)
  assert_eq(items.length(), 2)
  assert_true(physical_equal(items[0], leaf))
  assert_true(physical_equal(items[1], leaf))
  assert_true(representation_extent(root, 2, 1, 1000000) is Err(NodeLimit))
}

///|
test "Source extent observes edits rather than claiming original parse usage" {
  let original = parse_json_measured("[null]", limits()).unwrap()
  guard original.node.value is Array(items) else { fail("expected array") }
  items.push(parsed("\"later\""))
  let extent = representation_extent(original.node, 3, 1, 1000000).unwrap()
  assert_eq(original.usage.nodes, 2)
  assert_eq(extent.nodes, 3L)
  assert_eq(items.length(), 2)
  // Reading representation facts does not validate editable syntax.
  let invalid_text = String::from_array([(0xd800).unsafe_to_char()])
  let malformed : Node = {
    value: String(invalid_text),
    span: parsed("0").span,
  }
  assert_true(representation_extent(malformed, 1, 0, 1000000) is Ok(_))
}

///|
test "Source extent limits bound cycles and deep editable arrays" {
  let leaf = parsed("null")
  let children : Array[Node] = []
  let cycle : Node = { value: Array(children), span: leaf.span, }
  children.push(cycle)
  assert_true(representation_extent(cycle, 3, 50, 1000000) is Err(NodeLimit))
  assert_true(representation_extent(cycle, 50, 3, 1000000) is Err(DepthLimit))
  children.clear()
  assert_true(representation_extent(cycle, 1, 1, 1000000) is Ok(_))
  assert_true(representation_extent(cycle, 1, 0, 1000000) is Err(DepthLimit))
  assert_true(representation_extent(leaf, 0, 0, 0) is Err(InvalidLimits))
  assert_true(representation_extent(leaf, 1, -1, 0) is Err(InvalidLimits))
  assert_true(representation_extent(leaf, 1, 0, -1) is Err(InvalidLimits))
}

///|
test "Source extent separates original Journal envelope and inner use tree" {
  // The existing credential-use domain has four fields. Observing this shape
  // neither admits a use nor proves that a grant/Journal row is authentic.
  let wire = "{\"grant_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"use_id\":\"original-use\",\"use_ordinal\":1,\"version\":\"actql-remote-credential-use/0.1\"}"
  let inner = parse_json_bytes_preserving(
    @utf8.encode(wire),
    limits(),
    source_path="",
  ).unwrap()
  let extent = representation_extent(inner, 5, 1, 147).unwrap()
  assert_eq(extent.nodes, 5L)
  assert_eq(extent.fields, 4L)
  assert_eq(extent.spans, 9L)
  assert_eq(extent.strings, 16L)
  assert_eq(extent.text_utf16_units, 147L)
  assert_eq(extent.objects, 1L)
  assert_eq(extent.arrays, 0L)
  // The outer retained String and independently parsed inner representation
  // coexist. Neither projection subsumes the other or changes original bytes.
  let outer = parse_json(
    "\"" + wire.replace_all(old="\"", new="\\\"") + "\"",
    limits(),
    source_path="",
  ).unwrap()
  let outer_extent = representation_extent(outer, 1, 0, wire.length()).unwrap()
  assert_eq(outer_extent.text_utf16_units, wire.length().to_int64())
  assert_true(outer.value is String(actual) && actual == wire)
  assert_true(representation_extent(inner, 5, 1, 146) is Err(TextLimit))
}

///|
test "Source extent traversal holds bounded frames rather than recursing" {
  let mut tree = parsed("null")
  for _ in 0..<129 {
    tree = { value: Array([tree]), span: tree.span, }
  }
  let extent = representation_extent(tree, 130, 129, 1000000).unwrap()
  assert_eq(extent.nodes, 130L)
  assert_eq(extent.arrays, 129L)
  assert_true(extent.max_frame_slots >= 130L)
  assert_true(representation_extent(tree, 130, 128, 1000000) is Err(DepthLimit))
}
