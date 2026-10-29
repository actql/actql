///|
test "observed object constructor DATA preserves original wide recipes and checked paths" {
  assert_eq(open_object_construction_extent(0).unwrap(), {
    record_headers: 9L,
    reference_slots: 21L,
    scalar_words: 22L,
  })
  assert_eq(open_object_construction_extent(9).unwrap(), {
    record_headers: 45L,
    reference_slots: 120L,
    scalar_words: 139L,
  })
  assert_true(open_object_construction_extent(-1) is None)
  assert_eq(closed_object_field_construction_extent(Some(9), 1, 3L).unwrap(), {
    record_headers: 179L,
    reference_slots: 541L,
    scalar_words: 483L,
  })
  assert_true(closed_object_field_construction_extent(Some(-1), 1, 0L) is None)
  assert_true(
    closed_object_field_construction_extent(Some(0), 1, 9223372036854775807L)
    is None,
  )
  assert_true(issue_path_construction_extent(9223372036854775807L) is None)
  assert_eq(
    issue_path_construction_extent(2147483647L),
    issue_construction_extent(2147483647),
  )
}
