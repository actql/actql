///|
test "Store current component observation cannot replace a legacy Database" {
  // Missing physical fixtures fail at unwrap; this is never an optional pass.
  let (store, _, _, _, _) = native_bundle_fixture("sqlite-component-origin").unwrap()
  let original = store.database.read("runtime_bundle", "catalog").unwrap()
  for heap in [-1L, 0L, 4095L, 4096L, 524288L, 2147483648L] {
    assert_false(store.current_sqlite_component_matches_heap(heap))
  }
  let after = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(after.revision, original.revision)
  assert_eq(after.body, original.body)
  store.retiring = true
  assert_false(store.current_sqlite_component_matches_heap(4096L))
  store.retiring = false
  store.close_checked().unwrap()
  assert_false(store.current_sqlite_component_matches_heap(4096L))
}
