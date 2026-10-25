///|
// Actual legacy SystemSQLite exercises the existing metadata/fence port. This
// does not construct an installed Read, Runtime original or cleanup receipt.
test "Journal metadata context preserves fences without opening a transaction" {
  let database = epoch_test_database("journal-metadata-context")
  let foreign = epoch_test_database("journal-metadata-context-foreign")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  assert_true(journal.check_transaction_context(reads=Some(reads)) is Ok(_))
  assert_eq(calls, ["fenced"])
  assert_false(journal.transaction_active)
  journal.transaction_active = true
  calls.clear()
  assert_true(
    journal.check_transaction_context(reads=Some(reads))
    is Err(Physical(@sqlite.Busy)),
  )
  assert_eq(calls, ["fenced"])
  journal.transaction_active = false
  journal.publication_read_locked = true
  calls.clear()
  assert_true(
    journal.check_transaction_context(reads=Some(reads))
    is Err(Physical(@sqlite.Busy)),
  )
  assert_eq(calls, ["fenced"])
  journal.publication_read_locked = false
  journal.fenced = true
  calls.clear()
  assert_true(
    journal.check_transaction_context(reads=Some(reads)) is Err(Fenced),
  )
  assert_eq(calls, [])
  journal.fenced = false
  let foreign_reads = journal_test_read_access(foreign, calls)
  calls.clear()
  assert_true(
    journal.check_transaction_context(reads=Some(foreign_reads)) is Err(Fenced),
  )
  assert_eq(calls, [])
  database.fence_transactions()
  calls.clear()
  assert_true(
    journal.check_transaction_context(reads=Some(reads)) is Err(Fenced),
  )
  assert_eq(calls, ["fenced"])
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
}
