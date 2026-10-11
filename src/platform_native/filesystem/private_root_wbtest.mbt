///|
#borrow(root)
extern "C" fn test_private_mode(root : Root, mode : Int) -> Bool = "actql_native_filesystem_test_private_mode"

///|
test "Native private Host root binds actual custody and rejects broad or aliased roots" {
  let private_path = @env.get_env_var("ACTQL_TEST_NATIVE_PRIVATE_ROOT").unwrap()
  let broad_path = @env.get_env_var("ACTQL_TEST_NATIVE_BROAD_ROOT").unwrap()
  let alias_path = @env.get_env_var("ACTQL_TEST_NATIVE_PRIVATE_ALIAS").unwrap()
  let root = open_private_root(private_path).unwrap()
  let original = root.private_ownership().unwrap()
  assert_eq(root.private_ownership().unwrap(), original)
  assert_eq(
    open_root(private_path).unwrap().private_ownership().unwrap(),
    original,
  )
  assert_true(open_root(broad_path) is Ok(_))
  assert_true(open_private_root(broad_path) is Err(RootOpen(_)))
  assert_true(
    open_root(broad_path).unwrap().private_ownership() is Err(RootOpen(_)),
  )
  assert_true(open_private_root(alias_path) is Err(RootOpen(_)))
  assert_true(open_private_root(alias_path + "/") is Err(RootOpen(_)))
  assert_true(open_private_root(alias_path + "/nested") is Err(RootOpen(_)))
  assert_true(open_private_root(private_path + "/.") is Err(RootOpen(_)))
  assert_true(
    open_private_root(private_path + "/../private") is Err(RootOpen(_)),
  )
  assert_true(
    open_private_root(private_path + "\u{0000}ignored") is Err(RootOpen(_)),
  )
}

///|
test "Native private Host root refuses an extended ACL despite private POSIX mode" {
  if @env.get_env_var("ACTQL_TEST_NATIVE_PRIVATE_ACL_ROOT") is Some(path) {
    assert_true(open_root(path) is Ok(_))
    assert_true(open_private_root(path) is Err(RootOpen(_)))
    assert_true(
      open_root(path).unwrap().private_ownership() is Err(RootOpen(_)),
    )
  }
}

///|
test "Native private Host root rechecks current privacy before reuse" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_PRIVATE_ROOT").unwrap()
  let root = open_private_root(path).unwrap()
  let original = root.private_ownership().unwrap()
  assert_true(test_private_mode(root, 0o750))
  let denied = root.private_ownership()
  let denied_open = open_private_root(path)
  // Restore this fixture's mode even if the independent refusal expectation fails.
  assert_true(test_private_mode(root, 0o700))
  assert_true(denied is Err(RootOpen(_)))
  assert_true(denied_open is Err(RootOpen(_)))
  assert_eq(root.private_ownership().unwrap(), original)
}

///|
test "Native private Host root loses custody when the pinned directory is removed" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_PRIVATE_ROOT").unwrap()
  let root = open_private_root(path).unwrap()
  let original = root.create_directory("retired-private-root").unwrap()
  let held = root.open_child("retired-private-root").unwrap()
  assert_eq(held.private_ownership().unwrap(), original)
  assert_true(root.remove_directory("retired-private-root", original).unwrap())
  assert_true(held.private_ownership() is Err(RootOpen(_)))
  let replacement = root.create_directory("retired-private-root").unwrap()
  assert_false(replacement == original)
  assert_true(held.private_ownership() is Err(RootOpen(_)))
  assert_eq(
    root
    .open_child("retired-private-root")
    .unwrap()
    .private_ownership()
    .unwrap(),
    replacement,
  )
  assert_true(
    root.remove_directory("retired-private-root", replacement).unwrap(),
  )
}
