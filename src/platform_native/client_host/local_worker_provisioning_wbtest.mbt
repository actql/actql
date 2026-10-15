///|
fn worker_provisioning_test_host(
  name : String,
  allow : Bool,
) -> NativeLocalHostConnection {
  let parent_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(parent_path).unwrap()
  // Each independently adopted Host owns a different original lock namespace.
  parent.create_directory(name + ".fixture").unwrap() |> ignore
  parent.close().unwrap()
  let path = parent_path + "/" + name + ".fixture"
  let root = @filesystem.open_private_root(path).unwrap()
  let account = if allow {
    b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"original-worker\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"local\"]},\"resource\":{\"any_of\":[\"worker\"]},\"operation\":{\"any_of\":[\"provision\",\"read\"]},\"exclusions\":[]}]}"
  } else {
    local_selected_account
  }
  let writer = root.create_writer(name + ".account.stage", 4096L).unwrap()
  writer.append(account).unwrap()
  writer.seal(name + ".account.json").unwrap() |> ignore
  root.close().unwrap()
  begin_native_local_host_adoption(
    path,
    name + ".host",
    path,
    name + ".account.json",
    "operator",
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
}

///|
fn worker_provisioning_reopen(name : String) -> NativeLocalHostConnection {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/" + name + ".fixture"
  begin_native_local_host_adoption(
    path,
    name + ".host",
    path,
    name + ".account.json",
    "operator",
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
}

///|
fn worker_provisioning_selection(
  generation : Int64,
) -> (@arena.InstalledArenaHost, @arena.InstalledArenaWorkerSelection) {
  // Metadata only. No actual arena, resource ticket, Core, DLL or worker opens.
  let arena = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    generation,
    1048576L,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 1048576L,
    },
    65536L,
  ).unwrap()
  (arena, arena.worker_provisioning_selection().unwrap())
}

///|
test "worker provisioning first identity reopens unresolved without a new key or acquisition" {
  let name = "worker-original-reopen"
  let host = worker_provisioning_test_host(name, true)
  let (arena, selection) = worker_provisioning_selection(1L)
  let original = host
    .issue_worker_provisioning(selection, "operator", "local")
    .unwrap()
  let body = original.body
  let key = original.key
  assert_true(key.has_prefix("worker/") && key.length() == 71)
  assert_true(
    original.observe("operator", "local")
    is Ok(UnresolvedOriginal(_, _, Recorded)),
  )
  host.close().unwrap()
  let restored = worker_provisioning_reopen(name)
  for _ in 0..<2 {
    guard restored.lookup_worker_provisioning(selection, "operator", "local")
      is Ok(UnresolvedOriginal(saved, bytes, Recorded)) else {
      fail("missing original child")
    }
    assert_eq(saved, key)
    assert_eq(bytes, body)
    assert_true(
      restored.issue_worker_provisioning(selection, "operator", "local")
      is Err(CustodyLost),
    )
  }
  assert_true(arena.require_current() is Err(@bootstrap.Unavailable))
  assert_eq(
    restored.database
    .read("client_worker_provisioning_custody", "selected")
    .unwrap().revision,
    1L,
  )
  restored.close().unwrap()
  arena.try_close().unwrap()
}

///|
test "worker provisioning lost first commit reply keeps original key and lookup only" {
  let name = "worker-original-lost-reply"
  let host = worker_provisioning_test_host(name, true)
  let (arena, selection) = worker_provisioning_selection(1L)
  client_test_fail_commit_reply(host.database, 1)
  assert_true(
    host.issue_worker_provisioning(selection, "operator", "local")
    is Err(Journal(TransactionUnknown)),
  )
  let original = host.worker_provisioning_attempt.unwrap()
  let key = original.key
  assert_true(original.observe("operator", "local") is Err(Adoption(Fenced)))
  host.close().unwrap()
  let restored = worker_provisioning_reopen(name)
  guard restored.lookup_worker_provisioning(selection, "operator", "local")
    is Ok(UnresolvedOriginal(saved, _, Recorded)) else {
    fail("lost original commit")
  }
  assert_eq(saved, key)
  assert_true(
    restored.issue_worker_provisioning(selection, "operator", "local")
    is Err(CustodyLost),
  )
  restored.close().unwrap()
  arena.try_close().unwrap()
}

