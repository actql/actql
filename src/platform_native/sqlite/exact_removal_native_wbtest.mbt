///|
test "exact SQLite retirement requires a transaction and all original row fields" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("actual SQLite fixture required")
  }
  let database = load_library(path)
    .unwrap()
    .open_database(
      root + "/exact-retirement-" + @env.now().to_string() + ".sqlite3",
      64L,
    )
    .unwrap()
  database.insert("original", "one", b"original bytes").unwrap() |> ignore
  database.insert("original", "other", b"preserved").unwrap() |> ignore
  database.insert("other", "one", b"preserved").unwrap() |> ignore
  assert_true(
    database.remove_exact("original", "one", 0L, b"original bytes") is Err(_),
  )
  database.begin_immediate().unwrap()
  assert_true(
    database.remove_exact("original", "one", 1L, b"original bytes")
    is Err(Collision),
  )
  assert_true(
    database.remove_exact("original", "one", 0L, b"replacement")
    is Err(Collision),
  )
  assert_true(
    database.remove_exact("other", "one", 0L, b"original bytes")
    is Err(Collision),
  )
  assert_true(
    database.remove_exact("original", "missing", 0L, b"original bytes")
    is Err(Collision),
  )
  database.remove_exact("original", "one", 0L, b"original bytes").unwrap()
  database.rollback().unwrap()
  assert_eq(database.read("original", "one").unwrap().body, b"original bytes")
  database.begin_immediate().unwrap()
  database.remove_exact("original", "one", 0L, b"original bytes").unwrap()
  database.commit().unwrap()
  assert_true(database.read("original", "one") is Err(NotFound))
  assert_eq(database.read("original", "other").unwrap().body, b"preserved")
  assert_eq(database.read("other", "one").unwrap().body, b"preserved")
  database.begin_immediate().unwrap()
  database.fence_transactions()
  assert_true(
    database.remove_exact("original", "other", 0L, b"preserved") is Err(_),
  )
  database.rollback().unwrap()
  database.close_checked().unwrap()
}
