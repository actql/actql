///|
test "finite legacy diagnostics never prove an original current component heap" {
  let (base, root, path) = existing_database_fixture()
  let selected_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = load_library(selected_path, diagnostic_ceiling=Some(128)).unwrap()
  let database = library
    .open_database_with_custody(path + "/component-origin.sqlite3", 1024L)
    .unwrap()
  assert_true(database.diagnostic_ceiling() is Some(128))
  let revision = database.insert("origin", "same", b"original").unwrap()
  for expected in [-1L, 0L, 4095L, 4096L, 524288L, 2147483647L, 2147483648L] {
    assert_false(database.current_component_matches_heap(expected))
  }
  let retained = database.read("origin", "same").unwrap()
  assert_eq(retained.revision, revision)
  assert_eq(retained.body, b"original")
  database.close_checked().unwrap()
  assert_false(database.current_component_matches_heap(524288L))
  // The immutable diagnostic fact and original selected-current observation
  // have different lifetimes. Refusal is not a Library cleanup ACK.
  assert_true(database.diagnostic_ceiling() is Some(128))
  assert_true(library.close_checked() is Err(Physical(_)))
  assert_true(base.close_checked() is Err(Physical(_)))
  root.close().unwrap()
}
