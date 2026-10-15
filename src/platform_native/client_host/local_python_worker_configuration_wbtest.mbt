///|
fn python_worker_profile_host(path : String) -> NativeLocalHostConnection {
  begin_native_local_host_adoption(
    path,
    "host",
    path + "/configuration",
    "account.json",
    "local-cli",
    epoch_test_crypto(),
    configuration_files=[
      "environment.json", "compute.json", "retention.json", "retention-policy.json",
      "store.json", "result-policy.json", "profile.json", "read.json",
    ],
  )
  .unwrap()
  .open_journal(
    local_journal_test_library(),
    epoch_test_crypto(),
    100.0,
    8,
    8388608L,
  )
  .unwrap()
}

///|
test "Python worker fresh durable profile uses only its original child and reopens the same key" {
  let path = product_test_parent("python-worker-profile-fresh")
  let stage = begin_native_local_python_worker_configuration(
    path,
    "configuration",
    "2026-10-15T00:00:00.000Z",
    epoch_test_crypto(),
  ).unwrap()
  assert_eq(stage.originals.length(), 9)
  stage.stage_configuration().unwrap()
  let bytes = local_adoption_read(stage.root, "account.json", 65536L).unwrap()
  assert_true(stage.close())
  let host = python_worker_profile_host(path)
  let (arena, selection) = worker_provisioning_selection(1L)
  assert_true(
    host.issue_worker_provisioning(selection, "operator", "local")
    is Err(AuthorizationDenied),
  )
  assert_true(
    host.issue_worker_provisioning(selection, "local-cli", "remote")
    is Err(AuthorizationDenied),
  )
  let original = host
    .issue_worker_provisioning(selection, "local-cli", "local")
    .unwrap()
  let key = original.key
  let body = original.body
  assert_true(
    original.observe("local-cli", "local")
    is Ok(UnresolvedOriginal(_, _, Recorded)),
  )
  host.close().unwrap()
  let restored = restore_native_local_product_configuration(
    path,
    "configuration",
    epoch_test_crypto(),
  ).unwrap()
  assert_eq(
    local_adoption_read(restored.root, "account.json", 65536L).unwrap(),
    bytes,
  )
  assert_true(restored.close())
  let reopened = python_worker_profile_host(path)
  guard reopened.lookup_worker_provisioning(selection, "local-cli", "local")
    is Ok(UnresolvedOriginal(saved, original_body, Recorded)) else {
    fail("missing original Python worker operation")
  }
  assert_eq(saved, key)
  assert_eq(original_body, body)
  assert_true(
    reopened.issue_worker_provisioning(selection, "local-cli", "local")
    is Err(CustodyLost),
  )
  let (other_arena, other_selection) = worker_provisioning_selection(2L)
  assert_true(
    reopened.lookup_worker_provisioning(other_selection, "local-cli", "local")
    is Err(CustodyLost),
  )
  reopened.close().unwrap()
  arena.try_close().unwrap()
  other_arena.try_close().unwrap()
}

///|
test "Python worker fresh profile cannot supplement a retained run-only Account" {
  let path = product_test_parent("python-worker-profile-no-upgrade")
  let root = path + "/configuration"
  let old = @host.client_local_product_sdk_bootstrap_originals(
    root, "2026-10-15T00:00:00.000Z",
  ).unwrap()
  let stage = begin_native_local_product_configuration(
    path,
    "configuration",
    [("account.json", old.original.common.account)],
    epoch_test_crypto(),
  ).unwrap()
  stage.stage_configuration().unwrap()
  let before = local_adoption_read(stage.root, "account.json", 65536L).unwrap()
  assert_true(stage.close())
  assert_true(
    begin_native_local_python_worker_configuration(
      path,
      "configuration",
      "2026-10-15T00:00:00.000Z",
      epoch_test_crypto(),
    )
    is Err(SourceChanged),
  )
  let restored = restore_native_local_product_configuration(
    path,
    "configuration",
    epoch_test_crypto(),
  ).unwrap()
  assert_eq(restored.originals, [("account.json", before.0)])
  assert_eq(
    local_adoption_read(restored.root, "account.json", 65536L).unwrap(),
    before,
  )
  assert_true(restored.close())
  let host = begin_native_local_host_adoption(
      path,
      "host",
      root,
      "account.json",
      "local-cli",
      epoch_test_crypto(),
    )
    .unwrap()
    .open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  let (arena, selection) = worker_provisioning_selection(1L)
  assert_true(
    host.issue_worker_provisioning(selection, "local-cli", "local")
    is Err(AuthorizationDenied),
  )
  host.close().unwrap()
  arena.try_close().unwrap()
}

///|
test "Python worker saved profile refuses removed Account without regenerating it" {
  let path = product_test_parent("python-worker-profile-no-repair")
  let stage = begin_native_local_python_worker_configuration(
    path,
    "configuration",
    "2026-10-15T00:00:00.000Z",
    epoch_test_crypto(),
  ).unwrap()
  stage.stage_configuration().unwrap()
  let root = stage.root
  let generation = root.inspect_generation("account.json").unwrap().unwrap()
  assert_true(stage.close())
  let host = python_worker_profile_host(path)
  let (arena, selection) = worker_provisioning_selection(1L)
  let original = host
    .issue_worker_provisioning(selection, "local-cli", "local")
    .unwrap()
  root.reclaim_generation("account.json", generation).unwrap()
  assert_true(
    original.observe("local-cli", "local") is Err(Adoption(SourceChanged)),
  )
  host.close().unwrap()
  arena.try_close().unwrap()
  assert_true(
    restore_native_local_product_configuration(
      path,
      "configuration",
      epoch_test_crypto(),
    )
    is Err(CustodyLost),
  )
  assert_true(
    begin_native_local_python_worker_configuration(
      path,
      "configuration",
      "2026-10-16T00:00:00.000Z",
      epoch_test_crypto(),
    )
    is Err(SourceChanged),
  )
  assert_eq(root.inspect_generation("account.json").unwrap(), None)
}
