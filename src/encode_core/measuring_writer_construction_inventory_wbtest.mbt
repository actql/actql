///|
test "measure sink inventory delegates frame owner and counts finish tuple" {
  assert_true(measuring_writer_construction_extent(-1, 1) is None)
  assert_true(measuring_writer_construction_extent(1, -1) is None)
  for (keys, depth) in [(0, 0), (4, 2), (129, 30)] {
    let value = measuring_writer_construction_extent(keys, depth).unwrap()
    let frames = writer_frame_construction_extent(keys, depth)
    assert_eq(value.record_headers, frames.record_headers + 2L)
    assert_eq(value.scalar_words, frames.scalar_words + 3L)
    assert_eq(value.reference_slots, frames.reference_slots)
  }
}
