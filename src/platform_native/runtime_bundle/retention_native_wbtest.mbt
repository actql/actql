///|
fn native_retention_fixture(
  label : String,
) -> (NativeRuntimeBundleStore, @sqlite.Library, @signature.Library, String) {
  // This suite requires the owned native-core fixture. Missing physical inputs
  // are failures, never a counted test which silently returns without execution.
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let root = @filesystem.open_root(parent).unwrap()
  root.create_directory(label).unwrap() |> ignore
  let path = parent + "/" + label
  let root = root.open_child(label).unwrap()
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let store = open_runtime_bundle_store(
    sqlite,
    crypto,
    path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  let writer = root.create_writer("stage", 11L).unwrap()
  writer.append(b"runtime-one").unwrap()
  let generation = writer.seal("artifact").unwrap()
  adopt_native_bundle(store, generation, "artifact", "1") |> ignore
  store.activate(native_bundle_cid("1")).unwrap() |> ignore
  (store, sqlite, crypto, path)
}

///|
fn native_retention_scope(attempt : String) -> @bundle.RemoteBundleHoldScope {
  let distribution = @bundle.prepare_bundle_distribution([
    native_bundle_cid("1"),
  ]).unwrap()
  @bundle.prepare_bundle_hold_scope(
    distribution,
    "coordinator-a",
    "workspace-a",
    "sha256:" + "a".repeat(64),
    "development",
    "sha256:" + "b".repeat(64),
    native_bundle_cid("1"),
    "site-a",
    7,
    attempt,
  ).unwrap()
}

///|
fn native_retention_request(
  store : NativeRuntimeBundleStore,
  attempt : String,
) -> (@bundle.RemoteBundleDistribution, @bundle.RemoteBundleHoldBinding) {
  let distribution = @bundle.prepare_bundle_distribution([
    native_bundle_cid("1"),
  ]).unwrap()
  let request = @bundle.prepare_bundle_custody_context_query(
    distribution,
    native_retention_scope(attempt),
  ).unwrap()
  let response = store.custody(request).unwrap()
  let body = @bundle.bundle_custody_response_json(response).unwrap()
  @bundle.admit_bundle_custody_response_json(
    request,
    body,
    @bundle.bundle_custody_response_identity(response),
  ).unwrap()
  |> ignore
  (distribution, @bundle.bundle_custody_response_binding(response))
}

///|
test "typed bundle custody survives restart and fences delayed retain" {
  let (store, sqlite, crypto, path) = native_retention_fixture("typed-restart")
  let (distribution, binding) = native_retention_request(
    store, "original-attempt",
  )
  let request = @bundle.prepare_bundle_custody_request(
    distribution, binding, "retain",
  ).unwrap()
  let retained = store.custody(request).unwrap()
  assert_eq(
    @bundle.bundle_custody_response_observation(retained),
    Some(@bundle.BundleHoldRetained),
  )
  let revision = @bundle.bundle_custody_response_record_revision(retained)
  let repeated = store.custody(request).unwrap()
  assert_eq(@bundle.bundle_custody_response_record_revision(repeated), revision)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 11L)
  assert_true(store.close().unwrap())
  let reopened = open_runtime_bundle_store(
    sqlite,
    crypto,
    path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  assert_eq(
    reopened.inspect_member_hold(binding).unwrap().observation,
    @bundle.BundleHoldRetained,
  )
  reopened.drain(native_bundle_cid("1")).unwrap() |> ignore
  assert_eq(
    reopened.retain_member(binding).unwrap().observation,
    @bundle.BundleHoldRetained,
  )
  assert_eq(
    reopened.release_member(binding).unwrap().observation,
    @bundle.BundleHoldFenced,
  )
  let released = reopened.release_member(binding).unwrap()
  assert_eq(
    reopened.retain_member(binding).unwrap().record_revision,
    released.record_revision,
  )
  reopened.reclaim(native_bundle_cid("1")).unwrap() |> ignore
  assert_eq(
    reopened.inspect_member_hold(binding).unwrap().observation,
    @bundle.BundleHoldFenced,
  )
  assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(reopened.close().unwrap())
}

///|
test "typed bundle release before retain and replacement catalog fail closed" {
  let (store, _, _, _) = native_retention_fixture("typed-fence")
  let (_, binding) = native_retention_request(store, "release-first")
  assert_eq(
    store.inspect_member_hold(binding).unwrap().observation,
    @bundle.BundleHoldUnresolved,
  )
  assert_eq(
    store.release_member(binding).unwrap().observation,
    @bundle.BundleHoldFenced,
  )
  assert_eq(
    store.retain_member(binding).unwrap().observation,
    @bundle.BundleHoldFenced,
  )
  let (_, fresh) = native_retention_request(store, "fresh-attempt")
  let current = load_catalog(store).unwrap()
  let replaced = {
    ..current,
    revision: current.revision + 1L,
    catalog_incarnation: Some("00000000-0000-0000-0000-000000000000"),
  }
  persist_catalog(store, current, replaced).unwrap()
  let before = store.inspect(native_bundle_cid("1")).unwrap().unwrap().state
  assert_eq(
    store.retain_member(fresh).unwrap().observation,
    @bundle.BundleHoldUnavailable,
  )
  assert_eq(
    store.release_member(fresh).unwrap().observation,
    @bundle.BundleHoldUnavailable,
  )
  assert_eq(
    store.inspect(native_bundle_cid("1")).unwrap().unwrap().state,
    before,
  )
  let missing_distribution = @bundle.prepare_bundle_distribution([
    native_bundle_cid("2"),
  ]).unwrap()
  let missing = @bundle.prepare_bundle_hold_binding(
    missing_distribution,
    replaced.catalog_incarnation.unwrap(),
    "coordinator-a",
    "workspace-a",
    "sha256:" + "a".repeat(64),
    "development",
    "sha256:" + "b".repeat(64),
    native_bundle_cid("2"),
    "site-a",
    7,
    0,
    "missing-member",
  ).unwrap()
  assert_eq(
    store.inspect_member_hold(missing).unwrap().observation,
    @bundle.BundleHoldUnavailable,
  )
  assert_eq(
    store.release_member(missing).unwrap().observation,
    @bundle.BundleHoldUnavailable,
  )
  assert_true(store.close().unwrap())
}

///|
test "generic holds cannot impersonate typed bundle custody" {
  let (store, _, _, _) = native_retention_fixture("typed-namespace")
  let (_, binding) = native_retention_request(store, "typed-owner")
  let hold_id = member_hold_id(binding)
  assert_true(
    store.retain(native_bundle_cid("1"), hold_id, "workspace-set")
    is Err(InvalidConfiguration),
  )
  store.retain_member(binding).unwrap() |> ignore
  assert_true(store.release(hold_id) is Err(InvalidConfiguration))
  assert_eq(
    store.inspect_member_hold(binding).unwrap().observation,
    @bundle.BundleHoldRetained,
  )
  let current = load_catalog(store).unwrap()
  let bytes = catalog_bytes(current, store.max_record_bytes).unwrap()
  assert_true(admit_store_catalog(store, current.revision, bytes) is Ok(_))
  let changed = @utf8.decode(bytes).replace_all(
    old="typed-owner",
    new="other-owner",
  )
  assert_true(
    admit_store_catalog(store, current.revision, @utf8.encode(changed))
    is Err(_),
  )
  store.release_member(binding).unwrap() |> ignore
  assert_true(store.close().unwrap())
}

///|
test "typed bundle observations verify the original physical allocation" {
  let (store, _, _, _) = native_retention_fixture("typed-physical")
  let (_, binding) = native_retention_request(store, "physical-attempt")
  store.retain_member(binding).unwrap() |> ignore
  let catalog = load_catalog(store).unwrap()
  let entry = catalog.entries[0]
  store.root.reclaim_generation(entry.artifact_name, entry.generation).unwrap()
  assert_eq(
    store.inspect_member_hold(binding).unwrap().observation,
    @bundle.BundleHoldUnavailable,
  )
  assert_eq(
    store.retain_member(binding).unwrap().observation,
    @bundle.BundleHoldUnavailable,
  )
  // Losing bytes does not lose the original release authority or owner count.
  assert_eq(
    store.release_member(binding).unwrap().observation,
    @bundle.BundleHoldFenced,
  )
  assert_true(store.close().unwrap())
}

///|
test "legacy bundle catalogs require explicit retention initialization" {
  let (store, sqlite, crypto, path) = native_retention_fixture("typed-legacy")
  let current = load_catalog(store).unwrap()
  let legacy = { ..current, catalog_incarnation: None, }
  let bytes = catalog_bytes(legacy, store.max_record_bytes).unwrap()
  store.database
  .compare_exchange("runtime_bundle", "catalog", current.revision, bytes)
  .unwrap()
  |> ignore
  // Missing custody on this already initialized handle is not repaired.
  assert_true(store.initialize_retention() is Err(RecoveryRequired))
  store.database.close()
  assert_true(store.lock.close())
  let reopened = open_runtime_bundle_store(
    sqlite,
    crypto,
    path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  assert_true(
    reopened.retention_context(native_bundle_cid("1")) is Err(RecoveryRequired),
  )
  assert_eq(
    reopened.database.read("runtime_bundle", "catalog").unwrap().body,
    bytes,
  )
  let incarnation = reopened.initialize_retention().unwrap()
  assert_true(@bundle.valid_bundle_catalog_incarnation(incarnation))
  assert_eq(reopened.initialize_retention().unwrap(), incarnation)
  assert_eq(
    reopened.retention_context(native_bundle_cid("1")).unwrap().catalog_incarnation,
    incarnation,
  )
  assert_true(reopened.close().unwrap())
}

///|
test "bundle context alone acquires no hold and is not a replay journal" {
  let (store, _, _, _) = native_retention_fixture("typed-context")
  let distribution = @bundle.prepare_bundle_distribution([
    native_bundle_cid("1"),
  ]).unwrap()
  let request = @bundle.prepare_bundle_custody_context_query(
    distribution,
    native_retention_scope("context-only"),
  ).unwrap()
  let first = store.custody(request).unwrap()
  assert_eq(
    store.inspect(native_bundle_cid("1")).unwrap().unwrap().state[2],
    "0",
  )
  store.retain(native_bundle_cid("1"), "ordinary-owner", "dispatch").unwrap()
  |> ignore
  let later = store.custody(request).unwrap()
  assert_true(
    @bundle.bundle_hold_binding_identity(
      @bundle.bundle_custody_response_binding(first),
    ) !=
    @bundle.bundle_hold_binding_identity(
      @bundle.bundle_custody_response_binding(later),
    ),
  )
  // A lost context response must remain unresolved at the Coordinator. The
  // Store does not invent a saved reply, a new attempt, or a hold to recover it.
  assert_eq(
    store.inspect(native_bundle_cid("1")).unwrap().unwrap().state[2],
    "1",
  )
  assert_eq(
    store
    .inspect_member_hold(@bundle.bundle_custody_response_binding(first))
    .unwrap().observation,
    @bundle.BundleHoldFenced,
  )
  assert_true(store.release("ordinary-owner").unwrap())
  assert_true(store.close().unwrap())
}
