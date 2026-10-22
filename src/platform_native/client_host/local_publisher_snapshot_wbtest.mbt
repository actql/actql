///|
// Actual SystemSQLite and retained Host/Store originals. This diagnoses the
// Journal callback boundary; it is not a selected business supplier fixture.
test "publisher current joins only the original publication transaction" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-current-snapshot", true,
  )
  let publisher = host
    .bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "publisher-current-snapshot.run.json",
      store,
    )
    .unwrap()
  let journal = host.journal
  let before = journal.lookup(request, publisher.current()).unwrap()
  let calls = Ref(0)
  let current = () => {
    calls.val += 1
    publisher.current_in_mode(true)
  }
  // An ordinary predicate owns one snapshot and returns it normally.
  assert_true(journal.publisher_current_snapshot(current))
  assert_eq(calls.val, 1)
  assert_false(journal.transaction_active)
  // The commit callback's explicit same-Journal fence joins that snapshot.
  let joined = journal
    .transaction(() => {
      journal.publication_read_locked = true
      let valid = journal.publisher_current_snapshot(current)
      journal.publication_read_locked = false
      Ok(valid)
    })
    .unwrap()
  assert_true(joined)
  assert_eq(calls.val, 2)
  // An unrelated active transaction is not permission to join or mutate.
  let unrelated = journal
    .transaction(() => Ok(journal.publisher_current_snapshot(current)))
    .unwrap()
  assert_false(unrelated)
  assert_eq(calls.val, 2)
  // A stale read flag alone cannot stand in for actual transaction custody.
  journal.publication_read_locked = true
  assert_false(journal.publisher_current_snapshot(current))
  journal.publication_read_locked = false
  assert_eq(calls.val, 2)
  guard before is Retained(before) &&
    journal.lookup(request, publisher.current()) is Ok(Retained(after)) else {
    abort("same retained Run")
  }
  assert_eq(before.revision, after.revision)
  host.close().unwrap()
  assert_false(journal.publisher_current_snapshot(current))
  assert_true(store.close().unwrap())
}

///|
// The operation flag supplies no permission or resource ACK. Current Host,
// Store location and target Run still come from the actual legacy fixture.
test "publisher pure command predicates reuse the operation without replacing CAS transaction custody" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-operation-snapshot", true,
  )
  let publisher = host
    .bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "publisher-operation-snapshot.run.json",
      store,
    )
    .unwrap()
  let journal = host.journal
  let calls : Array[String] = []
  let reads = journal_test_read_access(host.database, calls)
  let current = () => publisher.current_in_mode(true, reads=Some(reads))
  journal.operation_active = true
  for _ in 0..<4 {
    assert_true(journal.publisher_current_snapshot(current, reads=Some(reads)))
  }
  assert_false(
    calls.any(value => {
      value == "begin" || value == "commit" || value == "rollback"
    }),
  )
  // Active command metadata is not evidence that a CAS owns a transaction.
  assert_false(publisher.current_in_owned_transaction())
  journal.publication_read_locked = true
  assert_false(journal.publisher_current_snapshot(current, reads=Some(reads)))
  journal.publication_read_locked = false
  journal
  .transaction_with_reads(
    () => {
      assert_true(publisher.current_in_owned_transaction())
      assert_false(
        journal.publisher_current_snapshot(current, reads=Some(reads)),
      )
      Ok(())
    },
    reads=Some(reads),
  )
  .unwrap()
  assert_eq(calls.filter(value => value == "begin").length(), 1)
  assert_eq(calls.filter(value => value == "commit").length(), 1)
  journal.operation_active = false
  journal.invalidate_operation_record()
  calls.clear()
  assert_true(journal.publisher_current_snapshot(current, reads=Some(reads)))
  assert_eq(calls.filter(value => value == "begin").length(), 1)
  assert_eq(calls.filter(value => value == "commit").length(), 1)
  journal.fenced = true
  journal.operation_active = true
  assert_false(journal.publisher_current_snapshot(current, reads=Some(reads)))
  journal.operation_active = false
  journal.invalidate_operation_record()
  host.close().unwrap()
  assert_true(store.close().unwrap())
}
