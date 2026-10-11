///|
// Native physical cases are defined independently of CLI output. The current
// artifact is not yet available, so compile checks are not execution evidence.
test "Native original publication Policy packet survives journal reopen without work" {
  let name = "run-policy-original-reopen"
  let database = epoch_test_database(name)
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "policy-request", "policy-run",
  )
  let bound = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let old_body = run_record_body(bound).unwrap()
  assert_false(
    (@utf8.decode(old_body) catch { _ => fail("invalid original row") }).contains(
      "publication_policy_originals",
    ),
  )
  assert_eq(
    run_record_body(read_run_record({ body: old_body, revision: 0L, }).unwrap()).unwrap(),
    old_body,
  )
  let root = @host.prepared_client_publication_data_policy_cid(prepared).unwrap()
  assert_true(
    journal.lookup_publication_policy_original(request, root, () => true)
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  let stored = journal
    .retain_publication_policy_originals(
      request,
      prepared,
      compiled,
      definition,
      () => true,
    )
    .unwrap()
  assert_eq(stored.revision, 1L)
  assert_false(stored.dispatch_reserved)
  assert_false(stored.physical_start_claimed)
  let original = stored.publication_policy_originals.unwrap()
  let first = journal
    .lookup_publication_policy_original(request, root, () => true)
    .unwrap()
  assert_eq(
    journal
    .retain_publication_policy_originals(
      request,
      prepared,
      compiled,
      definition,
      () => true,
    )
    .unwrap().revision,
    1L,
  )
  database.close_checked().unwrap()
  let reopened = epoch_test_database(name)
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("original Run missing")
  }
  assert_eq(record.publication_policy_originals, Some(original))
  assert_false(record.dispatch_reserved)
  assert_false(record.physical_start_claimed)
  let restored = journal
    .lookup_publication_policy_original(request, root, () => true)
    .unwrap()
  assert_eq(
    @publication.captured_effect_dependency_body_json(restored),
    @publication.captured_effect_dependency_body_json(first),
  )
  assert_true(
    journal.lookup_publication_policy_original(
      request,
      "sha256:" + "f".repeat(64),
      () => true,
    )
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  assert_true(
    journal.lookup_publication_policy_original(request, root, () => false)
    is Err(AuthorizationDenied),
  )
  reopened.close_checked().unwrap()
}

///|
test "Native Policy original custody rechecks authority and never repairs a started Run" {
  for denied_at in 1..<=3 {
    let database = epoch_test_database(
      "run-policy-denied-" + denied_at.to_string(),
    )
    initialize_native_client_run_journal(database).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let (request, prepared, compiled, definition) = journal_test_run(
      "policy-request", "policy-run",
    )
    let bound = journal
      .bind_run(request, prepared, compiled, definition, true)
      .unwrap()
    let mut calls = 0
    assert_true(
      journal.retain_publication_policy_originals(
        request,
        prepared,
        compiled,
        definition,
        () => {
          calls += 1
          calls != denied_at
        },
      )
      is Err(AuthorizationDenied),
    )
    assert_eq(calls, denied_at)
    guard journal.lookup(request, true) is Ok(Retained(record)) else {
      fail("original Run missing")
    }
    assert_eq(record.revision, bound.revision)
    assert_eq(record.publication_policy_originals, None)
    journal.reserve_dispatch(request, true).unwrap() |> ignore
    assert_true(journal.claim_physical_start(request, true).unwrap())
    assert_true(
      journal.retain_publication_policy_originals(
        request,
        prepared,
        compiled,
        definition,
        () => true,
      )
      is Err(Fenced),
    )
    guard journal.lookup(request, true) is Ok(Retained(record)) else {
      fail("started Run missing")
    }
    assert_eq(record.publication_policy_originals, None)
    database.close_checked().unwrap()
  }
}

///|
test "Native Policy original custody refuses foreign Run and malformed packet" {
  let database = epoch_test_database("run-policy-foreign")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "policy-request", "policy-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let (_, _, _, foreign) = journal_test_run("policy-request", "another-run")
  assert_true(
    journal.retain_publication_policy_originals(
      request,
      prepared,
      compiled,
      foreign,
      () => true,
    )
    is Err(ForeignRun),
  )
  for
    invalid in [
      "null",
      "{}",
      "{\"bodies\":[],\"root_policy_cid\":\"sha256:" + "a".repeat(64) + "\"}",
    ] {
    assert_true(read_run_policy_originals(invalid) is Err(CustodyLost))
  }
  let retained = journal
    .retain_publication_policy_originals(
      request,
      prepared,
      compiled,
      definition,
      () => true,
    )
    .unwrap()
  let bad = { ..retained, publication_policy_originals: Some("{}"), }
  assert_true(
    read_run_record({
      body: run_record_body(bad).unwrap(),
      revision: retained.revision,
    })
    is Err(CustodyLost),
  )
  database.close_checked().unwrap()
}
