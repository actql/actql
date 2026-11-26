///|
test "caller claim refuses autocommit without consuming the original ordinal" {
  let (_, db, _) = original_claim_lookup_database("caller-claim-autocommit")
  assert_true(
    db.claim_ordinal_action_in_transaction("grant", "use", 3L)
    is Err(Physical("claim requires an active unfenced caller transaction")),
  )
  assert_eq(db.lookup_claim_ordinal("grant", "use").unwrap(), None)
  assert_true(db.claim_ordinal_action("grant", "use", 3L) is Ok(Fresh(1L)))
  db.close_checked().unwrap()
}

///|
#borrow(database)
extern "C" fn suppress_fresh_insert(database : Database) -> Int = "actql_native_sqlite_test_suppress_fresh_insert"

///|
test "a suppressed fresh record requires rollback of the earlier caller write" {
  let (library, database, path) = original_claim_lookup_database(
    "suppressed-fresh-record",
  )
  database.insert("control", "run", b"original").unwrap() |> ignore
  assert_eq(suppress_fresh_insert(database), 0)
  database.begin_immediate().unwrap()
  assert_eq(
    database.compare_exchange("control", "run", 0L, b"tentative").unwrap(),
    1L,
  )
  assert_true(
    database.insert("control", "suppressed", b"witness")
    is Err(Physical("journal insert did not affect exactly one row")),
  )
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  database.rollback().unwrap()
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  database.close_checked().unwrap()
  let restored = library.open_existing_database(path, 64L).unwrap()
  let run = restored.read("control", "run").unwrap()
  assert_eq(run.body, b"original")
  assert_eq(run.revision, 0L)
  assert_true(restored.read("control", "suppressed") is Err(NotFound))
  restored.close_checked().unwrap()
}

///|
test "suppressed capacity and claim inserts cannot acknowledge new ownership" {
  let (library, database, path) = original_claim_lookup_database(
    "suppressed-fresh-ownership",
  )
  assert_true(
    database.reserve_capacity("files", "first", 8L, 1L, 16L, 2L).unwrap(),
  )
  assert_true(
    database.claim_ordinal_action("uses", "first", 2L) is Ok(Fresh(1L)),
  )
  assert_eq(suppress_fresh_insert(database), 0)
  assert_true(
    database.reserve_capacity("files", "suppressed", 8L, 1L, 16L, 2L)
    is Err(Physical("capacity insert did not affect exactly one row")),
  )
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(
    database.claim_ordinal_action("uses", "suppressed", 2L)
    is Err(Physical("claim insert did not affect exactly one row")),
  )
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_false(database.transaction_fenced())
  database.close_checked().unwrap()
  let restored = library.open_existing_database(path, 64L).unwrap()
  assert_true(restored.read_capacity("files", "suppressed") is Err(NotFound))
  assert_eq(restored.capacity_usage("files").unwrap().reserved_bytes, 8L)
  assert_true(restored.lookup_claim_ordinal("uses", "suppressed") is Ok(None))
  assert_true(restored.lookup_claim_ordinal("uses", "first") is Ok(Some(1L)))
  assert_true(
    restored.claim_ordinal_action("uses", "next", 2L) is Ok(Fresh(2L)),
  )
  restored.close_checked().unwrap()
}

///|
test "caller claim rolls back with original use and control CAS without an early commit" {
  let (library, db, path) = original_claim_lookup_database(
    "caller-claim-rollback",
  )
  db.insert("control", "run", b"original").unwrap() |> ignore
  let reader = library.open_existing_database(path, 64L).unwrap()
  db.begin_immediate().unwrap()
  assert_true(
    db.claim_ordinal_action_in_transaction("grant", "use", 3L) is Ok(Fresh(1L)),
  )
  db.insert("use", "original", b"original use").unwrap() |> ignore
  db.compare_exchange("control", "run", 0L, b"pending").unwrap() |> ignore
  assert_eq(reader.lookup_claim_ordinal("grant", "use").unwrap(), None)
  assert_eq(reader.read("control", "run").unwrap().body, b"original")
  assert_true(reader.read("use", "original") is Err(NotFound))
  db.rollback().unwrap()
  assert_eq(db.lookup_claim_ordinal("grant", "use").unwrap(), None)
  assert_true(db.read("use", "original") is Err(NotFound))
  assert_eq(db.read("control", "run").unwrap().revision, 0L)
  assert_true(db.claim_ordinal_action("grant", "use", 3L) is Ok(Fresh(1L)))
  reader.close_checked().unwrap()
  db.close_checked().unwrap()
}

///|
test "caller claim commits once and retained observation leaves caller transaction open" {
  let (library, db, path) = original_claim_lookup_database(
    "caller-claim-commit",
  )
  db.begin_immediate().unwrap()
  assert_true(
    db.claim_ordinal_action_in_transaction("grant", "use", 2L) is Ok(Fresh(1L)),
  )
  db.insert("uses", "use", b"same original").unwrap() |> ignore
  db.commit().unwrap()
  db.close_checked().unwrap()
  let restored = library.open_existing_database(path, 64L).unwrap()
  restored.begin_immediate().unwrap()
  assert_true(
    restored.claim_ordinal_action_in_transaction("grant", "use", 2L)
    is Ok(Retained(1L)),
  )
  restored.compare_exchange("uses", "use", 0L, b"tentative").unwrap() |> ignore
  restored.rollback().unwrap()
  assert_eq(restored.read("uses", "use").unwrap().body, b"same original")
  assert_true(
    restored.claim_ordinal_action("grant", "other-use", 2L) is Ok(Fresh(2L)),
  )
  restored.close_checked().unwrap()
}

///|
test "caller claim capacity refusal neither commits nor rolls back the owning transaction" {
  let (_, db, _) = original_claim_lookup_database("caller-claim-capacity")
  db.claim_ordinal("grant", "first", 1L).unwrap() |> ignore
  db.begin_immediate().unwrap()
  db.insert("control", "pending", b"owner pending").unwrap() |> ignore
  assert_true(
    db.claim_ordinal_action_in_transaction("grant", "second", 1L)
    is Err(CapacityExceeded),
  )
  assert_eq(db.read("control", "pending").unwrap().body, b"owner pending")
  db.rollback().unwrap()
  assert_true(db.read("control", "pending") is Err(NotFound))
  assert_eq(db.lookup_claim_ordinal("grant", "second").unwrap(), None)
  db.close_checked().unwrap()
}

///|
test "caller claim refuses fenced handles and retains original generic name and limit bounds" {
  let (_, db, _) = original_claim_lookup_database("caller-claim-fenced")
  assert_true(
    db.claim_ordinal_action_in_transaction("", "use", 1L) is Err(InvalidName),
  )
  assert_true(
    db.claim_ordinal_action_in_transaction("grant", "use", 0L)
    is Err(InvalidLimit),
  )
  db.begin_immediate().unwrap()
  db.fence_transactions()
  assert_true(
    db.claim_ordinal_action_in_transaction("grant", "use", 1L)
    is Err(Physical("claim requires an active unfenced caller transaction")),
  )
  db.rollback().unwrap()
  assert_eq(db.lookup_claim_ordinal("grant", "use").unwrap(), None)
  db.close_checked().unwrap()
  assert_true(
    db.claim_ordinal_action_in_transaction("grant", "use", 1L)
    is Err(DatabaseClosed),
  )
}
