///|
fn cleanup_test_cid(value : String) -> String {
  "sha256:" + value
}

///|
fn cleanup_test_open(
  name : String,
) -> (
  @sqlite.Library,
  @journal.Journal,
  @remote.DispatchRequest,
  String,
  @site.ExecutionSite,
) raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("SQLite library missing")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("SQLite root missing")
  }
  let library = @sqlite.load_library(path).unwrap()
  let runtime = cleanup_test_cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let site = @site.create_site(
    "cleanup-test-site", 4, runtime, 4, 4, 1048576L, 1048576L,
  ).unwrap()
  let control = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let database_path = root + "/" + name + ".sqlite3"
  let journal = @journal.open_journal(library, database_path, 262144L, control).unwrap()
  let request = @remote.prepare_dispatch_request(
    "cleanup-test-coordinator",
    cleanup_test_cid(
      "0000000000000000000000000000000000000000000000000000000000000000",
    ),
    "consumer",
    1,
    name,
    "cleanup-test-site",
    4,
    runtime,
    "local",
    "local/1",
    "strategy/1",
    cleanup_test_cid(
      "1111111111111111111111111111111111111111111111111111111111111111",
    ),
    cleanup_test_cid(
      "2222222222222222222222222222222222222222222222222222222222222222",
    ),
    cleanup_test_cid(
      "3333333333333333333333333333333333333333333333333333333333333333",
    ),
    cleanup_test_cid(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
    cleanup_test_cid(
      "4444444444444444444444444444444444444444444444444444444444444444",
    ),
  ).unwrap()
  (library, journal, request, database_path, site)
}

///|
/// These are persistence/claim boundary tests of the actual CLI helper.
/// They do not claim a public Run or substitute for physical Owner cleanup.
test "unstarted consumer cleanup retries failed begin and keeps released revision" {
  let (library, journal, request, path, _) = cleanup_test_open("begin-busy")
  ignore(journal.accept(request).unwrap())
  let cancelled = journal.request_cancellation(request).unwrap()
  assert_eq(@remote.dispatch_record_state_codes(cancelled), [5, 0, 0, 0, 0])
  let revision = @remote.dispatch_record_revision(cancelled)
  // A real competing writer prevents the original journal's release save.
  let blocker = library.open_database(path, 262144L).unwrap()
  blocker.begin_immediate().unwrap()
  assert_false(confirm_unstarted_consumer_cleanup(journal, request))
  assert_eq(
    @remote.dispatch_record_state_codes(journal.require(request).unwrap()),
    [5, 0, 0, 0, 0],
  )
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  blocker.rollback().unwrap()
  blocker.close_checked().unwrap()
  assert_true(confirm_unstarted_consumer_cleanup(journal, request))
  let released = journal.require(request).unwrap()
  assert_eq(@remote.dispatch_record_state_codes(released), [5, 0, 2, 0, 0])
  let released_revision = @remote.dispatch_record_revision(released)
  assert_true(confirm_unstarted_consumer_cleanup(journal, request))
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    released_revision,
  )
  assert_true(journal.close())
}

///|
test "unstarted consumer cleanup resumes releasing after save failure and reopen" {
  let (library, journal, request, path, site) = cleanup_test_open(
    "confirm-busy",
  )
  ignore(journal.accept(request).unwrap())
  let cancelled = journal.request_cancellation(request).unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_release(cancelled).unwrap())
  .unwrap()
  let before = journal.require(request).unwrap()
  assert_eq(@remote.dispatch_record_state_codes(before), [5, 0, 1, 0, 0])
  let revision = @remote.dispatch_record_revision(before)
  let blocker = library.open_database(path, 262144L).unwrap()
  blocker.begin_immediate().unwrap()
  assert_false(confirm_unstarted_consumer_cleanup(journal, request))
  assert_eq(
    @remote.dispatch_record_state_codes(journal.require(request).unwrap()),
    [5, 0, 1, 0, 0],
  )
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_true(journal.close())
  blocker.rollback().unwrap()
  blocker.close_checked().unwrap()
  let reopened = @journal.open_journal(
    library,
    path,
    262144L,
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
  ).unwrap()
  assert_true(confirm_unstarted_consumer_cleanup(reopened, request))
  let released = reopened.require(request).unwrap()
  assert_eq(@remote.dispatch_record_state_codes(released), [5, 0, 2, 0, 0])
  assert_eq(@remote.dispatch_record_revision(released), revision + 1)
  assert_true(confirm_unstarted_consumer_cleanup(reopened, request))
  assert_eq(
    @remote.dispatch_record_revision(reopened.require(request).unwrap()),
    revision + 1,
  )
  assert_true(reopened.close())
}

///|
test "unstarted consumer cleanup refuses a cancelled exclusive start claimant" {
  let (_, journal, request, _, site) = cleanup_test_open("claimed-cancel")
  let (_, record) = journal.accept(request).unwrap()
  let capability = @remote.register_remote_execution_capability(
    site,
    cleanup_test_cid(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    "local",
    "local/1",
    "strategy/1",
    cleanup_test_cid(
      "4444444444444444444444444444444444444444444444444444444444444444",
    ),
  ).unwrap()
  assert_eq(
    journal
    .claim_start(
      @remote.prepare_begin_provisioning(record, capability).unwrap(),
      "original-claimant",
    )
    .unwrap(),
    @journal.Won,
  )
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  ignore(journal.request_cancellation(request).unwrap())
  journal
  .commit_transition(
    @remote.prepare_confirm_execution_cancelled(record).unwrap(),
  )
  .unwrap()
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_eq(journal.start_claimant(request).unwrap(), Some("original-claimant"))
  assert_false(confirm_unstarted_consumer_cleanup(journal, request))
  assert_eq(
    @remote.dispatch_record_state_codes(journal.require(request).unwrap()),
    [5, 0, 0, 0, 0],
  )
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_true(journal.close())
}
