///|
/// Actual SQLite cases; selected Native execution requires the existing library
/// and isolated fixture root. Compile-only checking is not physical evidence.
test "funded Catalog read retains the original charge and claim consumes eligibility once" {
  let (_, _, journal) = initial_catalog_fixture("funded-read")
  let request = test_request("funded-read")
  let ledger = initial_catalog_test_ledger()
  let (_, _, retained) = journal
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  let custody = retained.unwrap()
  let before = @resources.ledger_usage(ledger)
  journal.read_funded_initial_catalog_use(custody).unwrap()
  journal.read_funded_initial_catalog_use(custody).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  let claim = journal.claim_funded_initial_catalog_use(custody).unwrap()
  assert_true(initial_catalog_use_claim_matches_journal(claim, journal))
  assert_eq(
    initial_catalog_use_claim_dispatch(claim),
    @remote.dispatch_request_identity(request),
  )
  assert_true(
    journal.read_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  assert_true(
    journal.claim_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(initial_catalog_use_custody_pending(custody))
  assert_true(journal.close())
}

///|
test "funded Catalog eligibility rechecks cancellation and current Site generation without consuming the stamp" {
  let (_, _, cancelled) = initial_catalog_fixture("funded-cancelled")
  let request = test_request("funded-cancelled")
  let ledger = initial_catalog_test_ledger()
  let (_, _, retained) = cancelled
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  let custody = retained.unwrap()
  cancelled.request_cancellation(request).unwrap() |> ignore
  assert_true(
    cancelled.read_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  assert_true(
    cancelled.claim_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  cancelled.require_initial_catalog_use(request, 0L).unwrap() |> ignore
  assert_true(cancelled.close())

  let (_, _, restarted) = initial_catalog_fixture("funded-generation")
  let request = test_request("funded-generation")
  let (_, _, retained) = restarted
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  let custody = retained.unwrap()
  let before = @resources.ledger_usage(ledger)
  let next_site = @site.create_site(
    "native-site",
    5,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  restarted.restart(next_site).unwrap() |> ignore
  assert_true(
    restarted.read_funded_initial_catalog_use(custody)
    is Err(Protocol(@remote.StaleSiteGeneration)),
  )
  assert_true(
    restarted.claim_funded_initial_catalog_use(custody)
    is Err(Protocol(@remote.StaleSiteGeneration)),
  )
  restarted.require_initial_catalog_use(request, 0L).unwrap() |> ignore
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(initial_catalog_use_custody_pending(custody))
  assert_true(restarted.close())
}

///|
test "funded Catalog custody rejects a different Journal with identical original dispatch bytes" {
  let (_, _, original) = initial_catalog_fixture("funded-original")
  let (_, _, foreign) = initial_catalog_fixture("funded-foreign")
  let request = test_request("funded-foreign")
  let ledger = initial_catalog_test_ledger()
  let (_, _, retained) = original
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  let custody = retained.unwrap()
  foreign.accept(request).unwrap() |> ignore
  assert_true(
    foreign.read_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  assert_true(
    foreign.claim_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  original.require_initial_catalog_use(request, 0L).unwrap() |> ignore
  assert_true(
    foreign.database.read(
      "site_initial_catalog_use",
      @remote.dispatch_request_identity(request),
    )
    is Err(@sqlite.NotFound),
  )
  assert_true(original.close())
  assert_true(foreign.close())
}

///|
test "unconfirmed Catalog acceptance stays pending until the same funded acceptance is confirmed" {
  let (_, _, journal) = initial_catalog_fixture("funded-unconfirmed")
  let request = test_request("funded-unconfirmed")
  let ledger = initial_catalog_test_ledger()
  let envelope = initial_catalog_test_envelope()
  test_fail_cancel_commit(journal.database, 1)
  guard journal.accept_with_initial_catalog_use(request, ledger, envelope)
    is Err(failure) else {
    fail("unconfirmed acceptance supplied eligibility")
  }
  let custody = failure.custody.unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    journal.read_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  assert_true(
    journal.claim_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  assert_true(journal.require(request) is Err(MissingDispatch))
  let (_, _, retry) = journal
    .accept_with_initial_catalog_use(
      request,
      ledger,
      envelope,
      original_custody=Some(custody),
    )
    .unwrap()
  assert_true(physical_equal(retry.unwrap(), custody))
  assert_eq(@resources.ledger_usage(ledger), before)
  journal.read_funded_initial_catalog_use(custody).unwrap()
  assert_true(journal.close())
}

///|
test "lost funded Catalog claim response and missing stamp cannot become another initial claim" {
  let (_, _, journal) = initial_catalog_fixture("funded-reply-loss")
  let request = test_request("funded-reply-loss")
  let ledger = initial_catalog_test_ledger()
  let (_, _, retained) = journal
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  let custody = retained.unwrap()
  let before = @resources.ledger_usage(ledger)
  test_fail_cancel_commit_reply(journal.database, 1)
  assert_true(journal.claim_funded_initial_catalog_use(custody) is Err(_))
  journal.require_initial_catalog_use(request, 1L).unwrap() |> ignore
  assert_true(
    journal.read_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  assert_true(
    journal.claim_funded_initial_catalog_use(custody) is Err(StateCollision),
  )
  let cid = @remote.dispatch_request_identity(request)
  let saved = journal.database.read("site_initial_catalog_use", cid).unwrap()
  journal.database.begin_immediate().unwrap()
  journal.database
  .remove_exact("site_initial_catalog_use", cid, saved.revision, saved.body)
  .unwrap()
  |> ignore
  journal.database.commit().unwrap()
  assert_true(
    journal.read_funded_initial_catalog_use(custody)
    is Err(Physical(@sqlite.NotFound)),
  )
  assert_true(
    journal.claim_funded_initial_catalog_use(custody)
    is Err(Physical(@sqlite.NotFound)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(initial_catalog_use_custody_pending(custody))
  assert_true(journal.close())
}
