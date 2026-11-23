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

///|
test "fenced autocommit refuses self-owned capacity and ordinal mutations before lookup" {
  let (library, root, path) = existing_database_fixture()
  let selected = path + "/capacity-fenced-autocommit.sqlite3"
  let database = library.open_database_with_custody(selected, 64L).unwrap()
  let observer = library
    .open_existing_database_with_custody(selected, 64L)
    .unwrap()
  assert_true(
    database.reserve_capacity("original", "held", 8L, 1L, 64L, 2L).unwrap(),
  )
  assert_true(
    database.claim_ordinal_action("original", "first", 2L) is Ok(Fresh(1L)),
  )
  database.fence_transactions()
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))

  assert_true(
    database.reserve_capacity("original", "extra", 3L, 1L, 64L, 2L)
    is Err(Physical(_)),
  )
  assert_true(
    database.release_capacity("original", "held", 8L, 1L) is Err(Physical(_)),
  )
  assert_true(
    database.claim_ordinal_action("original", "second", 2L) is Err(Physical(_)),
  )
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.transaction_fenced())
  let holding = observer.read_capacity("original", "held").unwrap()
  assert_eq(holding.reserved_bytes, 8L)
  assert_eq(holding.reserved_objects, 1L)
  assert_true(observer.read_capacity("original", "extra") is Err(NotFound))
  assert_true(
    observer.lookup_claim_ordinal("original", "first") is Ok(Some(1L)),
  )
  assert_true(observer.lookup_claim_ordinal("original", "second") is Ok(None))
  observer.close_checked().unwrap()
  database.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "fenced caller transaction refuses capacity changes but retains original rollback" {
  let (library, root, path) = existing_database_fixture()
  let selected = path + "/capacity-fenced-active.sqlite3"
  let database = library.open_database_with_custody(selected, 64L).unwrap()
  assert_true(
    database.reserve_capacity("original", "held", 8L, 1L, 64L, 2L).unwrap(),
  )
  database.begin_immediate().unwrap()
  database.insert("original", "input", b"private").unwrap() |> ignore
  database.fence_transactions()

  assert_true(
    database.reserve_capacity_in_transaction(
      "original", "extra", 3L, 1L, 64L, 2L,
    )
    is Err(Physical(_)),
  )
  assert_true(
    database.release_capacity_in_transaction("original", "held", 8L, 1L)
    is Err(Physical(_)),
  )
  assert_true(
    database.grow_key_capacity_in_transaction(
      "original",
      "held",
      { reserved_bytes: 8L, reserved_objects: 1L, },
      3L,
      1L,
      64L,
      2L,
    )
    is Err(Physical(_)),
  )
  assert_true(
    database.claim_ordinal_action_in_transaction("original", "claim", 2L)
    is Err(Physical(_)),
  )
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
  assert_eq(
    database.read_capacity("original", "held").unwrap().reserved_bytes,
    8L,
  )
  assert_true(database.read_capacity("original", "extra") is Err(NotFound))
  assert_true(database.lookup_claim_ordinal("original", "claim") is Ok(None))
  assert_eq(database.read("original", "input").unwrap().body, b"private")

  database.rollback().unwrap()
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.transaction_fenced())
  let child = match database.prepare_lookup_read().unwrap() {
    ReadyLookupRead(child) => child
    PendingLookupRead(_, _) =>
      abort("expected the original reconciliation snapshot")
  }
  assert_true(
    child.read_with_body_limit("original", "input", 64L) is Err(NotFound),
  )
  assert_eq(child.read_capacity("original", "held").unwrap().reserved_bytes, 8L)
  assert_true(child.read_capacity("original", "extra") is Err(NotFound))
  child.finish().unwrap()
  database.close_checked().unwrap()
  root.close().unwrap()
}
