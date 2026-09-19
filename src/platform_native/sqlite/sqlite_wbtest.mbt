///|
test "native SQLite rejects a missing runtime library" {
  guard load_library("/actql/missing/libsqlite3") is Err(LibraryLoad(_)) else {
    fail("missing SQLite runtime library was accepted")
  }
}

///|
test "native SQLite journal persists and fences competing revisions" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = load_library(path).unwrap()
  assert_true(!library.version().is_empty())
  let database_path = root + "/journal-" + @env.now().to_string() + ".sqlite3"
  let first = library.open_database(database_path, 16L).unwrap()
  let second = library.open_database(database_path, 16L).unwrap()
  guard first.read("", "one") is Err(InvalidName) else {
    fail("empty journal scope was accepted")
  }
  assert_eq(first.insert("dispatch", "one", b"accepted").unwrap(), 0L)
  assert_eq(first.insert("dispatch", "three", b"later").unwrap(), 0L)
  assert_eq(first.insert("other", "two", b"separate").unwrap(), 0L)
  guard first.insert("dispatch", "one", b"duplicate") is Err(Collision) else {
    fail("duplicate journal insert was accepted")
  }
  let initial = second.read("dispatch", "one").unwrap()
  assert_eq(initial.revision, 0L)
  assert_eq(initial.body, b"accepted")
  let first_entry = second.scan_after("dispatch", "").unwrap()
  assert_eq(first_entry.key, "one")
  assert_eq(first_entry.revision, 0L)
  assert_eq(first_entry.body, b"accepted")
  let second_entry = second.scan_after("dispatch", first_entry.key).unwrap()
  assert_eq(second_entry.key, "three")
  assert_eq(second_entry.body, b"later")
  guard second.scan_after("dispatch", second_entry.key) is Err(NotFound) else {
    fail("journal scan did not end at the namespace boundary")
  }
  assert_eq(
    first.compare_exchange("dispatch", "one", 0L, b"running").unwrap(),
    1L,
  )
  guard second.compare_exchange("dispatch", "one", 0L, b"stale")
    is Err(Collision) else {
    fail("stale journal revision was accepted")
  }
  guard first.insert("dispatch", "large", b"0123456789abcdefg")
    is Err(BodyTooLarge) else {
    fail("oversized journal body was accepted")
  }
  first.close()
  guard first.read("dispatch", "one") is Err(DatabaseClosed) else {
    fail("closed journal connection remained readable")
  }
  second.close()
  let reopened = library.open_database(database_path, 16L).unwrap()
  let retained = reopened.read("dispatch", "one").unwrap()
  assert_eq(retained.revision, 1L)
  assert_eq(retained.body, b"running")
  reopened.close()
}

///|
test "native SQLite capacity reservations are atomic and restart safe" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = load_library(path).unwrap()
  let database_path = root + "/capacity-" + @env.now().to_string() + ".sqlite3"
  let first = library.open_database(database_path, 64L).unwrap()
  let second = library.open_database(database_path, 64L).unwrap()
  assert_true(
    first.reserve_capacity("publication", "one", 600L, 1L, 1024L, 2L).unwrap(),
  )
  assert_false(
    second.reserve_capacity("publication", "one", 600L, 1L, 1024L, 2L).unwrap(),
  )
  guard second.reserve_capacity("publication", "one", 601L, 1L, 1024L, 2L)
    is Err(Collision) else {
    fail("mismatched repeated capacity reservation was accepted")
  }
  guard second.reserve_capacity("publication", "two", 600L, 1L, 1024L, 2L)
    is Err(CapacityExceeded) else {
    fail("concurrent capacity limit was not enforced")
  }
  let usage = second.capacity_usage("publication").unwrap()
  assert_eq(usage.reserved_bytes, 600L)
  assert_eq(usage.reserved_objects, 1L)
  first.close()
  second.close()
  let reopened = library.open_database(database_path, 64L).unwrap()
  let retained = reopened.capacity_usage("publication").unwrap()
  assert_eq(retained.reserved_bytes, 600L)
  assert_eq(retained.reserved_objects, 1L)
  assert_true(
    reopened.release_capacity("publication", "one", 600L, 1L).unwrap(),
  )
  assert_false(
    reopened.release_capacity("publication", "one", 600L, 1L).unwrap(),
  )
  let released = reopened.capacity_usage("publication").unwrap()
  assert_eq(released.reserved_bytes, 0L)
  assert_eq(released.reserved_objects, 0L)
  reopened.close()
}
