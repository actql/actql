///|
test "captured context constructor shares rows and funds wire rather than reparsing" {
  let small = publication_capture_constructor_layout(1000, 100, 5, 1, 1, 1, 0).unwrap()
  let large = publication_capture_constructor_layout(
    1300000, 100, 5, 1, 1, 1, 0,
  ).unwrap()
  assert_eq(small.retained.record_headers, large.retained.record_headers)
  assert_eq(small.temporary.record_headers, large.temporary.record_headers)
  assert_eq(
    large.retained.owned_utf16_units - small.retained.owned_utf16_units,
    1299000L,
  )
  assert_eq(
    large.temporary.owned_utf16_units - small.temporary.owned_utf16_units,
    6495000L,
  )
  assert_true(
    publication_capture_constructor_layout(1, 2147483647, 1, 1, 0, 0, 0) is None,
  )
}

///|
test "captured context constructor permits original zero-result metadata" {
  assert_true(
    publication_capture_constructor_layout(1000, 100, 6, 0, 0, 0, 0) is Some(_),
  )
  assert_true(
    publication_capture_constructor_layout(1000, 100, 6, 0, 1, 1, 0) is None,
  )
}

///|
test "captured recursive rows retain existing trees and fund nested writer key overlap" {
  let flat = publication_capture_constructor_layout(1000, 100, 8, 2, 2, 1, 0).unwrap()
  let recursive = publication_capture_constructor_layout(
    1000,
    100,
    8,
    2,
    2,
    1,
    0,
    row_key_nodes=40,
  ).unwrap()
  // Rows are already held by original snapshots, so nested keys require
  // writer workspace only, never another retained row tree or parser.
  assert_true(flat.retained == recursive.retained)
  assert_true(
    @execution.preparation_representation_cost(recursive.temporary).unwrap() >
    @execution.preparation_representation_cost(flat.temporary).unwrap(),
  )
  assert_true(
    publication_capture_constructor_layout(
      1000,
      100,
      8,
      2,
      2,
      1,
      0,
      row_key_nodes=-1,
    )
    is None,
  )
  assert_true(
    publication_capture_constructor_layout(
      1000,
      100,
      8,
      0,
      0,
      0,
      0,
      row_key_nodes=1,
    )
    is None,
  )
}
