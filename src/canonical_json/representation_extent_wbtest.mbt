///|
test "representation extent counts original Unicode keys values and containers" {
  let original = from_json(
    { "a": ["e\u0301", "😀", Json::null()], "b": { "x": true } },
    20,
    8,
    100,
    data_keys=true,
  )
  let before = stringify_value(original, 1024, 20, 8)
  let extent = representation_extent(original, 20, 8, 100).unwrap()
  assert_eq(extent.nodes, 7L)
  assert_eq(extent.strings, 5L)
  assert_eq(extent.text_utf16_units, 7L)
  assert_eq(extent.arrays, 1L)
  assert_eq(extent.objects, 2L)
  assert_true(extent.array_backing_slots >= 3L)
  assert_true(extent.object_backing_slots >= 3L)
  assert_eq(stringify_value(original, 1024, 20, 8), before)
  assert_true(representation_extent(original, 6, 8, 100) is Err(InputLimit))
  assert_true(representation_extent(original, 20, 1, 100) is Err(InputLimit))
  assert_true(representation_extent(original, 20, 8, 6) is Err(InputLimit))
}

///|
test "representation extent counts repeated shared values and refuses invalid limits" {
  let shared : CanonicalValue = String("e\u0301")
  let value : CanonicalValue = Array({ values: [shared, shared], })
  let extent = representation_extent(value, 3, 1, 4).unwrap()
  assert_eq(extent.nodes, 3L)
  assert_eq(extent.strings, 2L)
  assert_eq(extent.text_utf16_units, 4L)
  assert_true(representation_extent(value, 0, 1, 4) is Err(InputLimit))
  assert_true(representation_extent(value, 3, -1, 4) is Err(InputLimit))
  assert_true(representation_extent(value, 3, 1, -1) is Err(InputLimit))
}