///|
test "worker provisioning uncommitted first write keeps durable intent unresolved and cannot reissue" {
  let name = "worker-original-no-commit"
  let host = worker_provisioning_test_host(name, true)
  let (arena, selection) = worker_provisioning_selection(1L)
  client_test_fail_commit(host.database, 1)
  assert_true(
    host.issue_worker_provisioning(selection, "operator", "local")
    is Err(Journal(TransactionUnknown)),
  )
  let key = host.worker_provisioning_attempt.unwrap().key
  host.close().unwrap()
  let restored = worker_provisioning_reopen(name)
  guard restored.lookup_worker_provisioning(selection, "operator", "local")
    is Ok(UnresolvedOriginal(saved, _, NotRecorded)) else {
    fail("missing unresolved identity")
  }
  assert_eq(saved, key)
  assert_true(
    restored.issue_worker_provisioning(selection, "operator", "local")
    is Err(CustodyLost),
  )
  assert_eq(
    restored.database
    .read("client_worker_provisioning_custody", "selected")
    .unwrap().body,
    b"unissued",
  )
  restored.close().unwrap()
  arena.try_close().unwrap()
}

///|
test "worker provisioning foreign epoch or generation cannot adopt the original identity" {
  let host = worker_provisioning_test_host("worker-original-binding", true)
  let other = worker_provisioning_test_host("worker-original-foreign", true)
  let (arena, selection) = worker_provisioning_selection(1L)
  let (foreign_arena, foreign) = worker_provisioning_selection(2L)
  let original = host
    .issue_worker_provisioning(selection, "operator", "local")
    .unwrap()
  assert_true(
    host.lookup_worker_provisioning(foreign, "operator", "local")
    is Err(CustodyLost),
  )
  local_adoption_write(
    other.session.root,
    "worker-provisioning.json",
    original.body,
  ).unwrap()
  |> ignore
  assert_true(
    other.lookup_worker_provisioning(selection, "operator", "local")
    is Err(CustodyLost),
  )
  assert_eq(
    host.database.read("client_worker_provisioning", original.key).unwrap().body,
    original.body,
  )
  // Keep adoption/source/generation unchanged and replace only the fixture
  // epoch original. The independent epoch binding must reject this as well.
  let (_, now, revision) = read_epoch_custody(host.database).unwrap()
  let changed_epoch = epoch_custody_body(Bytes::make(32, 77), now).unwrap()
  host.database.begin_immediate().unwrap()
  host.database
  .compare_exchange(
    "client_submission_epoch", "authority", revision, changed_epoch,
  )
  .unwrap()
  |> ignore
  host.database.commit().unwrap()
  assert_true(
    host.lookup_worker_provisioning(selection, "operator", "local")
    is Err(CustodyLost),
  )
  host.close().unwrap()
  other.close().unwrap()
  arena.try_close().unwrap()
  foreign_arena.try_close().unwrap()
}

///|
test "worker provisioning missing custody and mere selection close never authorize a new generation" {
  let host = worker_provisioning_test_host("worker-original-retirement", true)
  let (arena, selection) = worker_provisioning_selection(1L)
  let original = host
    .issue_worker_provisioning(selection, "operator", "local")
    .unwrap()
  arena.try_close().unwrap()
  let (next_arena, next) = worker_provisioning_selection(2L)
  assert_true(
    host.issue_worker_provisioning(next, "operator", "local")
    is Err(CustodyLost),
  )
  // No physical worker stop/FD/alias retirement proof exists here. In
  // particular, a metadata-only Host close cannot issue a successor attempt.
  assert_eq(
    host.database.read("client_worker_provisioning", original.key).unwrap().revision,
    0L,
  )
  // Removing an original physical row is not retirement and cannot mint a
  // successor, even if a fresh installed metadata selection is available.
  host.database.begin_immediate().unwrap()
  host.database
  .remove_exact("client_worker_provisioning", original.key, 0L, original.body)
  .unwrap()
  host.database.commit().unwrap()
  let name = "worker-original-retirement"
  host.close().unwrap()
  let restored = worker_provisioning_reopen(name)
  let (same_generation_arena, same_generation) = worker_provisioning_selection(
    1L,
  )
  assert_true(
    restored.lookup_worker_provisioning(same_generation, "operator", "local")
    is Err(Journal(CustodyLost)),
  )
  assert_true(
    restored.issue_worker_provisioning(next, "operator", "local")
    is Err(CustodyLost),
  )
  assert_true(restored.worker_provisioning_attempt is None)
  restored.close().unwrap()
  next_arena.try_close().unwrap()
  same_generation_arena.try_close().unwrap()
}

///|
test "worker provisioning independent Account denial occurs before intent and journal writes" {
  let host = worker_provisioning_test_host("worker-original-denied", false)
  let (arena, selection) = worker_provisioning_selection(1L)
  assert_true(
    host.issue_worker_provisioning(selection, "operator", "local")
    is Err(AuthorizationDenied),
  )
  assert_true(host.worker_provisioning_attempt is None)
  assert_eq(
    host.session.root.inspect_generation("worker-provisioning.json").unwrap(),
    None,
  )
  assert_true(
    host.database.scan_after("client_worker_provisioning", "")
    is Err(@sqlite.NotFound),
  )
  host.close().unwrap()
  arena.try_close().unwrap()
}
