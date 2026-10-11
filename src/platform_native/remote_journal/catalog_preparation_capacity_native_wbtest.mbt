///|
/// Model byte envelopes exercise original custody only. No production layout
/// is installed and Native compilation is not execution of these SQLite cases.
test "Catalog preparation uses its original token rather than spare Ledger capacity" {
  let (_, _, journal) = initial_catalog_fixture("preparation-coverage")
  let request = test_request("preparation-coverage")
  let ledger = initial_catalog_test_ledger()
  let envelope = initial_catalog_test_envelope()
  let (_, _, retained) = journal
    .accept_with_initial_catalog_use(request, ledger, envelope)
    .unwrap()
  let custody = retained.unwrap()
  let before = @resources.ledger_usage(ledger)
  for _ in 0..<2 {
    journal.read_catalog_preparation_capacity(custody, envelope).unwrap()
  }
  assert_true(
    journal.read_catalog_preparation_capacity(custody, {
      record_bytes: 8192L,
      control_bytes: 8193L,
      workspace_bytes: 8192L,
    })
    is Err(Capacity(@resources.InvalidCharge)),
  )
  assert_true(
    journal.read_catalog_preparation_capacity(custody, {
      record_bytes: 8192L,
      control_bytes: 8192L,
      workspace_bytes: 8193L,
    })
    is Err(Capacity(@resources.InvalidCharge)),
  )
  assert_true(
    journal.read_catalog_preparation_capacity(custody, {
      record_bytes: 9223372036854775807L,
      control_bytes: 1L,
      workspace_bytes: 1L,
    })
    is Err(Capacity(@resources.InvalidCharge)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  journal.require_initial_catalog_use(request, 0L).unwrap() |> ignore
  assert_true(journal.close())
}

///|
test "Catalog preparation of a lost claim reply never recreates initial eligibility" {
  let (_, _, journal) = initial_catalog_fixture("preparation-claim-loss")
  let request = test_request("preparation-claim-loss")
  let ledger = initial_catalog_test_ledger()
  let envelope = initial_catalog_test_envelope()
  let (_, _, retained) = journal
    .accept_with_initial_catalog_use(request, ledger, envelope)
    .unwrap()
  let custody = retained.unwrap()
  let before = @resources.ledger_usage(ledger)
  test_fail_cancel_commit_reply(journal.database, 1)
  assert_true(journal.claim_funded_initial_catalog_use(custody) is Err(_))
  let original = journal.require_initial_catalog_use(request, 1L).unwrap()
  journal.read_catalog_preparation_capacity(custody, envelope).unwrap()
  assert_true(
    journal.read_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  assert_true(
    journal.claim_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  let after = journal.require_initial_catalog_use(request, 1L).unwrap()
  assert_eq(after.body, original.body)
  assert_eq(after.revision, original.revision)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(initial_catalog_use_custody_pending(custody))
  assert_true(journal.close())
}

///|
test "Catalog preparation rejects foreign replaced and missing original custody" {
  let (_, _, journal) = initial_catalog_fixture("preparation-original")
  let (_, _, foreign) = initial_catalog_fixture("preparation-foreign")
  let request = test_request("preparation-original")
  let ledger = initial_catalog_test_ledger()
  let envelope = initial_catalog_test_envelope()
  let (_, _, retained) = journal
    .accept_with_initial_catalog_use(request, ledger, envelope)
    .unwrap()
  let custody = retained.unwrap()
  let before = @resources.ledger_usage(ledger)
  foreign.accept(request).unwrap() |> ignore
  assert_true(
    foreign.read_catalog_preparation_capacity(custody, envelope)
    is Err(Journal(StateCollision)),
  )
  let cid = @remote.dispatch_request_identity(request)
  let original = journal.require_initial_catalog_use(request, 0L).unwrap()
  journal.database
  .compare_exchange(
    "site_initial_catalog_use",
    cid,
    0L,
    @utf8.encode("foreign body"),
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.read_catalog_preparation_capacity(custody, envelope)
    is Err(Journal(StateCollision)),
  )
  let replaced = journal.database.read("site_initial_catalog_use", cid).unwrap()
  journal.database
  .remove_exact(
    "site_initial_catalog_use",
    cid,
    replaced.revision,
    replaced.body,
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.read_catalog_preparation_capacity(custody, envelope)
    is Err(Journal(Physical(@sqlite.NotFound))),
  )
  assert_true(original.body.length() > 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(initial_catalog_use_custody_pending(custody))
  assert_true(journal.close())
  assert_true(foreign.close())
}
