///|
fn initial_catalog_fixture(
  suffix : String,
) -> (@sqlite.Library, String, Journal) raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("actual SQLite fixture required")
  }
  let library = @sqlite.load_library(library_path).unwrap()
  let path = root +
    "/initial-catalog-" +
    suffix +
    "-" +
    @env.now().to_string() +
    ".sqlite3"
  (
    library,
    path,
    open_journal(library, path, 262144L, test_control(test_site())).unwrap(),
  )
}

///|
fn initial_catalog_test_ledger(
  retention? : Int64 = 65536L,
) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: retention,
    execution_bytes: 65536L,
  }).unwrap()
}

///|
// Model envelope values exercise accounting, not a selected production cost
// coefficient or measured SQLite/allocator footprint.
fn initial_catalog_test_envelope() -> NativeInitialCatalogUseEnvelope {
  { record_bytes: 8192L, control_bytes: 8192L, workspace_bytes: 8192L, }
}

///|
test "initial Catalog acceptance funds and saves once while duplicates mint nothing" {
  let (_, _, journal) = initial_catalog_fixture("initial")
  let request = test_request("initial-catalog")
  let ledger = initial_catalog_test_ledger()
  let (_, _, custody) = journal
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  let custody = custody.unwrap()
  assert_true(initial_catalog_use_custody_pending(custody))
  assert_eq(
    initial_catalog_use_custody_dispatch(custody),
    @remote.dispatch_request_identity(request),
  )
  let before = initial_catalog_use_custody_usage(custody)
  assert_eq(before.reserved_retention_bytes, 16384L)
  assert_eq(before.reserved_execution_bytes, 8192L)
  let (kind, _, duplicate) = journal
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  assert_eq(kind, @remote.ExistingDispatch)
  assert_true(duplicate is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  let original = journal.require_initial_catalog_use(request, 0L).unwrap()
  assert_eq(
    original.body,
    @utf8.encode(@remote.dispatch_request_json(request).unwrap()),
  )
  assert_true(journal.close())
}

///|
test "legacy Catalog absence is not backfilled by duplicate accept" {
  let (_, _, journal) = initial_catalog_fixture("legacy")
  let request = test_request("legacy-catalog")
  journal.accept(request).unwrap() |> ignore
  let ledger = initial_catalog_test_ledger()
  let before = @resources.ledger_usage(ledger)
  let (_, _, custody) = journal
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  assert_true(custody is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    journal.claim_initial_catalog_use(request)
    is Err(Physical(@sqlite.NotFound)),
  )
  assert_true(journal.close())
}

///|
test "Catalog funding refusal precedes both durable initial records" {
  let (_, _, journal) = initial_catalog_fixture("capacity")
  let request = test_request("unfunded-catalog")
  let ledger = initial_catalog_test_ledger(retention=1L)
  guard journal.accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    is Err(failure) else {
    fail("unfunded initial acceptance succeeded")
  }
  assert_true(failure.issue is Capacity(@resources.RetentionLimit))
  assert_true(failure.custody is None)
  assert_true(journal.require(request) is Err(MissingDispatch))
  assert_true(
    journal.database.read(
      "site_initial_catalog_use",
      @remote.dispatch_request_identity(request),
    )
    is Err(@sqlite.NotFound),
  )
  assert_true(journal.close())
}

///|
test "Catalog initial save failure retains the funded responsibility" {
  let (_, _, journal) = initial_catalog_fixture("save-failure")
  let request = test_request("save-failure-catalog")
  let ledger = initial_catalog_test_ledger()
  test_fail_cancel_commit(journal.database, 1)
  guard journal.accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    is Err(failure) else {
    fail("unconfirmed initial acceptance succeeded")
  }
  assert_true(initial_catalog_use_custody_pending(failure.custody.unwrap()))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 16384L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 8192L)
  assert_true(journal.require(request) is Err(MissingDispatch))
  assert_true(
    journal.database.read(
      "site_initial_catalog_use",
      @remote.dispatch_request_identity(request),
    )
    is Err(@sqlite.NotFound),
  )
  assert_true(journal.close())
}

