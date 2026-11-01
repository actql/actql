///|
test "parsed tree and decoder borrows keep String and Span ownership separate" {
  let strings = @source_value.json_index_borrowed_construction_extent(
    3,
    2,
    11L,
    keep_spans=false,
  ).unwrap()
  assert_eq(strings, {
    record_headers: 5L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 11L,
  })
  let indexed = @source_value.json_index_borrowed_construction_extent(
    3,
    2,
    11L,
    keep_spans=true,
  ).unwrap()
  assert_eq(indexed, {
    record_headers: 10L,
    reference_slots: 5L,
    scalar_words: 30L,
    owned_utf16_units: 11L,
  })
  // Three Node/Value/Span families, two Field/key-Span families, five
  // String headers and one original growable reference container.
  assert_eq(
    @source_value.json_tree_retained_construction_extent(3, 2, 1, 0, 11L),
    Some({
      record_headers: 21L,
      reference_slots: 39L,
      scalar_words: 38L,
      owned_utf16_units: 11L,
    }),
  )
  assert_true(
    @source_value.json_tree_retained_construction_extent(3, 2, 2, 2, 11L)
    is None,
  )
  assert_true(
    @source_value.json_index_borrowed_construction_extent(
      0,
      0,
      0L,
      keep_spans=true,
    )
    is None,
  )
  assert_true(
    @source_value.json_index_borrowed_construction_extent(
      3,
      3,
      11L,
      keep_spans=true,
    )
    is None,
  )
  assert_true(
    @source_value.json_index_borrowed_construction_extent(
      3,
      2,
      -1L,
      keep_spans=false,
    )
    is None,
  )
}

///|
test "span-free Host projection omits only original coordinate records" {
  assert_eq(
    @source_value.json_tree_retained_construction_extent(
      3,
      2,
      1,
      0,
      11L,
      keep_spans=false,
    ),
    Some({
      record_headers: 16L,
      reference_slots: 34L,
      scalar_words: 8L,
      owned_utf16_units: 11L,
    }),
  )
  assert_true(
    @source_value.json_tree_retained_construction_extent(
      3,
      2,
      2,
      2,
      11L,
      keep_spans=false,
    )
    is None,
  )
}
