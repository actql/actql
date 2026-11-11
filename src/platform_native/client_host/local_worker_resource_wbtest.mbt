///|
#borrow(path)
extern "C" fn worker_resource_fixture_open(path : Bytes, flags : Int) -> Int = "open"

///|
extern "C" fn worker_resource_fixture_close(fd : Int) -> Int = "close"

///|
extern "C" fn worker_resource_fixture_page() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn worker_resource_fixture(
  label : String,
) -> (
  NativeLocalHostConnection,
  NativeLocalWorkerProvisioningAttempt,
  @arena.InstalledArenaHost,
  @arena.InstalledArenaWorkerSelection,
  @arena.InstalledArenaBackingBorrow,
  @arena.InstalledArenaDomain,
  Int,
) raise {
  let host = worker_provisioning_test_host(label, true)
  let bytes = 64L * worker_resource_fixture_page()
  let arena = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).unwrap()
  let selection = arena.worker_provisioning_selection().unwrap()
  // Child identity is durable before physical child acquisition.
  let attempt = host
    .issue_worker_provisioning(selection, "operator", "local")
    .unwrap()
  let parent_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(parent_path).unwrap()
  let writer = root.create_writer(label + ".backing.stage", bytes).unwrap()
  writer.append(Bytes::make(bytes.to_int(), 0)).unwrap()
  writer.seal(label + ".backing").unwrap() |> ignore
  writer.close_retaining_files().unwrap()
  root.close().unwrap()
  let name = @utf8.encode(parent_path + "/" + label + ".backing\u{0000}")
  // The bounded fixture owns this precreated 0600 regular file. These two libc
  // calls are test transport only, not a new installed allocator/provider.
  let fd = worker_resource_fixture_open(name, 2)
  assert_true(fd >= 0)
  arena.acquire_fd(fd).unwrap()
  let scope = arena.borrow_backing().unwrap()
  arena.enter_backing_borrow_scope(scope).unwrap()
  let domain = match
    arena.prepare_domain(scope, fd, 16L * worker_resource_fixture_page(), {
      planning_work: 2,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 3L,
      retained_bytes: 0L,
      execution_bytes: 16L * worker_resource_fixture_page(),
    }) {
    Ok(@arena.PreparedDomain(domain)) => domain
    _ => fail("original physical domain did not prepare")
  }
  arena.transfer_domain(domain).unwrap()
  arena.leave_backing_borrow_scope(scope).unwrap()
  (host, attempt, arena, selection, scope, domain, fd)
}

///|
fn worker_resource_fixture_retire(
  arena : @arena.InstalledArenaHost,
  scope : @arena.InstalledArenaBackingBorrow,
  domain : @arena.InstalledArenaDomain,
  fd : Int,
) -> Unit raise {
  arena.return_backing_borrow(scope).unwrap()
  // This test has no launched worker or external borrower. Actual scope has
  // ended. The existing Owner retires only this view/loan before its mapping.
  arena.close_domain_after_owner_ack(domain).unwrap()
  arena.try_close().unwrap()
  assert_eq(worker_resource_fixture_close(fd), 0)
}

///|
test "worker resource original persists actual same provider extent and cold DATA under the original child key" {
  let label = "worker-resource-store"
  let (host, attempt, arena, selection, scope, domain, fd) = worker_resource_fixture(
    label,
  )
  let original_key = attempt.key
  let (physical, resource) = selection.project_domain_original(domain).unwrap()
  attempt.record_resource_original(domain, "operator", "local").unwrap()
  assert_true(
    attempt.record_resource_original(domain, "operator", "local")
    is Err(CustodyLost),
  )
  host.close().unwrap()
  let restored = worker_provisioning_reopen(label)
  guard restored.lookup_worker_resource_original(selection, "operator", "local")
    is Ok(UnresolvedRecorded(key, saved_physical, saved_resource)) else {
    fail("missing original resource DATA")
  }
  assert_eq(key, original_key)
  assert_eq(saved_physical, physical)
  assert_eq(
    @resources.unresolved_backed_execution_data(saved_resource),
    resource,
  )
  assert_eq(
    restored.database
    .read("client_worker_provisioning_custody", "selected")
    .unwrap().revision,
    1L,
  )
  assert_true(restored.worker_provisioning_attempt is None)
  restored.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}