///|
test "lost Catalog claim commit reply never reissues an original claim after reopen" {
  let (library, path, journal) = initial_catalog_fixture("claim-reply")
  let request = test_request("claim-reply-catalog")
  let ledger = initial_catalog_test_ledger()
  journal
  .accept_with_initial_catalog_use(
    request,
    ledger,
    initial_catalog_test_envelope(),
  )
  .unwrap()
  |> ignore
  test_fail_cancel_commit_reply(journal.database, 1)
  assert_true(journal.claim_initial_catalog_use(request) is Err(_))
  assert_true(journal.close())
  let restored = open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  assert_true(restored.require_initial_catalog_use(request, 1L) is Ok(_))
  assert_true(
    restored.claim_initial_catalog_use(request) is Err(StateCollision),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 16384L)
  assert_true(restored.close())
}

///|
test "an empty replacement credential DB does not reset the Site original claim" {
  let (library, path, journal) = initial_catalog_fixture("replacement")
  let request = test_request("replacement-catalog")
  let ledger = initial_catalog_test_ledger()
  journal
  .accept_with_initial_catalog_use(
    request,
    ledger,
    initial_catalog_test_envelope(),
  )
  .unwrap()
  |> ignore
  let claim = journal.claim_initial_catalog_use(request).unwrap()
  assert_true(initial_catalog_use_claim_matches_journal(claim, journal))
  assert_eq(
    initial_catalog_use_claim_dispatch(claim),
    @remote.dispatch_request_identity(request),
  )
  // This is a Journal non-reset counterexample, not physical Resource/GET
  // continuity acceptance; that calling integration remains separate.
  let replacement = library
    .open_database(path + ".replacement", 65536L)
    .unwrap()
  assert_true(
    replacement.scan_after("credential_use", "") is Err(@sqlite.NotFound),
  )
  assert_true(journal.claim_initial_catalog_use(request) is Err(StateCollision))
  assert_true(journal.require_initial_catalog_use(request, 1L) is Ok(_))
  replacement.close()
  assert_true(journal.close())
}

