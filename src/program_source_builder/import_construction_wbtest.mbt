///|
test "cursor import construction retains original node and text families" {
  assert_true(cursor_import_construction_extent(0, 0) is None)
  assert_true(cursor_import_construction_extent(1, -1) is None)
  let one = cursor_import_construction_extent(1, 0).unwrap()
  let wider = cursor_import_construction_extent(4, 0).unwrap()
  let text = cursor_import_construction_extent(4, 21).unwrap()
  assert_true(wider.record_headers > one.record_headers)
  assert_true(wider.reference_slots > one.reference_slots)
  assert_true(wider.scalar_words > one.scalar_words)
  assert_true(text.owned_utf16_units > wider.owned_utf16_units)
  let index = @wire.admission_construction_inventory(4, 3, 4, 4, 4).unwrap()
  assert_true(
    text.record_headers >
    index.indexed.record_headers +
    index.keys.record_headers +
    index.ancestry.record_headers +
    index.controls.record_headers,
  )
  assert_true(
    text.reference_slots >
    index.indexed.reference_slots +
    index.keys.reference_slots +
    index.ancestry.reference_slots +
    index.controls.reference_slots,
  )
  assert_true(cursor_import_construction_extent(1, 2147483647) is None)
}

///|
test "cursor import construction covers nested fields without retaining caller arrays" {
  let document = @origin.document("request", 1024, source_path="request.sql").unwrap()
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let original = @source.parse_json_bytes(
    b"{\"region\":\"europe\",\"paths\":[\"a\",\"b\"],\"glob\":null}",
    { max_input_bytes: 1024, max_nodes: 100, max_depth: 16, },
  ).unwrap()
  let input_cursor = @wire.admit(original, {
    max_nodes: 100,
    max_depth: 16,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let geometry = @wire.observe_subtree_construction_geometry(input_cursor)
  let extent = cursor_import_construction_extent(
    geometry.nodes,
    geometry.total_utf16.to_int(),
  ).unwrap()
  assert_true(extent.record_headers > 0L && extent.owned_utf16_units > 0L)
  let builder = create(document, {
    source: { max_input_bytes: 1024, max_nodes: 100, max_depth: 16, },
    tree: {
      max_nodes: 100,
      max_depth: 16,
      max_string_bytes: 1024,
      max_total_string_bytes: 1024,
    },
    max_origin_entries: 200,
    max_output_bytes: 1024,
  }).unwrap()
  let imported = import_cursor(builder, input_cursor, generated).unwrap()
  let retained = finish(builder, imported).unwrap()
  assert_eq(usage(retained).nodes, geometry.nodes)
  assert_true(@wire.tree_index(cursor(retained), input_cursor) is None)
}

///|
test "later cursor imports retain expanding normalized keys without changing literal strings" {
  let input = @source.parse_json_literal("{\"\u0344\":\"\u0344\"}", {
    max_input_bytes: 100,
    max_nodes: 10,
    max_depth: 5,
  }).unwrap()
  let input = @wire.admit(input.node, {
    max_nodes: 10,
    max_depth: 5,
    max_string_bytes: 100,
    max_total_string_bytes: 100,
  }).unwrap()
  assert_eq(@wire.observe_subtree_construction_geometry(input).total_utf16, 2L)
  let document = @origin.document("x", 100).unwrap()
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let limits : Limits = {
    source: { max_input_bytes: 100, max_nodes: 20, max_depth: 8, },
    tree: {
      max_nodes: 20,
      max_depth: 8,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    },
    max_origin_entries: 40,
    max_output_bytes: 100,
  }
  let first = create(document, limits).unwrap()
  let first = finish(first, import_cursor(first, input, generated).unwrap()).unwrap()
  let second = create(document, limits).unwrap()
  let second = finish(
    second,
    import_source(second, first, cursor(first)).unwrap(),
  ).unwrap()
  for value in [first, second] {
    let at = cursor(value)
    assert_eq(@wire.field_at(at, 0).unwrap().0, "\u0308\u0301")
    assert_eq(@wire.text(@wire.field_at(at, 0).unwrap().1).unwrap(), "\u0344")
    assert_eq(@wire.observe_subtree_construction_geometry(at).total_utf16, 3L)
  }
  assert_true(@wire.tree_index(cursor(first), cursor(second)) is None)
  assert_eq(@wire.field_at(input, 0).unwrap().0, "\u0344")
}
