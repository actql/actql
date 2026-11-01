///|
fn bundle_open_custody_fixture(
  name : String,
) -> (@sqlite.Library, @signature.Library, String) {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let root = @filesystem.open_root(parent).unwrap()
  root.create_directory(name).unwrap() |> ignore
  root.close().unwrap()
  (
    @sqlite.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    ).unwrap(),
    @signature.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    ).unwrap(),
    parent + "/" + name,
  )
}

///|
test "Bundle constructor refusal and original failed SQLite custody remain distinct" {
  let (sqlite, crypto, path) = bundle_open_custody_fixture(
    "bundle-open-failed-db",
  )
  assert_true(
    open_runtime_bundle_store_with_custody(
      sqlite,
      crypto,
      path,
      [],
      "aarch64-apple-darwin",
      22L,
      8,
      8,
      1048576L,
    )
    is Err(RefusedBeforeAcquisition(InvalidConfiguration)),
  )
  let root = @filesystem.open_root(path).unwrap()
  assert_eq(
    root.inspect_generation(".actql-runtime-bundle.lock").unwrap(),
    None,
  )
  root.create_directory(".actql-runtime-bundle.sqlite3").unwrap() |> ignore
  root.close().unwrap()
  let failure = match
    open_runtime_bundle_store_with_custody(
      sqlite,
      crypto,
      path,
      native_bundle_authorities(),
      "aarch64-apple-darwin",
      22L,
      8,
      8,
      1048576L,
    ) {
    Err(CleanupRequired(original)) => original
    _ => {
      fail("failed SQLite construction discarded its acquired custody")
      return
    }
  }
  assert_true(failure.issue() is Database(@sqlite.DatabaseOpen(_)))
  assert_true(failure.failed_database is Some(_))
  assert_true(failure.lock is Some(_))
  assert_true(failure.root is Some(_))
  failure.retry_cleanup().unwrap()
  assert_true(failure.failed_database is None)
  assert_true(failure.lock is None)
  assert_true(failure.root is None)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is Database(@sqlite.DatabaseOpen(_)))
}

