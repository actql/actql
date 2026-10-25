///|
test "captured context constructor shares rows and funds wire rather than reparsing" {
  let small=publication_capture_constructor_layout(1000,100,5,1,1,1,0).unwrap()
  let large=publication_capture_constructor_layout(1300000,100,5,1,1,1,0).unwrap()
  assert_eq(small.retained.record_headers,large.retained.record_headers)
  assert_eq(small.temporary.record_headers,large.temporary.record_headers)
  assert_eq(large.retained.owned_utf16_units-small.retained.owned_utf16_units,1299000L)
  assert_eq(large.temporary.owned_utf16_units-small.temporary.owned_utf16_units,6495000L)
  assert_true(publication_capture_constructor_layout(1,2147483647,1,1,0,0,0) is None)
}

///|
test "captured context constructor permits original zero-result metadata" {
  assert_true(publication_capture_constructor_layout(1000,100,6,0,0,0,0) is Some(_))
  assert_true(publication_capture_constructor_layout(1000,100,6,0,1,1,0) is None)
}
