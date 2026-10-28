///|
test "original decoder Issue has one path backing and borrowed names" {
  assert_eq(issue_construction_extent(-1), None)
  assert_eq(issue_construction_extent(0).unwrap(), {
    record_headers: 5L,
    reference_slots: 16L,
    scalar_words: 4L,
  })
  assert_eq(issue_construction_extent(3).unwrap(), {
    record_headers: 8L,
    reference_slots: 28L,
    scalar_words: 10L,
  })
  assert_eq(issue_construction_extent(2147483647).unwrap(), {
    record_headers: 2147483652L,
    reference_slots: 8589934604L,
    scalar_words: 4294967298L,
  })
}
