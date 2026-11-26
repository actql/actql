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
#borrow(database)
extern "C" fn state_test_fail_rollback(
  database : Database,
  count : Int,
) -> Unit = "actql_native_sqlite_test_fail_rollback"

///|
#borrow(database)
extern "C" fn state_test_fail_inspection(
  database : Database,
  count : Int,
) -> Unit = "actql_native_sqlite_test_fail_transaction_state"

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
  let primary = match database.transaction_step(Commit) {
    Err(failure) => failure
    Ok(_) => abort("expected COMMIT refusal")
  }
  state_test_fail_rollback(database, 1)
  let cleanup = match database.transaction_step(Rollback) {
    Err(failure) => failure
    Ok(_) => abort("expected rollback refusal")
  }
  assert_true(primary.step == Commit)
  assert_true(primary.reply == SqlNotIssued)
  assert_true(primary.issue is Physical(_))
  assert_true(cleanup.step == Rollback)
  assert_true(cleanup.reply == SqlNotIssued)
  assert_true(cleanup.issue is Physical(_))
  database.fence_transactions()
  assert_true(database.transaction_fenced())
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  assert_true(database.begin_immediate() is Err(Physical(_)))
  assert_true(database.commit() is Err(Physical(_)))
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
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
  let observed = database.observe_transaction_step(Commit)
  match observed.result {
    Err(failure) => {
      assert_true(failure.step == Commit)
      assert_true(failure.reply == SqlReplyLost)
      assert_true(failure.issue is Physical(_))
    }
    Ok(_) => abort("expected lost COMMIT reply")
  }
  assert_true(observed.state is Some(Ok(NoActiveSqliteTransaction)))
  database.fence_transactions()
  assert_true(database.transaction_fenced())
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.transaction_fenced())
  let child = match database.prepare_lookup_read().unwrap() {
    ReadyLookupRead(child) => child
    PendingLookupRead(_, _) => abort("expected original lookup")
  }
  let found = child.read_with_body_limit("original", "input", 1024L).unwrap()
  assert_eq(found.revision, 0L)
  assert_eq(found.body, b"saved\x00\xff")
  child.finish().unwrap()
  assert_true(database.transaction_fenced())
  assert_true(database.begin_immediate() is Err(Physical(_)))
  database.close_checked().unwrap()
  let retained = library
    .open_existing_database_with_custody(selected, 1024L)
    .unwrap()
  assert_eq(retained.read("original", "input").unwrap().revision, 0L)
  assert_eq(retained.read("original", "input").unwrap().body, b"saved\x00\xff")
  retained.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "confirmed COMMIT retains an unavailable state observation separately" {
  let (library, root, path) = existing_database_fixture()
  let selected = path + "/state-confirmed-observation-unavailable.sqlite3"
  let database = library.open_database_with_custody(selected, 1024L).unwrap()
  let began = database.observe_transaction_step(BeginImmediate)
  assert_true(began.result is Ok(_))
  assert_true(began.state is Some(Ok(ActiveSqliteTransaction)))
  database.insert("original", "input", b"saved").unwrap() |> ignore
  state_test_fail_inspection(database, 1)
  let committed = database.observe_transaction_step(Commit)
  assert_true(committed.result is Ok(_))
  assert_true(committed.state is Some(Err(Physical(_))))
  database.close_checked().unwrap()
  let retained = library
    .open_existing_database_with_custody(selected, 1024L)
    .unwrap()
  assert_eq(retained.read("original", "input").unwrap().body, b"saved")
  retained.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "failed state inspection cannot lend the original fenced connection" {
  let (library, root, path) = existing_database_fixture()
  let database = library
    .open_database_with_custody(path + "/state-observe.sqlite3", 1024L)
    .unwrap()
  database.fence_transactions()
  state_test_fail_inspection(database, 2)
  assert_true(database.transaction_state() is Err(Physical(_)))
  assert_true(database.prepare_lookup_read() is Err(Physical(_)))
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.transaction_fenced())
  assert_true(database.begin_deferred() is Err(Physical(_)))
  database.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "real SQLite BEGIN BUSY keeps its code and no candidate transaction" {
  let (library, root, path) = existing_database_fixture()
  let selected = path + "/state-busy.sqlite3"
  let owner = library.open_database_with_custody(selected, 1024L).unwrap()
  let contender = library
    .open_existing_database_with_custody(selected, 1024L)
    .unwrap()
  owner.begin_immediate().unwrap()
  owner.insert("original", "input", b"private").unwrap() |> ignore
  match contender.transaction_step(BeginImmediate) {
    Err(failure) => {
      assert_true(failure.step == BeginImmediate)
      assert_true(failure.reply == SqlRejected({ primary: 5, extended: 5, }))
      assert_true(failure.issue is Busy)
    }
    Ok(_) => abort("expected real SQLite writer contention")
  }
  assert_true(contender.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(contender.read("original", "input") is Err(NotFound))
  owner.rollback().unwrap()
  contender.begin_immediate().unwrap()
  contender.rollback().unwrap()
  contender.close_checked().unwrap()
  owner.close_checked().unwrap()
  root.close().unwrap()
}

///|
#borrow(database)
extern "C" fn state_test_stage_deferred_constraint(database : Database) -> Int = "actql_native_sqlite_test_stage_deferred_constraint"

///|
test "real deferred COMMIT rejection preserves the extended code across rollback" {
  let (library, root, path) = existing_database_fixture()
  let selected = path + "/state-constraint.sqlite3"
  let database = library.open_database_with_custody(selected, 1024L).unwrap()
  let observer = library
    .open_existing_database_with_custody(selected, 1024L)
    .unwrap()
  database.begin_immediate().unwrap()
  database.insert("original", "input", b"private").unwrap() |> ignore
  assert_eq(state_test_stage_deferred_constraint(database), 0)
  let primary = match database.transaction_step(Commit) {
    Err(failure) => failure
    Ok(_) => abort("expected a real deferred constraint refusal")
  }
  assert_true(database.transaction_state() is Ok(ActiveSqliteTransaction))
  assert_true(observer.read("original", "input") is Err(NotFound))
  database.transaction_step(Rollback).unwrap()
  assert_true(database.transaction_state() is Ok(NoActiveSqliteTransaction))
  assert_true(database.read("original", "input") is Err(NotFound))
  assert_true(primary.step == Commit)
  // SQLITE_CONSTRAINT and SQLITE_CONSTRAINT_FOREIGNKEY are distinct codes.
  assert_true(primary.reply == SqlRejected({ primary: 19, extended: 787, }))
  assert_true(primary.issue is Physical(_))
  observer.close_checked().unwrap()
  database.close_checked().unwrap()
  root.close().unwrap()
}
