///|
fn key_capacity_previous(bytes : Int64, objects : Int64) -> NativeCapacityUsage {
  { reserved_bytes: bytes, reserved_objects: objects, }
}

///|
test "key-scoped capacity keeps two scopes and unequal three-batch bodies independent" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/key-grow-scopes.sqlite3", 128L)
    .unwrap()
  let lengths = [5L, 13L, 7L]
  for scope in ["run-A:batch", "run-B:batch"] {
    let mut previous = key_capacity_previous(0L, 0L)
    for i, bytes in lengths {
      database.begin_immediate().unwrap()
      database
      .grow_key_capacity_in_transaction(
        "lookup-pages", scope, previous, bytes, 1L, 25L, 3L,
      )
      .unwrap()
      database.commit().unwrap()
      previous = key_capacity_previous(
        previous.reserved_bytes + bytes,
        i.to_int64() + 1L,
      )
      let observed = database.read_capacity("lookup-pages", scope).unwrap()
      assert_eq(observed.reserved_bytes, previous.reserved_bytes)
      assert_eq(observed.reserved_objects, previous.reserved_objects)
    }
  }
  let total = database.capacity_usage("lookup-pages").unwrap()
  assert_eq(total.reserved_bytes, 50L)
  assert_eq(total.reserved_objects, 6L)
  // The old namespace-limited primitive must still reject beside that history.
  assert_true(
    database.reserve_capacity("lookup-pages", "other", 1L, 1L, 25L, 3L)
    is Err(CapacityExceeded),
  )
  assert_eq(
    database.read_capacity("lookup-pages", "run-A:batch").unwrap().reserved_bytes,
    25L,
  )
  assert_eq(
    database.read_capacity("lookup-pages", "run-B:batch").unwrap().reserved_objects,
    3L,
  )
  database.close_checked().unwrap()
}

///|
test "key-scoped capacity exact bounds one-short and overflow preserve original counters" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/key-grow-bounds.sqlite3", 128L)
    .unwrap()
  database.begin_immediate().unwrap()
  let zero = key_capacity_previous(0L, 0L)
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope", "short-bytes", zero, 9L, 1L, 8L, 1L,
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope", "short-objects", zero, 9L, 2L, 9L, 1L,
    )
    is Err(CapacityExceeded),
  )
  assert_true(database.read_capacity("scope", "short-bytes") is Err(NotFound))
  assert_true(database.read_capacity("scope", "short-objects") is Err(NotFound))
  database
  .grow_key_capacity_in_transaction("scope", "exact", zero, 9L, 2L, 9L, 2L)
  .unwrap()
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope",
      "exact",
      key_capacity_previous(9L, 2L),
      1L,
      1L,
      9L,
      3L,
    )
    is Err(CapacityExceeded),
  )
  database
  .grow_key_capacity_in_transaction(
    "scope", "overflow", zero, 9223372036854775806L, 1L, 9223372036854775807L, 3L,
  )
  .unwrap()
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope",
      "overflow",
      key_capacity_previous(9223372036854775806L, 1L),
      2L,
      1L,
      9223372036854775807L,
      3L,
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope",
      "negative",
      key_capacity_previous(-1L, 0L),
      1L,
      1L,
      9L,
      2L,
    )
    is Err(InvalidLimit),
  )
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope", "zero-delta", zero, 0L, 1L, 9L, 2L,
    )
    is Err(InvalidLimit),
  )
  database.commit().unwrap()
  assert_eq(
    database.read_capacity("scope", "exact").unwrap().reserved_bytes,
    9L,
  )
  assert_eq(
    database.read_capacity("scope", "overflow").unwrap().reserved_bytes,
    9223372036854775806L,
  )
  database.close_checked().unwrap()
}

///|
test "key-scoped capacity CAS refuses stale missing and replayed originals without reconstruction" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/key-grow-original.sqlite3", 128L)
    .unwrap()
  database.begin_immediate().unwrap()
  database
  .grow_key_capacity_in_transaction(
    "scope",
    "original",
    key_capacity_previous(0L, 0L),
    5L,
    1L,
    20L,
    3L,
  )
  .unwrap()
  // Equal first-entry replay is not idempotent ACK, even with the same body size.
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope",
      "original",
      key_capacity_previous(0L, 0L),
      5L,
      1L,
      20L,
      3L,
    )
    is Err(Collision),
  )
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope",
      "original",
      key_capacity_previous(4L, 1L),
      7L,
      1L,
      20L,
      3L,
    )
    is Err(Collision),
  )
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope",
      "missing",
      key_capacity_previous(5L, 1L),
      7L,
      1L,
      20L,
      3L,
    )
    is Err(Collision),
  )
  assert_true(database.read_capacity("scope", "missing") is Err(NotFound))
  assert_eq(
    database.read_capacity("scope", "original").unwrap().reserved_bytes,
    5L,
  )
  database
  .grow_key_capacity_in_transaction(
    "scope",
    "original",
    key_capacity_previous(5L, 1L),
    7L,
    1L,
    20L,
    3L,
  )
  .unwrap()
  database.commit().unwrap()
  assert_eq(
    database.read_capacity("scope", "original").unwrap().reserved_bytes,
    12L,
  )
  database.close_checked().unwrap()
}

///|
test "key-scoped capacity requires original transaction and shares row rollback and commit" {
  let (library, _, root) = existing_database_fixture()
  let path = root + "/key-grow-transaction.sqlite3"
  let database = library.open_database(path, 128L).unwrap()
  let observer = library.open_existing_database(path, 128L).unwrap()
  let zero = key_capacity_previous(0L, 0L)
  assert_true(
    database.grow_key_capacity_in_transaction(
      "scope", "one", zero, 5L, 1L, 20L, 3L,
    )
    is Err(Physical(_)),
  )
  assert_true(database.read_capacity("scope", "one") is Err(NotFound))
  database.begin_immediate().unwrap()
  database
  .grow_key_capacity_in_transaction("scope", "one", zero, 5L, 1L, 20L, 3L)
  .unwrap()
  database.insert("entries", "one", b"first").unwrap() |> ignore
  database.commit().unwrap()
  database.begin_immediate().unwrap()
  database
  .grow_key_capacity_in_transaction(
    "scope",
    "one",
    key_capacity_previous(5L, 1L),
    13L,
    1L,
    20L,
    3L,
  )
  .unwrap()
  // A later business-row failure leaves the caller's whole transaction pending.
  assert_true(database.insert("entries", "one", b"collision") is Err(Collision))
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  assert_eq(observer.read_capacity("scope", "one").unwrap().reserved_bytes, 5L)
  database.rollback().unwrap()
  assert_eq(database.read_capacity("scope", "one").unwrap().reserved_bytes, 5L)
  assert_eq(database.read("entries", "one").unwrap().body, b"first")
  database.begin_immediate().unwrap()
  database
  .grow_key_capacity_in_transaction(
    "scope",
    "one",
    key_capacity_previous(5L, 1L),
    13L,
    1L,
    20L,
    3L,
  )
  .unwrap()
  database.insert("entries", "two", b"second-longer").unwrap() |> ignore
  database.commit().unwrap()
  assert_eq(observer.read_capacity("scope", "one").unwrap().reserved_bytes, 18L)
  assert_eq(observer.read("entries", "two").unwrap().body, b"second-longer")
  observer.close_checked().unwrap()
  database.close_checked().unwrap()
}
