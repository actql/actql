///|
test "original capacity release refuses without caller transaction and changes nothing" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/release-no-tx.sqlite3", 64L)
    .unwrap()
  assert_true(
    database.reserve_capacity("original", "one", 8L, 1L, 64L, 2L).unwrap(),
  )
  assert_true(
    database.release_capacity_in_transaction("original", "one", 8L, 1L)
    is Err(Physical(_)),
  )
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_eq(database.capacity_usage("original").unwrap().reserved_bytes, 8L)
  assert_true(database.release_capacity("original", "one", 8L, 1L).unwrap())
  assert_false(database.release_capacity("original", "one", 8L, 1L).unwrap())
  database.close_checked().unwrap()
}

///|
test "capacity release and original row CAS share commit or rollback without implicit completion" {
  let (library, _, root) = existing_database_fixture()
  let path = root + "/release-with-row.sqlite3"
  let database = library.open_database(path, 64L).unwrap()
  let observer = library.open_existing_database(path, 64L).unwrap()
  assert_true(
    database.reserve_capacity("原", "holding", 8L, 1L, 64L, 2L).unwrap(),
  )
  assert_eq(database.insert("原", "row", b"before").unwrap(), 0L)
  database.begin_immediate().unwrap()
  assert_true(
    database.release_capacity_in_transaction("原", "holding", 8L, 1L).unwrap(),
  )
  assert_eq(
    database.compare_exchange("原", "row", 0L, b"private").unwrap(),
    1L,
  )
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  assert_eq(observer.capacity_usage("原").unwrap().reserved_bytes, 8L)
  assert_eq(observer.read("原", "row").unwrap().body, b"before")
  database.rollback().unwrap()
  assert_eq(database.capacity_usage("原").unwrap().reserved_bytes, 8L)
  assert_eq(database.read("原", "row").unwrap().body, b"before")
  database.begin_immediate().unwrap()
  assert_true(
    database.release_capacity_in_transaction("原", "holding", 8L, 1L).unwrap(),
  )
  assert_eq(
    database.compare_exchange("原", "row", 0L, b"committed").unwrap(),
    1L,
  )
  database.commit().unwrap()
  assert_eq(observer.capacity_usage("原").unwrap().reserved_bytes, 0L)
  assert_eq(observer.read("原", "row").unwrap().body, b"committed")
  observer.close_checked().unwrap()
  database.close_checked().unwrap()
}

///|
test "capacity release collision and absent reservation never finish caller transaction" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/release-collision.sqlite3", 64L)
    .unwrap()
  assert_true(
    database.reserve_capacity("original", "one", 8L, 1L, 64L, 2L).unwrap(),
  )
  database.begin_immediate().unwrap()
  assert_true(
    database.release_capacity_in_transaction("original", "one", 9L, 1L)
    is Err(Collision),
  )
  assert_eq(database.capacity_usage("original").unwrap().reserved_bytes, 8L)
  assert_false(
    database
    .release_capacity_in_transaction("original", "missing", 8L, 1L)
    .unwrap(),
  )
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  assert_true(
    database
    .reserve_capacity_in_transaction("original", "two", 3L, 1L, 64L, 2L)
    .unwrap(),
  )
  database.rollback().unwrap()
  let usage = database.capacity_usage("original").unwrap()
  assert_eq(usage.reserved_bytes, 8L)
  assert_eq(usage.reserved_objects, 1L)
  database.close_checked().unwrap()
}