///|
test "Bundle catalog rejection retains the same initialized DB until checked cleanup" {
  let (sqlite, crypto, path) = bundle_open_custody_fixture(
    "bundle-open-bad-catalog",
  )
  let original = open_runtime_bundle_store_with_custody(
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
  original.database.insert("independent", "original", b"untouched").unwrap()
  |> ignore
  let catalog = original.database.read("runtime_bundle", "catalog").unwrap()
  original.database
  .compare_exchange("runtime_bundle", "catalog", catalog.revision, b"invalid")
  .unwrap()
  |> ignore
  // Fault setup retires real handles without asking the invalid catalog to
  // prove a successful Store transition. The production reopen rejects it.
  original.database.close_checked().unwrap()
  original.lock.close_checked().unwrap()
  original.root.close().unwrap()
  let failure = match
    open_runtime_bundle_store_with_custody(
      sqlite,
      crypto,
      path,
      native_bundle_authorities(),
      "aarch64-apple-darwin",
      22L,
      8,
      8,
      1048576L,
    ) {
    Err(CleanupRequired(same)) => same
    _ => {
      fail("invalid catalog lost initialized handles or was repaired")
      return
    }
  }
  let database = failure.database.unwrap()
  let lock = failure.lock.unwrap()
  let root = failure.root.unwrap()
  bundle_close_fail_database(database, 1)
  assert_true(failure.retry_cleanup() is Err(Database(@sqlite.Physical(_))))
  assert_true(physical_equal(database, failure.database.unwrap()))
  assert_true(physical_equal(lock, failure.lock.unwrap()))
  assert_true(physical_equal(root, failure.root.unwrap()))
  assert_eq(bundle_close_database_attempts(database), 1)
  failure.retry_cleanup().unwrap()
  assert_eq(bundle_close_database_attempts(database), 2)
  failure.retry_cleanup().unwrap()
  assert_eq(bundle_close_database_attempts(database), 2)
  let restored = sqlite
    .open_existing_database(path + "/.actql-runtime-bundle.sqlite3", 1048576L)
    .unwrap()
  assert_eq(
    restored.read("runtime_bundle", "catalog").unwrap().body,
    b"invalid",
  )
  assert_eq(
    restored.read("independent", "original").unwrap().body,
    b"untouched",
  )
  restored.close_checked().unwrap()
}

///|
test "Bundle failed preparation Lock Unknown preserves outer Root and never recloses its FD" {
  let (store, _, _, _) = native_retention_fixture("bundle-open-lock-unknown")
  let failure = bundle_store_open_failure(
    StateCollision,
    root=Some(store.root),
    lock=Some(store.lock),
    database=Some(store.database),
  )
  assert_true(bundle_close_lose_lock_observation(store.lock))
  assert_true(
    failure.retry_cleanup() is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_true(failure.database is None)
  assert_true(failure.lock is Some(same) && physical_equal(same, store.lock))
  assert_true(failure.root is Some(same) && physical_equal(same, store.root))
  let writer = store.root.create_writer("independent-fd-reuse", 3L).unwrap()
  assert_true(
    failure.retry_cleanup() is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  writer.append(b"abc").unwrap()
  writer.cancel().unwrap()
  assert_true(failure.issue() is StateCollision)
}

///|
test "Bundle verification Reader stays with original Store until its checked retirement" {
  let (store, _, _, _) = native_retention_fixture(
    "bundle-verification-reader-pending",
  )
  let generation = store.root.inspect_generation("artifact").unwrap().unwrap()
  let reader = store.root
    .open_reader_with_custody("artifact", generation)
    .unwrap()
  store.component_reader = Some(reader)
  assert_true(store.active() is Err(CleanupPending))
  assert_true(
    store.component_reader is Some(same) && physical_equal(same, reader),
  )
  assert_eq(bundle_close_database_attempts(store.database), 0)
  assert_true(
    store.acquire_active_component_with_custody("foreign", "foreign", "process")
    is Err(RefusedBeforeHolding(CleanupPending)),
  )
  store.close_checked().unwrap()
  assert_true(store.component_reader is None)
  assert_true(store.closed)
  assert_eq(bundle_close_database_attempts(store.database), 1)
  store.close_checked().unwrap()
  assert_eq(bundle_close_database_attempts(store.database), 1)
}

///|
test "Bundle process release first retires its same pending verification Reader" {
  let (store, _, _, _) = native_retention_fixture("bundle-reader-release-order")
  store
  .retain(native_bundle_cid("1"), "original-process-reader", "runtime-process")
  .unwrap()
  |> ignore
  let generation = store.root.inspect_generation("artifact").unwrap().unwrap()
  let reader = store.root
    .open_reader_with_custody("artifact", generation)
    .unwrap()
  store.component_reader = Some(reader)
  assert_true(store.inspect(native_bundle_cid("1")) is Err(CleanupPending))
  assert_true(store.release("original-process-reader").unwrap())
  assert_true(store.component_reader is None)
  assert_eq(
    store.inspect(native_bundle_cid("1")).unwrap().unwrap().state[2],
    "0",
  )
  assert_eq(bundle_close_database_attempts(store.database), 0)
  store.close_checked().unwrap()
  assert_eq(bundle_close_database_attempts(store.database), 1)
}

///|
test "Bundle process hold collision refuses before holding and preserves the foreign original" {
  let (store, _, _, _) = native_retention_fixture("bundle-process-foreign-hold")
  store
  .retain(native_bundle_cid("1"), "foreign-original", "independent-kind")
  .unwrap()
  |> ignore
  assert_true(
    store.acquire_active_component_with_custody(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "foreign-original",
    )
    is Err(RefusedBeforeHolding(HoldCollision)),
  )
  let original = store.inspect(native_bundle_cid("1")).unwrap().unwrap()
  assert_eq(original.state[2], "1")
  // The refused acquisition has no release responsibility for this foreign
  // nominal holding. Store handle retirement preserves the durable record.
  store.close_checked().unwrap()
}

///|
#borrow(reader)
extern "C" fn bundle_copy_lose_reader_close_observation(
  reader : @filesystem.Reader,
) -> Bool = "actql_native_filesystem_test_reader_consumed_unknown"

///|
test "Bundle component-copy Reader Unknown retains its original Store and outer handles" {
  let (store, _, _, _) = native_retention_fixture("bundle-copy-reader-unknown")
  store
  .retain(native_bundle_cid("1"), "copy-original-process", "runtime-process")
  .unwrap()
  |> ignore
  let generation = store.root.inspect_generation("artifact").unwrap().unwrap()
  let reader = store.root
    .open_reader_with_custody("artifact", generation)
    .unwrap()
  // The existing filesystem hook executes the real original close, then
  // loses its observation. No Bool or substituted descriptor supplies ACK.
  assert_true(bundle_copy_lose_reader_close_observation(reader))
  assert_true(
    close_bundle_component_reader(store, original_reader=Some(reader))
    is Err(Filesystem(@filesystem.Read(_))),
  )
  assert_true(
    store.component_reader is Some(same) && physical_equal(same, reader),
  )
  assert_true(store.active() is Err(CleanupPending))
  assert_true(store.capacity_usage() is Err(CleanupPending))
  assert_eq(bundle_close_database_attempts(store.database), 0)
  // A new independent FD may reuse the consumed number; cleanup must never
  // retry that number or retire this unrelated Writer in place of its Reader.
  let independent = store.root.create_writer("copy-independent-fd", 3L).unwrap()
  assert_true(store.close_checked() is Err(Filesystem(@filesystem.Read(_))))
  assert_true(
    store.release("copy-original-process")
    is Err(Filesystem(@filesystem.Read(_))),
  )
  assert_true(
    store.component_reader is Some(same) && physical_equal(same, reader),
  )
  assert_eq(bundle_close_database_attempts(store.database), 0)
  independent.append(b"abc").unwrap()
  independent.cancel().unwrap()
  // No terminal Store/Root/Library/Run stop is inferred from this refusal.
  assert_false(store.closed)
}

///|
#borrow(root)
extern "C" fn bundle_copy_fail_root_sync(
  root : @filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_root_sync"

///|
fn bundle_copy_cleanup_fixture(
  name : String,
) -> (
  NativeRuntimeBundleStore,
  @filesystem.Writer,
  NativeRuntimeBundleComponentCopy,
) {
  let (store, _, _, _) = native_retention_fixture(name)
  let (artifact_name, staging_name) = component_copy_names(
    native_bundle_cid("1"),
    "runtime_executable",
  )
  let intent : NativeRuntimeBundleComponentCopy = {
    runtime_bundle_cid: native_bundle_cid("1"),
    role: "runtime_executable",
    component_cid: "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
    component_bytes: 11L,
    artifact_name,
    staging_name,
    phase: Intent,
  }
  // Use the existing production order: real durable copy reservation before
  // opening/writing its physical staging object, then its original ownership.
  let current = load_catalog(store).unwrap()
  let copies = current.component_copies.copy()
  copies.push(intent)
  persist_catalog(store, current, with_catalog_copies(current, copies)).unwrap()
  |> ignore
  let writer = store.root.create_writer_with_custody(staging_name, 11L).unwrap()
  let copy = record_copy_phase(store, intent, StagingOwned(writer.ownership())).unwrap()
  writer.append(b"runtime-one").unwrap()
  (store, writer, copy)
}

///|
test "Bundle copy Writer sync failure retains original until physical cleanup and separate catalog recovery" {
  let (store, writer, copy) = bundle_copy_cleanup_fixture(
    "bundle-copy-writer-sync",
  )
  let catalog = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 22L)
  bundle_copy_fail_root_sync(store.root, 1)
  assert_true(
    cancel_bundle_component_writer(store, writer)
    is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_true(
    store.component_writer is Some(same) && physical_equal(same, writer),
  )
  assert_true(store.active() is Err(CleanupPending))
  assert_true(store.capacity_usage() is Err(CleanupPending))
  assert_eq(bundle_close_database_attempts(store.database), 0)
  let unchanged = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(unchanged.revision, catalog.revision)
  assert_eq(unchanged.body, catalog.body)
  // Same-Writer physical cleanup can now finish, but that is not its durable
  // copy reservation/CAS release or permission to retire the outer Store.
  assert_true(store.close_checked() is Err(CleanupPending))
  assert_true(store.component_writer is None)
  assert_eq(bundle_close_database_attempts(store.database), 0)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 22L)
  let after_cleanup = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(after_cleanup.revision, catalog.revision)
  assert_eq(after_cleanup.body, catalog.body)
  recover_component_copy(store, copy).unwrap()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 11L)
  store.close_checked().unwrap()
  assert_eq(bundle_close_database_attempts(store.database), 1)
}

///|
test "Bundle copy pending Reader keeps its same Writer before cancellation and outer retirement" {
  let (store, writer, _) = bundle_copy_cleanup_fixture(
    "bundle-copy-reader-writer",
  )
  let catalog = store.database.read("runtime_bundle", "catalog").unwrap()
  let generation = store.root.inspect_generation("artifact").unwrap().unwrap()
  let reader = store.root
    .open_reader_with_custody("artifact", generation)
    .unwrap()
  assert_true(bundle_copy_lose_reader_close_observation(reader))
  assert_true(
    close_bundle_component_reader(store, original_reader=Some(reader))
    is Err(Filesystem(@filesystem.Read(_))),
  )
  assert_true(
    cancel_bundle_component_writer(store, writer)
    is Err(Filesystem(@filesystem.Read(_))),
  )
  assert_true(
    store.component_reader is Some(same) && physical_equal(same, reader),
  )
  assert_true(
    store.component_writer is Some(same) && physical_equal(same, writer),
  )
  // Actual Writer append still succeeds: cleanup did not cancel its sibling
  // while the earlier Reader's close observation remains unknown.
  writer.append(b"").unwrap()
  assert_true(store.close_checked() is Err(Filesystem(@filesystem.Read(_))))
  assert_true(store.capacity_usage() is Err(CleanupPending))
  writer.append(b"").unwrap()
  assert_eq(bundle_close_database_attempts(store.database), 0)
  let unchanged = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(unchanged.revision, catalog.revision)
  assert_eq(unchanged.body, catalog.body)
  assert_false(store.closed)
}

///|
test "Bundle materialization public success retires its IO but keeps exact durable copy reservation" {
  let (store, _, _, _) = native_retention_fixture(
    "bundle-materialization-success",
  )
  let binding = store
    .acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "materialization-original-process",
    )
    .unwrap()
  let component = store
    .materialize_active_component(binding, "runtime_executable")
    .unwrap()
  let (_, _, _, bytes, name, generation, offset) = native_bundle_component_source_projection(
    component,
  )
  assert_eq(bytes, 11L)
  assert_eq(offset, 0L)
  assert_true(store.root.verify_generation(name, generation))
  let reader = store.root.open_reader_with_custody(name, generation).unwrap()
  assert_eq(reader.next(11).unwrap().bytes, b"runtime-one")
  reader.finish().unwrap()
  reader.close().unwrap()
  assert_true(store.component_reader is None)
  assert_true(store.component_open_failure is None)
  assert_true(store.component_writer is None)
  assert_true(store.component_writer_open_failure is None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 22L)
  // Native Store handle retirement preserves its original durable process
  // holding and copy bytes; it is not Run/Host or reservation release.
  store.close_checked().unwrap()
  assert_true(store.closed)
  assert_eq(bundle_close_database_attempts(store.database), 1)
}

///|
test "Bundle materialization public Writer refusal retains original failure and never deletes foreign staging" {
  let (store, _, _, _) = native_retention_fixture(
    "bundle-materialization-conflict",
  )
  let binding = store
    .acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "materialization-conflict-process",
    )
    .unwrap()
  let (_, staging_name) = component_copy_names(
    native_bundle_cid("1"),
    "runtime_executable",
  )
  let foreign = store.root.create_writer_with_custody(staging_name, 3L).unwrap()
  foreign.append(b"xyz").unwrap()
  foreign.close_retaining_files().unwrap()
  let foreign_generation = store.root
    .inspect_generation(staging_name)
    .unwrap()
    .unwrap()
  assert_true(
    store.materialize_active_component(binding, "runtime_executable")
    is Err(Filesystem(@filesystem.Conflict)),
  )
  let original = store.component_writer_open_failure.unwrap()
  assert_true(original.issue() is @filesystem.Conflict)
  assert_true(store.active() is Err(CleanupPending))
  assert_true(store.capacity_usage() is Err(CleanupPending))
  assert_eq(bundle_close_database_attempts(store.database), 0)
  let catalog = store.database.read("runtime_bundle", "catalog").unwrap()
  // Retiring only the actual failed constructor cannot remove the foreign
  // file or turn the unresolved durable Intent into free capacity.
  assert_true(store.close_checked() is Err(CleanupPending))
  assert_true(store.component_writer_open_failure is None)
  assert_eq(bundle_close_database_attempts(store.database), 0)
  let unchanged = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(unchanged.revision, catalog.revision)
  assert_eq(unchanged.body, catalog.body)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 22L)
  assert_true(store.root.verify_generation(staging_name, foreign_generation))
  let reader = store.root
    .open_reader_with_custody(staging_name, foreign_generation)
    .unwrap()
  assert_eq(reader.next(3).unwrap().bytes, b"xyz")
  reader.finish().unwrap()
  reader.close().unwrap()
  let copy = load_catalog(store).unwrap().component_copies[0]
  assert_true(copy.phase is Intent)
  assert_true(recover_component_copy(store, copy) is Err(RecoveryRequired))
  assert_true(store.root.verify_generation(staging_name, foreign_generation))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 22L)
  assert_false(store.closed)
}

