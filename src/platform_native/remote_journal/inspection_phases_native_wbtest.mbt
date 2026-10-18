///|
test "native phased inspection retains the same copy through separate close acknowledgements" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/phased-inspection-read.sqlite3"
  let original = library.open_database(path, 1048576L).unwrap()
  original.insert("fixture", "original", b"exact value").unwrap() |> ignore
  let before = test_source_bytes(path)
  let captured = prepare_sqlite_source_inspection(path, 1048576L, 1048576L).unwrap()
  assert_true(captured.pending())
  assert_true(captured.validate_source() is Err(StateCollision))
  assert_true(captured.close_snapshot() is Err(CleanupPending))
  let copy = captured.open_database(library).unwrap().unwrap()
  assert_true(captured.open_database(library) is Err(StateCollision))
  assert_eq(copy.read("fixture", "original").unwrap().body, b"exact value")
  assert_true(copy.insert("fixture", "injected", b"forbidden") is Err(_))
  captured.validate_source().unwrap()
  captured.close_database().unwrap()
  assert_true(captured.pending())
  assert_eq(test_checked_close_count(copy), 1)
  assert_true(copy.read("fixture", "original") is Err(@sqlite.DatabaseClosed))
  assert_true(captured.open_database(library) is Err(Closed))
  assert_true(captured.validate_source() is Err(Closed))
  captured.close_snapshot().unwrap()
  assert_false(captured.pending())
  captured.retry().unwrap()
  assert_eq(test_checked_close_count(copy), 1)
  assert_eq(test_source_bytes(path), before)
  original.close_checked().unwrap()
}

///|
test "native phased inspection keeps scratch and the same DB after a failed physical close" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/phased-inspection-pending.sqlite3"
  let original = library.open_database(path, 1048576L).unwrap()
  let before = test_source_bytes(path)
  let captured = prepare_sqlite_source_inspection(path, 1048576L, 1048576L).unwrap()
  let copy = captured.open_database(library).unwrap().unwrap()
  let copy_path = captured.path.unwrap()
  let copy_before = test_source_bytes(copy_path)
  assert_true(copy_before[0].length() > 0)
  test_fail_inspection_close(copy, 1)
  assert_true(captured.close_database() is Err(Physical(@sqlite.Physical(_))))
  assert_eq(test_checked_close_count(copy), 1)
  assert_true(physical_equal(captured.database.unwrap(), copy))
  assert_true(captured.pending())
  assert_true(captured.close_snapshot() is Err(CleanupPending))
  assert_eq(test_source_bytes(copy_path), copy_before)
  assert_true(captured.open_database(library) is Err(Closed))
  captured.close_database().unwrap()
  assert_eq(test_checked_close_count(copy), 2)
  assert_true(captured.pending())
  captured.close_snapshot().unwrap()
  assert_false(captured.pending())
  assert_eq(test_source_bytes(copy_path), [b"", b"", b"", b""])
  captured.retry().unwrap()
  assert_eq(test_checked_close_count(copy), 2)
  assert_eq(test_source_bytes(path), before)
  original.close_checked().unwrap()
}

///|
test "native phased inspection can abandon the captured copy without opening a DB" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/phased-inspection-abandoned.sqlite3"
  let original = library.open_database(path, 1048576L).unwrap()
  let before = test_source_bytes(path)
  let captured = prepare_sqlite_source_inspection(path, 1048576L, 1048576L).unwrap()
  let copy_path = captured.path.unwrap()
  assert_true(test_source_bytes(copy_path)[0].length() > 0)
  captured.close_database().unwrap()
  assert_true(captured.pending())
  assert_true(captured.open_database(library) is Err(Closed))
  captured.close_snapshot().unwrap()
  assert_false(captured.pending())
  assert_eq(test_source_bytes(copy_path), [b"", b"", b"", b""])
  assert_eq(test_source_bytes(path), before)
  original.close_checked().unwrap()
}

///|
test "native phased inspection retains preparation failure without a replacement attempt" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/phased-inspection-capacity.sqlite3"
  let original = library.open_database(path, 1048576L).unwrap()
  let before = test_source_bytes(path)
  let captured = prepare_sqlite_source_inspection(path, 1048576L, 0L).unwrap()
  assert_true(captured.pending())
  assert_true(
    captured.open_database(library) is Err(Physical(@sqlite.CapacityExceeded)),
  )
  assert_true(captured.database is None)
  assert_true(captured.open_database(library) is Err(StateCollision))
  captured.close_database().unwrap()
  captured.close_snapshot().unwrap()
  assert_false(captured.pending())
  assert_eq(test_source_bytes(path), before)
  original.close_checked().unwrap()
}

///|
test "native phased inspection absence and invalid limits never initialize source custody" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/phased-inspection-absent.sqlite3"
  assert_true(
    prepare_sqlite_source_inspection(path, -1L, 1048576L)
    is Err(Physical(@sqlite.InvalidLimit)),
  )
  assert_true(
    prepare_sqlite_source_inspection(path, 1048576L, -1L)
    is Err(Physical(@sqlite.InvalidLimit)),
  )
  let captured = prepare_sqlite_source_inspection(path, 1048576L, 1048576L).unwrap()
  assert_true(captured.open_database(library).unwrap() is None)
  captured.validate_source().unwrap()
  captured.close_database().unwrap()
  captured.close_snapshot().unwrap()
  assert_false(captured.pending())
  assert_eq(test_source_bytes(path), [b"", b"", b"", b""])
}

///|
test "native phased inspection rechecks the original source after its separate read" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/phased-inspection-changed.sqlite3"
  let original = library.open_database(path, 1048576L).unwrap()
  original.insert("fixture", "first", b"original").unwrap() |> ignore
  let captured = prepare_sqlite_source_inspection(path, 1048576L, 1048576L).unwrap()
  let copy = captured.open_database(library).unwrap().unwrap()
  assert_eq(copy.read("fixture", "first").unwrap().body, b"original")
  original.insert("fixture", "changed", b"later").unwrap() |> ignore
  assert_true(captured.validate_source() is Err(Physical(_)))
  captured.close_database().unwrap()
  captured.close_snapshot().unwrap()
  assert_false(captured.pending())
  assert_true(original.read("fixture", "changed") is Ok(_))
  original.close_checked().unwrap()
}
