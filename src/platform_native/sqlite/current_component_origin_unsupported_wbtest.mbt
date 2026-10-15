///|
test "unsupported Database never supplies a current component origin" {
  let database : Database = { unsupported: (), }
  for expected in [-1L, 0L, 4096L, 524288L, 2147483648L] {
    assert_false(database.current_component_matches_heap(expected))
  }
}