///|
test "worker resource original lost commit reply looks up the same actual row and never writes again" {
  let label = "worker-resource-lost"
  let (host, attempt, arena, selection, scope, domain, fd) = worker_resource_fixture(
    label,
  )
  submitted_test_fail_commit_after(host.database, 1, true)
  assert_true(
    attempt.record_resource_original(domain, "operator", "local")
    is Err(Journal(TransactionUnknown)),
  )
  assert_true(attempt.resource is Some(_))
  assert_true(
    attempt.record_resource_original(domain, "operator", "local")
    is Err(CustodyLost),
  )
  host.close().unwrap()
  let restored = worker_provisioning_reopen(label)
  assert_true(
    restored.lookup_worker_resource_original(selection, "operator", "local")
    is Ok(UnresolvedRecorded(key, _, _)) &&
    key == attempt.key,
  )
  assert_true(restored.worker_provisioning_attempt is None)
  restored.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}

///|
test "worker resource original uncommitted write stays unresolved under the same key and preserves actual child custody" {
  let label = "worker-resource-unknown"
  let (host, attempt, arena, selection, scope, domain, fd) = worker_resource_fixture(
    label,
  )
  submitted_test_fail_commit_after(host.database, 1, false)
  assert_true(
    attempt.record_resource_original(domain, "operator", "local")
    is Err(Journal(TransactionUnknown)),
  )
  let original = attempt.resource.unwrap()
  assert_true(physical_equal(original.domain, domain))
  assert_true(
    attempt.record_resource_original(domain, "operator", "local")
    is Err(CustodyLost),
  )
  host.close().unwrap()
  let restored = worker_provisioning_reopen(label)
  guard restored.lookup_worker_resource_original(selection, "operator", "local")
    is Ok(UnresolvedNotRecorded(key)) else {
    fail("missing original unresolved write")
  }
  assert_eq(key, attempt.key)
  assert_true(restored.worker_provisioning_attempt is None)
  restored.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}

///|
test "worker resource original rejects foreign equal DATA child and inconsistent backing record without replacing original custody" {
  let (host, attempt, arena, selection, scope, domain, fd) = worker_resource_fixture(
    "worker-resource-foreign",
  )
  let (other_host, other, other_arena, _, other_scope, other_domain, other_fd) = worker_resource_fixture(
    "worker-resource-other",
  )
  assert_true(
    attempt.record_resource_original(other_domain, "operator", "local")
    is Err(PhysicalSelection(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(attempt.resource is None)
  attempt.record_resource_original(domain, "operator", "local").unwrap()
  let body = attempt.resource.unwrap().body
  let fields = local_adoption_fields(body, worker_physical_fields()).unwrap()
  // Same original operation and Resource values; change only actual backing.
  fields[6] = "1"
  let changed = local_adoption_record(
    worker_physical_fields().mapi((i, key) => (key, fields[i])),
  ).unwrap()
  // The outer backing cannot be smaller than its original Resource allocation.
  assert_true(
    read_worker_physical_original(attempt.body, changed) is Err(CustodyLost),
  )
  assert_true(attempt.resource is Some(value) && value.body == body)
  assert_true(other.resource is None)
  // Changing the original binding or schema is rejected by the closed reader.
  assert_true(
    read_worker_physical_original(other.body, body) is Err(CustodyLost),
  )
  fields[13] = "actql-local-worker-resource/foreign"
  let changed = local_adoption_record(
    worker_physical_fields().mapi((i, key) => (key, fields[i])),
  ).unwrap()
  assert_true(
    read_worker_physical_original(attempt.body, changed) is Err(CustodyLost),
  )
  assert_true(
    host.lookup_worker_resource_original(selection, "operator", "local")
    is Ok(UnresolvedRecorded(_, _, _)),
  )
  host.close().unwrap()
  other_host.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
  worker_resource_fixture_retire(
    other_arena, other_scope, other_domain, other_fd,
  )
}

///|
test "worker resource original current Account refusal cannot record DATA or dispose the existing physical child" {
  let (host, attempt, arena, _, scope, domain, fd) = worker_resource_fixture(
    "worker-resource-current",
  )
  assert_true(
    attempt.record_resource_original(domain, "operator", "other")
    is Err(AuthorizationDenied),
  )
  assert_true(attempt.resource is None)
  assert_true(
    host.database.read(
      "client_worker_provisioning",
      worker_resource_record_key(attempt.key),
    )
    is Err(@sqlite.NotFound),
  )
  arena.require_domain_current(domain).unwrap()
  attempt.record_resource_original(domain, "operator", "local").unwrap()
  // Logical closing does not discard the saved original or fabricate cleanup.
  assert_true(arena.try_close() is Err(@bootstrap.ReadersPending))
  assert_true(
    attempt.resource is Some(value) && physical_equal(value.domain, domain),
  )
  host.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}