///|
fn bundle_hash_empty_store(
  name : String,
) -> (NativeRuntimeBundleStore, @signature.Library) {
  let (sqlite, crypto, path) = bundle_open_custody_fixture(name)
  let store = open_runtime_bundle_store_with_custody(
    sqlite,
    crypto,
    path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    64L,
    8,
    8,
    1048576L,
  ).unwrap()
  (store, crypto)
}

///|
test "Bundle installer hash cancel retires its original EVP context before Library close" {
  let (store, crypto) = bundle_hash_empty_store("bundle-hash-cancel")
  let installer = store
    .begin_install(
      "original-cancel",
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_bundle_cid("1"),
      native_bundle_body("1"),
      native_bundle_signature("1"),
    )
    .unwrap()
  installer.append(b"partial").unwrap()
  installer.cancel().unwrap()
  assert_eq(store.inspect_install("original-cancel").unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  store.close_checked().unwrap()
  // The original installer alias is still live. GC/finalization must not be
  // needed to retire its EVP context or fabricate the parent Library's ACK.
  assert_true(installer.closed)
  assert_eq(crypto.close_checked(), Ok(()))
}

///|
test "Bundle installer hash multi-component seal retires the unused original EVP context" {
  let (store, crypto) = bundle_hash_empty_store("bundle-hash-multi")
  let installer = store
    .begin_install(
      "original-multi",
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_multi_component_cid(),
      native_multi_component_body(),
      native_multi_component_signature(),
    )
    .unwrap()
  installer.append(b"library-two").unwrap()
  installer.append(b"runtime-one").unwrap()
  let installed = installer.seal().unwrap()
  assert_eq(installed.runtime_bundle_cid, native_multi_component_cid())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 22L)
  store.close_checked().unwrap()
  assert_true(installer.closed)
  assert_eq(crypto.close_checked(), Ok(()))
}

