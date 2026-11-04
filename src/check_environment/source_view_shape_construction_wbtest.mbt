///|
test "selected shape validator inventory includes the same complete generated rule and frame" {
  let generated = source_view_rule_construction()
  let frame = source_view_shape_frame_construction(12L, 5L, 1L, 15L, true)
  let actual = source_view_shape_validation_construction_extent(12, 5, 1, 3).unwrap()
  assert_eq(
    actual,
    @shape.add_collection_construction_extents(frame, generated).unwrap(),
  )
  // Independent full generated rule count: raw233 records and99 arrays,
  // expanded by the existing collection owner. A selected subrule does not
  // make its enclosing generated constructor disappear.
  assert_eq(actual.record_headers - frame.record_headers, 530L)
  assert_eq(actual.reference_slots - frame.reference_slots, 2095L)
  assert_eq(actual.scalar_words - frame.scalar_words, 476L)
  assert_eq(
    @shape.add_collection_construction_extents(actual, actual).unwrap().record_headers,
    2L * actual.record_headers,
  )
}

///|
test "selected shape validator inventory refuses impossible geometry" {
  assert_true(
    source_view_shape_validation_construction_extent(0, 0, 0, 0) is None,
  )
  assert_true(
    source_view_shape_validation_construction_extent(1, 2, 0, 0) is None,
  )
  assert_true(
    source_view_shape_validation_construction_extent(1, 0, -1, 0) is None,
  )
  assert_true(
    source_view_shape_validation_construction_extent(1, 0, 0, -1) is None,
  )
}

///|
test "factoring shape frames preserves the previous whole-view recipe for fixed inputs" {
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  for
    (nodes, fields, items, path, active) in [
      (0L, 0L, 0L, 0L, false),
      (12L, 5L, 1L, 15L, true),
      (400L, 25L, 12L, 416L, true),
    ] {
    // Independent original view_construction shape_frame recipe, unchanged.
    let previous = @shape.collection_construction_extent({
      records: 14L +
      3L * nodes +
      path +
      child.record_headers +
      field.record_headers,
      record_references: 10L +
      6L * nodes +
      path +
      child.reference_slots +
      field.reference_slots,
      record_words: 14L +
      3L * nodes +
      path +
      child.scalar_words +
      field.scalar_words,
      reference_arrays: 2L,
      reference_items: 2L * nodes + path,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: if active {
        2L
      } else {
        0L
      },
      map_entries: fields + items,
    }).unwrap()
    assert_eq(
      source_view_shape_frame_construction(nodes, fields, items, path, active),
      previous,
    )
  }
}
