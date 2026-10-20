///|
#borrow(root)
extern "C" fn test_namespace_close_failure(root : Root, count : Int) -> Unit = "actql_native_filesystem_test_namespace_close_failure"

///|
#borrow(root)
extern "C" fn test_directory_replacement(root : Root) -> Bool = "actql_native_filesystem_test_directory_replacement"

///|
#borrow(root)
extern "C" fn test_directory_mode(root : Root, mode : Int) -> Bool = "actql_native_filesystem_test_private_mode"

///|
fn directory_observation_fixture(name : String) -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_DIRECTORY_OBSERVATION_ROOT")
    is Some(path) else {
    fail(
      "selected directory observation requires its own canonical fixture Root",
    )
  }
  path + "/" + name
}

///|
test "directory observation compares the same named and opened original" {
  let root = open_root(directory_observation_fixture("exact")).unwrap()
  let original = root.observe_directory().unwrap()
  let identity = original.identity().unwrap()
  original.check_current().unwrap()
  original.check_current().unwrap()
  assert_eq(original.identity().unwrap(), identity)
  root.close().unwrap()
  assert_true(original.check_current() is Err(GenerationMismatch))
  assert_true(original.identity() is Err(GenerationMismatch))
}

///|
test "directory observation refuses alias namespace without replacing its Root" {
  let root = open_root(directory_observation_fixture("alias")).unwrap()
  assert_true(root.observe_directory() is Err(GenerationMismatch))
  root.close().unwrap()
}

///|
test "directory observation refuses renamed and replaced original namespace" {
  let root = open_root(directory_observation_fixture("replacement")).unwrap()
  let original = root.observe_directory().unwrap()
  assert_true(test_directory_replacement(root))
  assert_true(original.check_current() is Err(GenerationMismatch))
  assert_true(original.identity() is Err(GenerationMismatch))
  assert_true(root.observe_directory() is Err(GenerationMismatch))
  root.close().unwrap()
}

///|
test "directory observation refuses a changed original mode" {
  let root = open_root(directory_observation_fixture("mode")).unwrap()
  let original = root.observe_directory().unwrap()
  assert_true(test_directory_mode(root, 0o750))
  assert_true(original.check_current() is Err(GenerationMismatch))
  assert_true(original.identity() is Err(GenerationMismatch))
  root.close().unwrap()
}

///|
test "namespace close Unknown remains on the same Root and blocks observations" {
  let root = open_root(directory_observation_fixture("cleanup")).unwrap()
  let file = root.observe_file("file").unwrap()
  test_namespace_close_failure(root, 1)
  assert_true(root.observe_directory() is Err(Cleanup(_)))
  assert_true(file.check_current() is Err(Cleanup(_)))
  assert_true(
    root.check_directory_members([{ name: "file", kind: File, }])
    is Err(Cleanup(_)),
  )
  assert_true(root.close() is Err(Cleanup(_)))
  assert_true(root.close() is Err(Cleanup(_)))
}

///|
// This is the already selected absolute package namespace, not open_child's
// generic object-name domain or permission to install arbitrary scopes.
test "selected scope directory retains its exact named and opened original" {
  let root = open_root(
    directory_observation_fixture("scope-exact/node_modules/@actql"),
  ).unwrap()
  let original = root.observe_directory().unwrap()
  original.check_current().unwrap()
  original.check_current().unwrap()
  root.close().unwrap()
  assert_true(original.check_current() is Err(GenerationMismatch))
}

///|
test "selected scope namespace refuses a symlink and later directory replacement" {
  // The fixture contains a symlink at the @actql component. General root-open
  // is not the proof; the same Owner's full no-follow namespace read is.
  let aliased_root = open_root(
    directory_observation_fixture("scope-alias/node_modules/@actql"),
  ).unwrap()
  assert_true(aliased_root.observe_directory() is Err(GenerationMismatch))
  aliased_root.close().unwrap()
  let root = open_root(
    directory_observation_fixture("scope-replacement/node_modules/@actql"),
  ).unwrap()
  let original = root.observe_directory().unwrap()
  assert_true(test_directory_replacement(root))
  assert_true(original.check_current() is Err(GenerationMismatch))
  assert_true(root.observe_directory() is Err(GenerationMismatch))
  root.close().unwrap()
}
