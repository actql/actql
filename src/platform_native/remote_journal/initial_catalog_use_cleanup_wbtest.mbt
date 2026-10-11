///|
test "initial Catalog cleanup matches only the original accepted or claimed row" {
  let original = b"original consumer request"
  assert_true(initial_catalog_use_cleanup_row_matches(original, original, 0L))
  assert_true(initial_catalog_use_cleanup_row_matches(original, original, 1L))
  assert_false(
    initial_catalog_use_cleanup_row_matches(original, b"another consumer", 0L),
  )
  assert_false(initial_catalog_use_cleanup_row_matches(original, original, 2L))
  assert_false(initial_catalog_use_cleanup_row_matches(original, original, -1L))
}

///|
test "initial Catalog row matching preserves original bytes rather than normalized values" {
  assert_false(
    initial_catalog_use_cleanup_row_matches(b"\xc3\xa9", b"e\xcc\x81", 1L),
  )
  assert_false(
    initial_catalog_use_cleanup_row_matches(b"line\r\n", b"line\n", 0L),
  )
  assert_false(initial_catalog_use_cleanup_row_matches(b"request", b"", 0L))
}
