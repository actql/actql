///|
// Actual legacy SystemSQLite/explicit Crypto Journal operations. The private
// operation flag selects only typed-fact retention; it issues no permission,
// installed supplier, native Read claim or resource acknowledgement.
test "one selected Run revision and Policy original survive trusted read-only transactions" {
  let host = policy_host_fixture("public-operation-fact-reuse")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "one-target",
    "one-run",
    scope~,
  )
  host.journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  host
  .retain_publication_policy_originals(
    crypto, "operator", "cli", request, prepared, compiled, definition,
  )
  .unwrap()
  |> ignore
  let journal = host.journal
  journal.admitted_record = None
  journal.admitted_publications.clear()
  journal.operation_active = true
  let first = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  let wire = first.publication_policy_originals.unwrap()
  let policies = journal.publication_originals(wire).unwrap()
  assert_eq(journal.admitted_publications.length(), 1)
  let second = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  assert_true(physical_equal(first, second))
  assert_true(
    physical_equal(policies, journal.publication_originals(wire).unwrap()),
  )
  assert_eq(journal.admitted_publications.length(), 1)
  // These are the same typed originals across two actual transactions, not
  // newly admitted copies selected by a private helper/transaction frame.
  journal.operation_active = false
  journal.admitted_record = None
  journal.admitted_publications.clear()
  journal.operation_active = true
  let next = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  assert_false(physical_equal(first, next))
  assert_false(
    physical_equal(policies, journal.publication_originals(wire).unwrap()),
  )
  assert_eq(journal.admitted_publications.length(), 1)
  journal.operation_active = false
  journal.admitted_record = None
  journal.admitted_publications.clear()
  host.close().unwrap()
}

///|
test "operation retention refuses changed target bytes and preserves rollback and Unknown" {
  let host = policy_host_fixture("public-operation-target-change")
  let scope = host
    .authority_scope_cid("operator", "cli", epoch_test_crypto())
    .unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "changed-target",
    "changed-run",
    scope~,
  )
  host.journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let journal = host.journal
  journal.operation_active = true
  let first = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  let key = @host.client_request_scope_cid(request)
  let before = host.database.read("client_runs", key).unwrap()
  let changed = journal.transaction(() => {
    match
      host.database.compare_exchange(
        "client_runs",
        key,
        before.revision,
        b"changed target",
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    journal.retained(request)
  })
  assert_true(changed is Err(CustodyLost))
  let after = host.database.read("client_runs", key).unwrap()
  assert_eq(after.revision, before.revision)
  assert_eq(after.body, before.body)
  let restored = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  assert_true(physical_equal(first, restored))
  client_test_fail_commit_reply(host.database, 1)
  assert_true(
    journal.transaction(() => journal.retained(request))
    is Err(TransactionUnknown),
  )
  assert_true(journal.fenced && host.database.transaction_fenced())
  assert_true(journal.lookup(request, true) is Err(Fenced))
  journal.operation_active = false
  journal.admitted_record = None
  journal.admitted_publications.clear()
  host.close().unwrap()
}
