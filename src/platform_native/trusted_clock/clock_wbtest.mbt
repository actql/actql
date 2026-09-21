///|
test "native trusted clock rejects rollback across reopen" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  let library = @sqlite.load_library(sqlite_path).unwrap()
  let path = sqlite_root + "/trusted-clock.sqlite"
  let first = open(library, path, "remote-transfer-clock-v1", "host").unwrap()
  assert_true(first.observe_value(1000L) is Ok(1000L))
  assert_true(first.observe_value(1001L) is Ok(1001L))
  assert_true(first.observe_value(1000L) is Err(Rollback))
  assert_true(first.close())
  let reopened = open(library, path, "remote-transfer-clock-v1", "host").unwrap()
  assert_true(reopened.observe_value(999L) is Err(Rollback))
  assert_true(reopened.observe_value(1002L) is Ok(1002L))
  assert_true(reopened.close())
}