///|
test "cancellation-first acceptance cannot mint initial Catalog eligibility" {
  let (_, _, journal) = initial_catalog_fixture("cancel-first")
  let request = test_request("cancel-first-catalog")
  journal.request_cancellation(request).unwrap() |> ignore
  let ledger = initial_catalog_test_ledger()
  let before = @resources.ledger_usage(ledger)
  let (_, _, custody) = journal
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  assert_true(custody is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(journal.claim_initial_catalog_use(request) is Err(_))
  assert_true(
    journal.database.read(
      "site_initial_catalog_use",
      @remote.dispatch_request_identity(request),
    )
    is Err(@sqlite.NotFound),
  )
  assert_true(journal.close())
}

///|
test "Site generation change refuses the original unclaimed Catalog marker" {
  let (_, _, journal) = initial_catalog_fixture("current-site")
  let request = test_request("current-site-catalog")
  let ledger = initial_catalog_test_ledger()
  journal
  .accept_with_initial_catalog_use(
    request,
    ledger,
    initial_catalog_test_envelope(),
  )
  .unwrap()
  |> ignore
  let original = journal.database
    .read(
      "site_initial_catalog_use",
      @remote.dispatch_request_identity(request),
    )
    .unwrap()
  let next_site = @site.create_site(
    "native-site",
    5,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  journal.restart(next_site).unwrap() |> ignore
  assert_true(
    journal.claim_initial_catalog_use(request)
    is Err(Protocol(@remote.StaleSiteGeneration)),
  )
  let after = journal.database
    .read(
      "site_initial_catalog_use",
      @remote.dispatch_request_identity(request),
    )
    .unwrap()
  assert_eq(after.revision, original.revision)
  assert_eq(after.body, original.body)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 16384L)
  assert_true(journal.close())
}

///|
fn initial_catalog_test_release(
  journal : Journal,
  request : @remote.DispatchRequest,
) -> Unit raise {
  journal.request_cancellation(request).unwrap() |> ignore
  let begin = @remote.prepare_begin_remote_release(
    journal.require(request).unwrap(),
  ).unwrap()
  journal.commit_transition(begin).unwrap() |> ignore
  let finish = @remote.prepare_confirm_remote_release(
    journal.require(request).unwrap(),
  ).unwrap()
  journal.commit_transition(finish).unwrap() |> ignore
  assert_true(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
}

///|
test "initial stamp cleanup waits for exact consumer release and returns its original charge once" {
  let (_, _, journal) = initial_catalog_fixture("cleanup")
  let request = test_request("stamp-cleanup")
  let ledger = initial_catalog_test_ledger()
  let custody = journal
  .accept_with_initial_catalog_use(
    request,
    ledger,
    initial_catalog_test_envelope(),
  )
  .unwrap().2.unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    journal.cleanup_initial_catalog_use(custody) is Err(Journal(StateCollision)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  initial_catalog_test_release(journal, request)
  let released = journal.require(request).unwrap()
  let cancellation = journal.cancellation_requested(request).unwrap()
  journal.cleanup_initial_catalog_use(custody).unwrap()
  assert_false(initial_catalog_use_custody_pending(custody))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  let after = @resources.ledger_usage(ledger)
  journal.cleanup_initial_catalog_use(custody).unwrap()
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    @remote.dispatch_record_revision(released),
  )
  assert_eq(journal.cancellation_requested(request).unwrap(), cancellation)
  assert_true(journal.claim_initial_catalog_use(request) is Err(_))
  let (_, _, replay) = journal
    .accept_with_initial_catalog_use(
      request,
      ledger,
      initial_catalog_test_envelope(),
    )
    .unwrap()
  assert_true(replay is None)
  assert_true(journal.close())
}

///|
test "lost exact cleanup commit reply retains the same nominal operation and reservation" {
  let (_, _, journal) = initial_catalog_fixture("cleanup-reply")
  let request = test_request("cleanup-reply")
  let ledger = initial_catalog_test_ledger()
  let custody = journal
  .accept_with_initial_catalog_use(
    request,
    ledger,
    initial_catalog_test_envelope(),
  )
  .unwrap().2.unwrap()
  initial_catalog_test_release(journal, request)
  let before = @resources.ledger_usage(ledger)
  test_fail_cancel_commit_reply(journal.database, 1)
  assert_true(journal.cleanup_initial_catalog_use(custody) is Err(_))
  assert_true(custody.cleanup_started)
  assert_false(custody.removal_confirmed)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    journal.database.read("site_initial_catalog_use", custody.dispatch_cid)
    is Err(@sqlite.NotFound),
  )
  journal.cleanup_initial_catalog_use(custody).unwrap()
  assert_false(initial_catalog_use_custody_pending(custody))
  assert_true(journal.close())
}

///|
test "missing initial stamp without its nominal cleanup cannot discharge the reservation" {
  let (_, _, journal) = initial_catalog_fixture("cleanup-missing")
  let request = test_request("cleanup-missing")
  let ledger = initial_catalog_test_ledger()
  let custody = journal
  .accept_with_initial_catalog_use(
    request,
    ledger,
    initial_catalog_test_envelope(),
  )
  .unwrap().2.unwrap()
  initial_catalog_test_release(journal, request)
  let before = @resources.ledger_usage(ledger)
  let saved = journal.require_initial_catalog_use(request, 0L).unwrap()
  // Inject control-row loss; this is not an Owner-issued cleanup proof.
  journal.database.begin_immediate().unwrap()
  journal.database
  .remove_exact(
    "site_initial_catalog_use",
    custody.dispatch_cid,
    0L,
    saved.body,
  )
  .unwrap()
  journal.database.commit().unwrap()
  assert_true(journal.cleanup_initial_catalog_use(custody) is Err(_))
  assert_false(custody.cleanup_started)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(initial_catalog_use_custody_pending(custody))
  assert_true(journal.close())
}

///|
test "a reopened Journal cannot adopt another nominal initial stamp cleanup" {
  let (library, path, journal) = initial_catalog_fixture("cleanup-foreign")
  let request = test_request("cleanup-foreign")
  let ledger = initial_catalog_test_ledger()
  let custody = journal
  .accept_with_initial_catalog_use(
    request,
    ledger,
    initial_catalog_test_envelope(),
  )
  .unwrap().2.unwrap()
  initial_catalog_test_release(journal, request)
  let other = open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    other.cleanup_initial_catalog_use(custody) is Err(Journal(StateCollision)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(other.close())
  journal.cleanup_initial_catalog_use(custody).unwrap()
  assert_true(journal.close())
}