///|
test "Bundle installer hash constructor conflict retires its original context without foreign cleanup" {
  let (store, crypto) = bundle_hash_empty_store("bundle-hash-constructor")
  let install_id = "original-hash-conflict"
  let install_key = @sha.hex(
    @utf8.encode(install_id + "\u0000" + native_bundle_cid("1")),
  )
  let staging_name = "runtime-stage-" + install_key
  let foreign = store.root.create_writer_with_custody(staging_name, 3L).unwrap()
  foreign.append(b"xyz").unwrap()
  foreign.close_retaining_files().unwrap()
  let generation = store.root.inspect_generation(staging_name).unwrap().unwrap()
  assert_true(
    store.begin_install(
      install_id,
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_bundle_cid("1"),
      native_bundle_body("1"),
      native_bundle_signature("1"),
    )
    is Err(Filesystem(@filesystem.Conflict)),
  )
  assert_true(store.root.verify_generation(staging_name, generation))
  assert_eq(store.inspect_install(install_id).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  store.close_checked().unwrap()
  assert_eq(crypto.close_checked(), Ok(()))
}

///|
test "Bundle hash materialization completes its original context before parent Library close" {
  let (store, _, crypto, _) = native_retention_fixture(
    "bundle-hash-materialization",
  )
  let binding = store
    .acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "hash-materialization-process",
    )
    .unwrap()
  let component = store
    .materialize_active_component(binding, "runtime_executable")
    .unwrap()
  let (_, _, _, bytes, name, generation, offset) = native_bundle_component_source_projection(
    component,
  )
  assert_eq(bytes, 11L)
  assert_eq(offset, 0L)
  assert_true(store.root.verify_generation(name, generation))
  assert_true(store.component_hasher is None)
  assert_true(store.component_reader is None)
  assert_true(store.component_writer is None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 22L)
  store.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "Bundle hash cleanup retires same context after denial before an Unknown Reader and outer handles" {
  let (store, _, crypto, _) = native_retention_fixture(
    "bundle-hash-reader-unknown",
  )
  let hash = crypto.sha256_hasher().unwrap()
  hash.update(b"unfinished").unwrap()
  let generation = store.root.inspect_generation("artifact").unwrap().unwrap()
  let reader = store.root
    .open_reader_with_custody("artifact", generation)
    .unwrap()
  store.component_hasher = Some(hash)
  assert_eq(crypto.close_checked(), Err(@signature.CleanupPending))
  assert_true(hash.update(b"later") is Err(_))
  assert_true(bundle_copy_lose_reader_close_observation(reader))
  assert_true(
    close_bundle_component_reader(store, original_reader=Some(reader))
    is Err(Filesystem(@filesystem.Read(_))),
  )
  assert_true(store.component_hasher is None)
  assert_true(
    store.component_reader is Some(same) && physical_equal(same, reader),
  )
  // Actual explicit EVP-context retirement can release this Library's own
  // handle even while the independent Reader/DB/Store duty remains pending.
  crypto.close_checked().unwrap()
  assert_true(store.close_checked() is Err(Filesystem(@filesystem.Read(_))))
  assert_eq(bundle_close_database_attempts(store.database), 0)
  assert_false(store.closed)
}
