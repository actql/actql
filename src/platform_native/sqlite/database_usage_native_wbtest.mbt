///|
test "capacity lookup keeps zero distinct from absent and never reserves" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/usage-lookup.sqlite3", 64L)
    .unwrap()
  assert_true(database.read_capacity("原", "zero") is Err(NotFound))
  assert_true(
    database.reserve_capacity("原", "zero", 0L, 0L, 64L, 2L).unwrap(),
  )
  assert_true(
    database.reserve_capacity("原", "holding", 8L, 1L, 64L, 2L).unwrap(),
  )
  let zero = database.read_capacity("原", "zero").unwrap()
  assert_eq(zero.reserved_bytes, 0L)
  assert_eq(zero.reserved_objects, 0L)
  let original = database.read_capacity("原", "holding").unwrap()
  assert_eq(original.reserved_bytes, 8L)
  assert_eq(original.reserved_objects, 1L)
  assert_true(database.read_capacity("other", "holding") is Err(NotFound))
  assert_true(database.read_capacity("原", "absent") is Err(NotFound))
  assert_true(database.read_capacity("", "holding") is Err(InvalidName))
  assert_true(
    database.read_capacity("原", "x".repeat(513)) is Err(InvalidName),
  )
  let totals = database.database_usage().unwrap()
  assert_eq(totals.reservation_count, 2L)
  assert_eq(totals.record_count, 0L)
  assert_eq(totals.body_bytes, 0L)
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  database.close_checked().unwrap()
  assert_true(database.read_capacity("原", "holding") is Err(DatabaseClosed))
  assert_true(database.database_usage() is Err(DatabaseClosed))
}

///|
test "database usage observes all physical namespaces and byte lengths without copying bodies" {
  let (library, _, root) = existing_database_fixture()
  let path = root + "/usage-physical.sqlite3"
  let database = library.open_database(path, 64L).unwrap()
  database.insert("a", "same", b"\xe9\x9b\xaa\x00\n").unwrap() |> ignore
  database.insert("b", "same", b"abc").unwrap() |> ignore
  database.insert("b", "empty", b"").unwrap() |> ignore
  database.reserve_capacity("a", "one", 4L, 1L, 64L, 2L).unwrap() |> ignore
  database.reserve_capacity("b", "one", 7L, 2L, 64L, 2L).unwrap() |> ignore
  let bounded = library.open_existing_database(path, 1L).unwrap()
  assert_true(bounded.read("a", "same") is Err(Physical(_)))
  let totals = bounded.database_usage().unwrap()
  assert_eq(totals.record_count, 3L)
  assert_eq(totals.body_bytes, 8L)
  assert_eq(totals.reservation_count, 2L)
  assert_eq(bounded.capacity_usage("a").unwrap().reserved_bytes, 4L)
  bounded.close_checked().unwrap()
  database.close_checked().unwrap()
}

///|
#borrow(database)
extern "C" fn usage_test_lose_commit_reply(
  database : Database,
  count : Int,
) -> Unit = "actql_native_sqlite_test_fail_commit_reply"

///|
test "private usage is not durable and lost commit is reconciled by original lookup only" {
  let (library, _, root) = existing_database_fixture()
  let path = root + "/usage-transaction.sqlite3"
  let database = library.open_database(path, 64L).unwrap()
  let observer = library.open_existing_database(path, 64L).unwrap()
  database.begin_immediate().unwrap()
  database
  .reserve_capacity_in_transaction("原", "attempt", 8L, 1L, 64L, 2L)
  .unwrap()
  |> ignore
  database.insert("原", "row", b"private").unwrap() |> ignore
  let private = database.database_usage().unwrap()
  assert_eq(private.record_count, 1L)
  assert_eq(private.body_bytes, 7L)
  assert_eq(private.reservation_count, 1L)
  assert_eq(
    database.read_capacity("原", "attempt").unwrap().reserved_bytes,
    8L,
  )
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  let saved = observer.database_usage().unwrap()
  assert_eq(saved.record_count, 0L)
  assert_eq(saved.reservation_count, 0L)
  assert_true(observer.read_capacity("原", "attempt") is Err(NotFound))
  database.rollback().unwrap()
  assert_eq(database.database_usage().unwrap().record_count, 0L)
  assert_true(database.read_capacity("原", "attempt") is Err(NotFound))
  database.begin_immediate().unwrap()
  database
  .reserve_capacity_in_transaction("原", "attempt", 8L, 1L, 64L, 2L)
  .unwrap()
  |> ignore
  database.insert("原", "row", b"saved").unwrap() |> ignore
  usage_test_lose_commit_reply(database, 1)
  assert_true(database.commit() is Err(BodyTooLarge))
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  let committed = database.database_usage().unwrap()
  assert_eq(committed.record_count, 1L)
  assert_eq(committed.body_bytes, 5L)
  assert_eq(committed.reservation_count, 1L)
  assert_eq(
    database.read_capacity("原", "attempt").unwrap().reserved_bytes,
    8L,
  )
  assert_eq(observer.database_usage().unwrap().record_count, 1L)
  assert_eq(observer.read("原", "row").unwrap().body, b"saved")
  observer.close_checked().unwrap()
  database.close_checked().unwrap()
}

///|
test "metadata query failure is neither missing reservation nor empty database" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/usage-query-failure.sqlite3", 64L)
    .unwrap()
  database.insert("原", "row", b"unchanged").unwrap() |> ignore
  assert_true(test_drop_capacity(database))
  assert_true(database.read_capacity("原", "missing") is Err(Physical(_)))
  assert_true(database.database_usage() is Err(Physical(_)))
  assert_eq(database.read("原", "row").unwrap().body, b"unchanged")
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  database.close_checked().unwrap()
}
