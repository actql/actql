///|
#borrow(root)
extern "C" fn test_fail_census_close(root : Root, failures : Int) -> Unit = "actql_native_filesystem_test_fail_census_close"

///|
fn census_fixture_path(name : String) -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CENSUS_ROOT") is Some(path) else {
    fail("selected census case requires its owned fixture Root")
  }
  path + "/" + name
}

///|
fn census_fixture_members() -> Array[NativeDirectoryMember] {
  [{ name: "LICENSE", kind: File, }, { name: "bin", kind: Directory, }]
}

///|
test "bounded census observes exactly the same opened Root repeatedly" {
  let root = open_root(census_fixture_path("exact")).unwrap()
  assert_true(root.check_directory_members(census_fixture_members()) is Ok(_))
  assert_true(root.check_directory_members(census_fixture_members()) is Ok(_))
  root.close().unwrap()
  root.close().unwrap()
  assert_true(root.check_directory_members(census_fixture_members()) is Err(_))
}

///|
test "bounded census rejects missing extra empty directory and symlink members" {
  for name in ["missing", "extra", "extra-empty", "symlink", "wrong-kind"] {
    let root = open_root(census_fixture_path(name)).unwrap()
    assert_true(
      root.check_directory_members(census_fixture_members())
      is Err(GenerationMismatch),
    )
    root.close().unwrap()
  }
}

///|
test "bounded census refuses duplicate nonordered names and invalid intake" {
  let root = open_root(census_fixture_path("exact")).unwrap()
  assert_true(
    root.check_directory_members([
      { name: "LICENSE", kind: File, },
      { name: "LICENSE", kind: File, },
    ])
    is Err(InvalidName),
  )
  assert_true(
    root.check_directory_members([
      { name: "bin", kind: Directory, },
      { name: "LICENSE", kind: File, },
    ])
    is Err(InvalidName),
  )
  assert_true(
    root.check_directory_members([{ name: "../escape", kind: File, }])
    is Err(InvalidName),
  )
  assert_true(root.check_directory_members(census_fixture_members()) is Ok(_))
  root.close().unwrap()
}

///|
test "bounded census accepts a truly empty opened directory" {
  let root = open_root(census_fixture_path("empty")).unwrap()
  root.check_directory_members([]).unwrap()
  root.check_directory_members([]).unwrap()
  root.close().unwrap()
}

///|
test "unconfirmed census close stays with the same Root beyond its fd close" {
  let root = open_root(census_fixture_path("cleanup")).unwrap()
  test_fail_census_close(root, 1)
  assert_true(
    root.check_directory_members(census_fixture_members()) is Err(Cleanup(_)),
  )
  assert_true(
    root.check_directory_members(census_fixture_members()) is Err(Cleanup(_)),
  )
  assert_true(root.close() is Err(Cleanup(_)))
  // Another observation cannot reinterpret the old consumed descriptor as ACK.
  assert_true(root.close() is Err(Cleanup(_)))
}

///|
test "census-only scope spelling does not weaken ordinary object names" {
  assert_false(valid_object_name("@actql"))
  assert_true(valid_census_member_name({ name: "@actql", kind: Directory, }))
  assert_false(valid_census_member_name({ name: "@actql", kind: File, }))
  for
    name in [
      "@other", "@ACTQL", "@actql/child", "../@actql", "@actql.", "@actql\u{0}",
    ] {
    assert_false(valid_census_member_name({ name, kind: Directory, }))
  }
}

///|
test "scope directory census retains exact kind membership and no-follow rejection" {
  let expected : Array[NativeDirectoryMember] = [
    { name: "@actql", kind: Directory, },
  ]
  let exact = open_root(census_fixture_path("scoped-exact")).unwrap()
  exact.check_directory_members(expected).unwrap()
  // Both the public boundary and raw borrowed frame reject file-kind spelling.
  assert_true(
    exact.check_directory_members([{ name: "@actql", kind: File, }])
    is Err(InvalidName),
  )
  assert_eq(directory_census_ffi(exact, b"f@actql\x00", 8, 1), 4)
  assert_eq(directory_census_ffi(exact, b"d@other\x00", 8, 1), 4)
  exact.close().unwrap()
  for name in ["scoped-file", "scoped-other", "scoped-extra", "scoped-symlink"] {
    let root = open_root(census_fixture_path(name)).unwrap()
    assert_true(
      root.check_directory_members(expected) is Err(GenerationMismatch),
    )
    root.close().unwrap()
  }
}
