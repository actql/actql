///|
test "release observation rereads a separately committed cleanup without relaxing old reconstruction" {
  let (library, recovery, request, path, site) = cleanup_test_open(
    "separate-release-observation",
  )
  let (_, record) = recovery.accept(request).unwrap()
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
  recovery
  .commit_transition(
    @remote.prepare_begin_provisioning(record, capability).unwrap(),
  )
  .unwrap()
  recovery
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  recovery
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  let environment : ControlEnvironment = {
    sqlite_library: library,
    crypto_library: path => {
      @signature.load_library(path).map_err(_ => "fixture Crypto load failed")
    },
    journal_path: path,
    max_record_bytes: 262144L,
    site_key: "cleanup-test-site",
    site_generation: 4,
    runtime_bundle_cid: cleanup_test_cid(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    max_operations: 4,
    max_transfers: 4,
    max_bytes: 1048576L,
  }
  let before = fresh_journal(environment).unwrap()
  let cached = before.observation(request).unwrap()
  assert_eq(
    @remote.dispatch_record_state_codes(
      @journal.recovered_site_dispatch_record(cached),
    ),
    [3, 0, 0, 0, 0],
  )
  // These are real journal CAS transitions by a separate cleanup Owner.
  // This test covers observation freshness, not physical cleanup acceptance.
  recovery
  .commit_transition(@remote.prepare_begin_remote_release(record).unwrap())
  .unwrap()
  recovery
  .commit_transition(@remote.prepare_confirm_remote_release(record).unwrap())
  .unwrap()
  let revision = @remote.dispatch_record_revision(record)
  assert_true(recovery.close())
  assert_true(before.observation(request) is Err(@journal.Protocol(_)))
  assert_true(before.close())
  for _ in 0..<2 {
    let current = fresh_journal(environment).unwrap()
    let observation = current.observation(request).unwrap()
    let saved = @journal.recovered_site_dispatch_record(observation)
    assert_eq(@remote.dispatch_record_state_codes(saved), [3, 0, 2, 0, 0])
    assert_eq(@remote.dispatch_record_revision(saved), revision)
    assert_true(current.close())
  }
  let foreign = fresh_journal({ ..environment, site_generation: 5, })
  assert_true(foreign is None)
}
