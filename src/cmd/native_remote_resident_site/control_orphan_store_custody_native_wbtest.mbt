///|
fn orphan_store_test_root(name : String) -> (@filesystem.Root, String) {
  let parent_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_root_with_custody(parent_path).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  let root = parent.open_child(name).unwrap()
  parent.close().unwrap()
  (root, parent_path + "/" + name)
}

///|
/// Actual constructor/handle custody, not a Run release, publication ACK,
/// selected installed Resident, current dispatch or physical child stop.
test "orphan Store failure retains original cleanup and does not replace its Journal or Slot" {
  let (library, journal, request, journal_path, _) = cleanup_test_open(
    "orphan-store-open-failure",
  )
  journal.accept(request).unwrap() |> ignore
  let environment = replay_journal_test_environment(library, journal_path)
  let (root, path) = orphan_store_test_root("orphan-occupied-store")
  let occupied = root
    .acquire_lock_with_custody(".actql-publication.lock")
    .unwrap()
  let slot = @slot.open_native_executor_slot(path + ".slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let settings : ControlOrphanStoreSettings = {
    root: path,
    authority_cid: cleanup_test_cid("a".repeat(64)),
    capacity_bytes: 4096L,
  }
  let failed : Ref[@publication_store.NativePublicationStoreOpenFailure?] = Ref(
    None,
  )
  assert_true(open_control_orphan_store(environment, settings, failed) is None)
  let original = failed.val.unwrap()
  let issue = match original.issue() {
    Filesystem(@filesystem.Lock(message)) => message
    _ => {
      fail("expected the original competing Store Lock failure")
      abort("wrong original issue")
    }
  }
  let foreign : ControlOrphanStoreSettings = {
    ..settings,
    root: path + "/must-not-be-opened",
  }
  assert_true(open_control_orphan_store(environment, foreign, failed) is None)
  assert_true(failed.val is Some(same) && physical_equal(same, original))
  assert_eq(root.inspect_generation("must-not-be-opened").unwrap(), None)
  assert_eq(slot.verify_current_hold(), Ok(()))
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    0,
  )
  let retained = Ref(Some(ReplayJournalHandle(journal)))
  assert_true(retry_control_orphan_store_cleanup(failed, retained, slot))
  assert_true(failed.val is None)
  assert_true(retained.val is None)
  assert_true(
    original.issue() is Filesystem(@filesystem.Lock(message)) &&
    message == issue,
  )
  // The failed Store's cleanup cannot unlock the genuinely occupied Store.
  let still_occupied = match
    root.acquire_lock_with_custody(".actql-publication.lock") {
    Err(failure) => failure
    Ok(_) => {
      fail("failed orphan constructor released the foreign Store Lock")
      abort("unexpected Lock")
    }
  }
  still_occupied.retry_cleanup().unwrap()
  let independent = @slot.open_native_executor_slot(path + ".slot").unwrap()
  assert_true(independent.try_acquire().unwrap())
  assert_true(independent.close())
  let same_journal = open_control_replay_journal(environment, retained).unwrap()
  assert_eq(
    @remote.dispatch_record_revision(same_journal.require(request).unwrap()),
    0,
  )
  assert_true(retry_control_replay_journal_cleanup(retained))
  assert_true(retained.val is None)
  occupied.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "orphan reclaim keeps its actual Store and Slot until the original active Writer closes" {
  let (library, journal, request, journal_path, _) = cleanup_test_open(
    "orphan-store-active-writer",
  )
  journal.accept(request).unwrap() |> ignore
  journal.close_checked().unwrap()
  let environment = replay_journal_test_environment(library, journal_path)
  let (root, path) = orphan_store_test_root("orphan-active-store")
  let slot = @slot.open_native_executor_slot(path + ".slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let settings : ControlOrphanStoreSettings = {
    root: path,
    authority_cid: cleanup_test_cid("a".repeat(64)),
    capacity_bytes: 4096L,
  }
  let failed : Ref[@publication_store.NativePublicationStoreOpenFailure?] = Ref(
    None,
  )
  let opened = open_control_orphan_store(environment, settings, failed)
  assert_true(opened is Some(_))
  let store = opened.unwrap()
  let payload = @payload.prepare_publication_payload_request(
    settings.authority_cid,
    cleanup_test_cid("1".repeat(64)),
    cleanup_test_cid("2".repeat(64)),
    cleanup_test_cid("3".repeat(64)),
    cleanup_test_cid("4".repeat(64)),
    cleanup_test_cid("5".repeat(64)),
    cleanup_test_cid("6".repeat(64)),
    cleanup_test_cid("7".repeat(64)),
    8L,
    1L,
  ).unwrap()
  let writer = store.begin_payload(payload).unwrap()
  writer.append(b"x").unwrap()
  let retained : Ref[ControlReplayJournalCustody?] = Ref(None)
  let observed = reclaim_orphaned_outputs(
    settings,
    environment,
    slot,
    Some(store),
    retained,
    failed,
  )
  assert_true(observed is OrphanStoreOpen(same) && physical_equal(same, store))
  assert_true(retained.val is None)
  assert_true(failed.val is None)
  assert_eq(slot.verify_current_hold(), Ok(()))
  writer.cancel().unwrap()
  assert_true(
    reclaim_orphaned_outputs(
      settings,
      environment,
      slot,
      Some(store),
      retained,
      failed,
    )
    is OrphansDone,
  )
  assert_true(retained.val is None)
  let independent = @slot.open_native_executor_slot(path + ".slot").unwrap()
  assert_true(independent.try_acquire().unwrap())
  assert_true(independent.close())
  root.close().unwrap()
  let same_journal = open_control_replay_journal(environment, retained).unwrap()
  assert_eq(
    @remote.dispatch_record_revision(same_journal.require(request).unwrap()),
    0,
  )
  assert_true(retry_control_replay_journal_cleanup(retained))
}

///|
test "orphan Store refusal before acquisition still retires its earlier original Journal and Slot" {
  let (library, journal, request, journal_path, _) = cleanup_test_open(
    "orphan-refused-store",
  )
  journal.accept(request).unwrap() |> ignore
  let environment = replay_journal_test_environment(library, journal_path)
  let (root, path) = orphan_store_test_root("orphan-refused-store")
  let slot = @slot.open_native_executor_slot(path + ".slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let failed : Ref[@publication_store.NativePublicationStoreOpenFailure?] = Ref(
    None,
  )
  let settings : ControlOrphanStoreSettings = {
    root: path,
    authority_cid: cleanup_test_cid("a".repeat(64)),
    capacity_bytes: -1L,
  }
  assert_true(open_control_orphan_store(environment, settings, failed) is None)
  assert_true(failed.val is None)
  assert_eq(root.inspect_generation(".actql-publication.lock").unwrap(), None)
  let retained = Ref(Some(ReplayJournalHandle(journal)))
  retain_control_orphan_reader_cleanup(retained, slot)
  assert_true(retained.val is None)
  let independent = @slot.open_native_executor_slot(path + ".slot").unwrap()
  assert_true(independent.try_acquire().unwrap())
  assert_true(independent.close())
  let same_journal = open_control_replay_journal(environment, retained).unwrap()
  assert_eq(
    @remote.dispatch_record_revision(same_journal.require(request).unwrap()),
    0,
  )
  assert_true(retry_control_replay_journal_cleanup(retained))
  root.close().unwrap()
}
