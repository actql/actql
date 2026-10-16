///|
#borrow(database)
extern "C" fn state_test_fail_commit(database : Database, count : Int) -> Unit = "actql_native_sqlite_test_fail_commit"

///|
#borrow(database)
extern "C" fn state_test_lose_commit_reply(
  database : Database,
  count : Int,
) -> Unit = "actql_native_sqlite_test_fail_commit_reply"

///|
test "physical transaction state distinguishes ordinary begin commit rollback and closed handle" {
  let (library, root, path) = existing_database_fixture()
  let database = library
    .open_database_with_custody(path + "/state-normal.sqlite3", 1024L)
    .unwrap()
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  database.begin_immediate().unwrap()
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  database.insert("original", "rolled-back", b"uncommitted").unwrap() |> ignore
  database.rollback().unwrap()
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.read("original", "rolled-back") is Err(NotFound))
  database.begin_immediate().unwrap()
  database.insert("original", "committed", b"saved").unwrap() |> ignore
  database.commit().unwrap()
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  database.close_checked().unwrap()
  assert_true(database.transaction_state() is Err(DatabaseClosed))
  root.close().unwrap()
}

///|
test "commit refusal keeps private transaction rows distinct from durable original lookup" {
  let (library, root, path) = existing_database_fixture()
  let selected = path + "/state-before-commit.sqlite3"
  let database = library.open_database_with_custody(selected, 1024L).unwrap()
  database.begin_immediate().unwrap()
  database.insert("original", "input", b"private").unwrap() |> ignore
  state_test_fail_commit(database, 1)
  assert_true(database.commit() is Err(BodyTooLarge))
  database.fence_transactions()
  assert_true(database.transaction_fenced())
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  // Same-connection visibility does not prove COMMIT. The installed caller
  // must refuse durable lookup in this state, rather than reuse private rows.
  assert_eq(database.read("original", "input").unwrap().body, b"private")
  database.close_checked().unwrap()
  let retained = library
    .open_existing_database_with_custody(selected, 1024L)
    .unwrap()
  assert_true(retained.read("original", "input") is Err(NotFound))
  retained.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "lost commit reply preserves fence and autocommit without proving any Run outcome" {
  let (library, root, path) = existing_database_fixture()
  let selected = path + "/state-lost-reply.sqlite3"
  let database = library.open_database_with_custody(selected, 1024L).unwrap()
  database.begin_immediate().unwrap()
  database.insert("original", "input", b"saved\x00\xff").unwrap() |> ignore
  state_test_lose_commit_reply(database, 1)
  assert_true(database.commit() is Err(BodyTooLarge))
  database.fence_transactions()
  assert_true(database.transaction_fenced())
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.transaction_fenced())
  assert_eq(database.read("original", "input").unwrap().body, b"saved\x00\xff")
  database.close_checked().unwrap()
  let retained = library
    .open_existing_database_with_custody(selected, 1024L)
    .unwrap()
  assert_eq(retained.read("original", "input").unwrap().revision, 0L)
  assert_eq(retained.read("original", "input").unwrap().body, b"saved\x00\xff")
  retained.close_checked().unwrap()
  root.close().unwrap()
}
