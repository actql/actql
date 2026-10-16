///|
#borrow(database)
extern "C" fn lookup_test_fault(database : Database, kind : Int) -> Unit = "actql_native_sqlite_test_lookup_fault"

///|
#borrow(database)
extern "C" fn lookup_test_count(database : Database, kind : Int) -> Int = "actql_native_sqlite_test_lookup_count"

///|
fn lookup_ready(database : Database) -> NativeLookupRead {
  match database.prepare_lookup_read().unwrap() {
    ReadyLookupRead(child) => child
    PendingLookupRead(_, _) => abort("expected an acknowledged read start")
  }
}

///|
test "fenced lost COMMIT lends one pinned original payload generation and reservation snapshot" {
  let (library, _, root) = existing_database_fixture()
  let path = root + "/lookup-committed.sqlite3"
  let database = library.open_database(path, 64L).unwrap()
  database.begin_immediate().unwrap()
  database.insert("原", "😀", b"saved\x00\xff").unwrap() |> ignore
  database
  .reserve_capacity_in_transaction("原", "held", 8L, 1L, 64L, 2L)
  .unwrap()
  |> ignore
  usage_test_lose_commit_reply(database, 1)
  assert_true(database.commit() is Err(BodyTooLarge))
  database.fence_transactions()
  let snapshot = lookup_ready(database)
  assert_true(database.owns_lookup_read(snapshot))
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
  assert_true(database.close_checked() is Err(_))
  assert_true(database.rollback() is Err(Physical(_)))
  assert_true(database.commit() is Err(Physical(_)))
  assert_true(database.begin_immediate() is Err(Physical(_)))
  assert_true(database.insert("原", "new", b"forbidden") is Err(Physical(_)))
  assert_true(
    database.reserve_capacity("原", "new", 1L, 1L, 64L, 2L) is Err(Physical(_)),
  )
  let writer = library.open_existing_database(path, 64L).unwrap()
  writer.begin_immediate().unwrap()
  writer.compare_exchange("原", "😀", 0L, b"later").unwrap() |> ignore
  writer.commit().unwrap()
  let original = snapshot.read_with_body_limit("原", "😀", 64L).unwrap()
  assert_eq(original.revision, 0L)
  assert_eq(original.body, b"saved\x00\xff")
  assert_eq(snapshot.read_header("原", "😀").unwrap().body_bytes, 7L)
  assert_eq(
    snapshot.scan_after_with_body_limit("原", "", 64L).unwrap().key,
    "😀",
  )
  assert_eq(snapshot.read_capacity("原", "held").unwrap().reserved_bytes, 8L)
  assert_eq(snapshot.capacity_usage("原").unwrap().reserved_objects, 1L)
  let totals = snapshot.database_usage().unwrap()
  assert_eq(totals.record_count, 1L)
  assert_eq(totals.body_bytes, 7L)
  assert_eq(totals.reservation_count, 1L)
  snapshot.finish().unwrap()
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.transaction_fenced())
  // Even low-level SQL mutation stays physically query-only after retirement.
  assert_true(
    database.compare_exchange("原", "😀", 1L, b"forbidden") is Err(_),
  )
  assert_true(snapshot.require_current() is Err(Physical(_)))
  assert_eq(lookup_test_count(database, 1), 1)
  assert_eq(lookup_test_count(database, 2), 1)
  assert_eq(writer.read("原", "😀").unwrap().body, b"later")
  writer.close_checked().unwrap()
  database.close_checked().unwrap()
}

///|
test "prior active uncertain write refuses read acquisition without rollback or adoption" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/lookup-active.sqlite3", 64L)
    .unwrap()
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
  database.begin_immediate().unwrap()
  database.insert("原", "row", b"private").unwrap() |> ignore
  database.fence_transactions()
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  assert_eq(database.read("原", "row").unwrap().body, b"private")
  assert_eq(lookup_test_count(database, 1), 0)
  assert_eq(lookup_test_count(database, 2), 0)
  database.close_checked().unwrap()
}

///|
test "lost read start retains same pending child and cleanup never repeats BEGIN" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/lookup-start-loss.sqlite3", 64L)
    .unwrap()
  database.insert("原", "row", b"saved").unwrap() |> ignore
  database.fence_transactions()
  lookup_test_fault(database, 1)
  let child = match database.prepare_lookup_read().unwrap() {
    PendingLookupRead(child, _) => child
    ReadyLookupRead(_) => abort("lost start cannot publish readiness")
  }
  assert_true(child.read_header("原", "row") is Err(Physical(_)))
  assert_true(child.finish() is Err(Physical(_)))
  assert_true(database.close_checked() is Err(_))
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
  child.retry_cleanup().unwrap()
  child.retry_cleanup().unwrap()
  assert_true(child.finish() is Err(Physical(_)))
  assert_eq(lookup_test_count(database, 1), 1)
  assert_eq(lookup_test_count(database, 2), 1)
  assert_true(database.transaction_fenced())
  database.close_checked().unwrap()
}

