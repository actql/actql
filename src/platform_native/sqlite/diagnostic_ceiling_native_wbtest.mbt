///|
test "Native diagnostic omission is fixed and preserves Physical classification" {
  assert_eq(decode_diagnostic(b""), "SQLite diagnostic detail omitted")
  assert_eq(decode_diagnostic(b"abc"), "abc")
  assert_eq(decode_diagnostic(b"\xc3\xa9"), "é")
  assert_true(Physical(decode_diagnostic(b"")) is Physical(_))
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(0)) is Err(InvalidLimit),
  )
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(-1)) is Err(InvalidLimit),
  )
}

///|
test "original legacy Library and Database have no finite diagnostic bound" {
  let (library, root, path) = existing_database_fixture()
  assert_true(library.diagnostic_ceiling() is None)
  let database = library
    .open_database_with_custody(
      path + "/legacy-diagnostic-bound.sqlite3",
      1024L,
    )
    .unwrap()
  assert_true(database.diagnostic_ceiling() is None)
  database.close_checked().unwrap()
  assert_true(database.diagnostic_ceiling() is None)
  library.close_checked().unwrap()
  assert_true(library.diagnostic_ceiling() is None)
  root.close().unwrap()
}

///|
test "original finite diagnostic selection survives other Library choice and close without reissue" {
  let (base, root, path) = existing_database_fixture()
  let selected_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = load_library(selected_path, diagnostic_ceiling=Some(128)).unwrap()
  let database = library
    .open_database_with_custody(
      path + "/original-diagnostic-bound.sqlite3",
      1024L,
    )
    .unwrap()
  let other = load_library(selected_path, diagnostic_ceiling=Some(1)).unwrap()
  assert_true(other.diagnostic_ceiling() is Some(1))
  assert_true(library.diagnostic_ceiling() is Some(128))
  assert_true(database.diagnostic_ceiling() is Some(128))
  other.close_checked().unwrap()
  database.close_checked().unwrap()
  assert_true(database.diagnostic_ceiling() is Some(128))
  library.close_checked().unwrap()
  assert_true(library.diagnostic_ceiling() is Some(128))
  base.close_checked().unwrap()
  root.close().unwrap()
}
