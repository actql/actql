///|
test "recorded live worker current requires the retained attempt and committed resource without writing" {
  let (host, attempt, arena, _, scope, domain, fd) = worker_resource_fixture(
    "worker-live-retained",
  )
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(CustodyLost),
  )
  attempt.record_resource_original(domain, "operator", "local").unwrap()
  let key = worker_resource_record_key(attempt.key)
  let before = host.database.read("client_worker_provisioning", key).unwrap()
  for _ in 0..<2 {
    attempt
    .require_recorded_resource_current(domain, "operator", "local")
    .unwrap()
  }
  let after = host.database.read("client_worker_provisioning", key).unwrap()
  assert_eq(after.revision, before.revision)
  assert_eq(after.body, before.body)
  let copy : NativeLocalWorkerProvisioningAttempt = {
    host,
    selection: attempt.selection,
    body: attempt.body,
    key: attempt.key,
    resource: attempt.resource,
  }
  assert_true(
    copy.require_recorded_resource_current(domain, "operator", "local")
    is Err(CustodyLost),
  )
  host.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}

///|
test "recorded live worker current rejects foreign domain and current Account denial without releasing the original" {
  let (host, attempt, arena, _, scope, domain, fd) = worker_resource_fixture(
    "worker-live-current",
  )
  let (other_host, _, other_arena, _, other_scope, other_domain, other_fd) = worker_resource_fixture(
    "worker-live-foreign",
  )
  attempt.record_resource_original(domain, "operator", "local").unwrap()
  assert_true(
    attempt.require_recorded_resource_current(other_domain, "operator", "local")
    is Err(CustodyLost),
  )
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "other")
    is Err(AuthorizationDenied),
  )
  arena.require_domain_current(domain).unwrap()
  attempt
  .require_recorded_resource_current(domain, "operator", "local")
  .unwrap()
  assert_true(arena.try_close() is Err(@bootstrap.ReadersPending))
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(Selection(@bootstrap.Closing)),
  )
  assert_true(
    attempt.resource is Some(original) &&
    physical_equal(original.domain, domain),
  )
  host.close().unwrap()
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(Adoption(Closed)),
  )
  other_host.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
  worker_resource_fixture_retire(
    other_arena, other_scope, other_domain, other_fd,
  )
}

///|
test "recorded live worker current rejects changed and oversized saved resource rows with typed physical failure" {
  let (host, attempt, arena, _, scope, domain, fd) = worker_resource_fixture(
    "worker-live-row",
  )
  attempt.record_resource_original(domain, "operator", "local").unwrap()
  let original = attempt.resource.unwrap()
  let key = worker_resource_record_key(attempt.key)
  host.database.begin_immediate().unwrap()
  host.database
  .compare_exchange("client_worker_provisioning", key, 0L, b"changed")
  .unwrap()
  |> ignore
  host.database.commit().unwrap()
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(Journal(CustodyLost)),
  )
  host.database.begin_immediate().unwrap()
  host.database
  .compare_exchange(
    "client_worker_provisioning",
    key,
    1L,
    Bytes::make(4097, 65),
  )
  .unwrap()
  |> ignore
  host.database.commit().unwrap()
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(Journal(Physical(@sqlite.BodyTooLarge))),
  )
  assert_true(physical_equal(attempt.resource.unwrap(), original))
  arena.require_domain_current(domain).unwrap()
  host.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}

///|
test "recorded live worker current rechecks the original epoch rather than accepting equal saved resource DATA" {
  let (host, attempt, arena, _, scope, domain, fd) = worker_resource_fixture(
    "worker-live-epoch",
  )
  attempt.record_resource_original(domain, "operator", "local").unwrap()
  let original = attempt.resource.unwrap()
  let (_, now, revision) = read_epoch_custody(host.database).unwrap()
  let changed = epoch_custody_body(Bytes::make(32, 77), now).unwrap()
  host.database.begin_immediate().unwrap()
  host.database
  .compare_exchange("client_submission_epoch", "authority", revision, changed)
  .unwrap()
  |> ignore
  host.database.commit().unwrap()
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(CustodyLost),
  )
  assert_true(physical_equal(attempt.resource.unwrap(), original))
  arena.require_domain_current(domain).unwrap()
  host.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}

///|
test "recorded live worker current preserves unknown resource COMMIT and cold lookup cannot adopt live custody" {
  let label = "worker-live-lost"
  let (host, attempt, arena, selection, scope, domain, fd) = worker_resource_fixture(
    label,
  )
  submitted_test_fail_commit_after(host.database, 1, true)
  assert_true(
    attempt.record_resource_original(domain, "operator", "local")
    is Err(Journal(TransactionUnknown)),
  )
  let original = attempt.resource.unwrap()
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(Adoption(Fenced)),
  )
  host.close().unwrap()
  let restored = worker_provisioning_reopen(label)
  assert_true(
    restored.lookup_worker_resource_original(selection, "operator", "local")
    is Ok(UnresolvedRecorded(_, _, _)),
  )
  assert_true(restored.worker_provisioning_attempt is None)
  assert_true(physical_equal(attempt.resource.unwrap(), original))
  restored.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}

///|
test "recorded live worker current read transaction failure fences the same attempt and retains the physical domain" {
  let (host, attempt, arena, _, scope, domain, fd) = worker_resource_fixture(
    "worker-live-observation-unknown",
  )
  attempt.record_resource_original(domain, "operator", "local").unwrap()
  let original = attempt.resource.unwrap()
  submitted_test_fail_commit_after(host.database, 0, true)
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(Journal(TransactionUnknown)),
  )
  assert_true(
    attempt.require_recorded_resource_current(domain, "operator", "local")
    is Err(Adoption(Fenced)),
  )
  assert_true(physical_equal(attempt.resource.unwrap(), original))
  arena.require_domain_current(domain).unwrap()
  host.close().unwrap()
  worker_resource_fixture_retire(arena, scope, domain, fd)
}