///|
test "lost read stop is drained on original attempt and cannot complete earlier observation" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/lookup-stop-loss.sqlite3", 64L)
    .unwrap()
  database.fence_transactions()
  let child = lookup_ready(database)
  assert_eq(child.database_usage().unwrap().record_count, 0L)
  lookup_test_fault(database, 2)
  assert_true(child.finish() is Err(Physical(_)))
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.close_checked() is Err(_))
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
  child.retry_cleanup().unwrap()
  assert_eq(lookup_test_count(database, 2), 1)
  assert_true(child.finish() is Err(Physical(_)))
  assert_true(database.transaction_fenced())
  database.close_checked().unwrap()
}

///|
test "known pre-stop refusal retains child capacity and only cleanup can retry original stop" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/lookup-stop-refused.sqlite3", 64L)
    .unwrap()
  database.fence_transactions()
  let child = lookup_ready(database)
  lookup_test_fault(database, 3)
  assert_true(child.finish() is Err(Physical(_)))
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  assert_true(database.close_checked() is Err(_))
  assert_true(child.database_usage() is Err(Physical(_)))
  child.retry_cleanup().unwrap()
  assert_eq(lookup_test_count(database, 2), 1)
  assert_true(child.finish() is Err(Physical(_)))
  database.close_checked().unwrap()
}

///|
test "foreign and retired snapshot aliases cannot authorize another connection or generation" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/lookup-alias.sqlite3", 64L)
    .unwrap()
  let foreign = library
    .open_database(root + "/lookup-foreign.sqlite3", 64L)
    .unwrap()
  database.fence_transactions()
  foreign.fence_transactions()
  let old = lookup_ready(database)
  assert_false(foreign.owns_lookup_read(old))
  old.finish().unwrap()
  let fresh = lookup_ready(database)
  assert_true(old.read_header("原", "missing") is Err(Physical(_)))
  old.retry_cleanup().unwrap()
  fresh.require_current().unwrap()
  fresh.finish().unwrap()
  assert_eq(lookup_test_count(database, 1), 2)
  assert_eq(lookup_test_count(database, 2), 2)
  foreign.close_checked().unwrap()
  database.close_checked().unwrap()
}

///|
test "current loss invalidates observation while same read child retains physical cleanup" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/lookup-current.sqlite3", 64L)
    .unwrap()
  database.fence_transactions()
  let child = lookup_ready(database)
  lookup_test_fault(database, 4)
  assert_true(child.database_usage() is Err(Physical(_)))
  assert_true(child.finish() is Err(Physical(_)))
  assert_true(database.close_checked() is Err(_))
  child.retry_cleanup().unwrap()
  assert_eq(lookup_test_count(database, 2), 1)
  lookup_test_fault(database, 5)
  assert_true(child.finish() is Err(Physical(_)))
  assert_true(database.transaction_fenced())
  database.close_checked().unwrap()
}

///|
test "partial construction before BEGIN retains original child until no-active cleanup ACK" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/lookup-partial.sqlite3", 64L)
    .unwrap()
  database.fence_transactions()
  lookup_test_fault(database, 6)
  let child = match database.prepare_lookup_read().unwrap() {
    PendingLookupRead(child, _) => child
    ReadyLookupRead(_) =>
      abort("partial construction is not a started snapshot")
  }
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.close_checked() is Err(_))
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
  assert_true(child.finish() is Err(Physical(_)))
  child.retry_cleanup().unwrap()
  assert_eq(lookup_test_count(database, 1), 0)
  assert_eq(lookup_test_count(database, 2), 0)
  assert_true(database.transaction_fenced())
  database.close_checked().unwrap()
}

///|
test "stop ACK without final current cannot publish completion or regain readiness on retry" {
  let (library, _, root) = existing_database_fixture()
  let database = library
    .open_database(root + "/lookup-postcurrent.sqlite3", 64L)
    .unwrap()
  database.fence_transactions()
  let child = lookup_ready(database)
  lookup_test_fault(database, 7)
  assert_true(child.finish() is Err(Physical(_)))
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  child.retry_cleanup().unwrap()
  lookup_test_fault(database, 5)
  assert_true(child.finish() is Err(Physical(_)))
  assert_eq(lookup_test_count(database, 1), 1)
  assert_eq(lookup_test_count(database, 2), 1)
  assert_true(database.transaction_fenced())
  database.close_checked().unwrap()
}
