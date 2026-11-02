///|
/// Physical constructor/close controls with test Libraries only. These do not
/// run an installed command, issue Run release, establish Effect cleanup or
/// acknowledge an original holder's physical stop.
test "release command keeps failed Store and earlier recovery parents until checked retirement" {
  let (owner, slot_root) = retained_recovery_test_open(
    "release-command-store-failure",
  )
  let (root, path) = orphan_store_test_root("release-command-store-failure")
  let occupied = root
    .acquire_lock_with_custody(".actql-publication.lock")
    .unwrap()
  let resources = new_holder_partial_output_resources()
  let settings : ControlOrphanStoreSettings = {
    root: path,
    authority_cid: cleanup_test_cid("a".repeat(64)),
    capacity_bytes: 4096L,
  }
  assert_true(
    open_release_command_store(owner.environment, resources, settings) is None,
  )
  let original = resources.failed_store.unwrap()
  assert_true(original.issue() is Filesystem(@filesystem.Lock(_)))
  assert_true(
    open_release_command_store(owner.environment, resources, {
      ..settings,
      root: path + "/must-not-open",
    })
    is None,
  )
  assert_eq(root.inspect_generation("must-not-open").unwrap(), None)
  let installer = control_bundle_test_install(owner.bundles, "2")
  let pending = partial_output_recovery_cleanup(
    resources,
    owner,
    owner.slot,
    "original release Store failed",
  )
  assert_false(retry_partial_output_recovery_cleanup(pending))
  assert_eq(pending.step.val, 3)
  assert_true(resources.failed_store is None)
  assert_true(original.issue() is Filesystem(@filesystem.Lock(_)))
  assert_eq(owner.slot.verify_current_hold(), Ok(()))
  let foreign = match
    root.acquire_lock_with_custody(".actql-publication.lock") {
    Err(failed) => failed
    Ok(_) => {
      fail("release failure cleanup unlocked another Store")
      abort("foreign Store Lock lost")
    }
  }
  foreign.retry_cleanup().unwrap()
  installer.cancel().unwrap()
  assert_true(retry_partial_output_recovery_cleanup(pending))
  assert_eq(pending.failure, "original release Store failed")
  assert_false(owner.physical_cleanup_done)
  assert_true(owner.terminal_close is RecoveryTerminalOpen)
  let next = @slot.open_native_executor_slot(slot_root + "/original.slot").unwrap()
  assert_true(next.try_acquire().unwrap())
  assert_true(next.close())
  occupied.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "release command reuses actual terminal close observation without reclosing replacement Slot" {
  let (owner, path) = retained_recovery_test_open(
    "release-command-terminal-observation",
  )
  owner.bundles.close_checked().unwrap()
  owner.bundle_closed = true
  // Seed only the private local handle step to exercise its stated input.
  // No Core terminal selection, durable transition or Run success is proved.
  owner.terminal_close = RecoveryTerminalJournal
  let retained = Ref(Some(owner))
  assert_true(retry_stopped_recovery_terminal_close(owner, retained))
  assert_true(retained.val is None)
  assert_true(owner.terminal_close is RecoveryTerminalClosed)
  let replacement = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(replacement.try_acquire().unwrap())
  let terminal = partial_output_recovery_cleanup(
    new_holder_partial_output_resources(),
    owner,
    owner.slot,
    "recorded original terminal close",
  )
  assert_true(retry_partial_output_recovery_cleanup(terminal))
  assert_true(retry_partial_output_recovery_cleanup(terminal))
  assert_eq(replacement.verify_current_hold(), Ok(()))
  assert_false(owner.physical_cleanup_done)
  assert_true(replacement.close())
}

///|
test "release command retires failed input construction without marking original Run released" {
  let (owner, path) = retained_recovery_test_open(
    "release-command-input-failure",
  )
  let (fixture, input_path) = orphan_store_test_root(
    "release-command-input-failure",
  )
  assert_true(
    stopped_holder_cleanup_resources(
      owner,
      input_path + "/transfer.sqlite3",
      Some(input_path + "/missing-root"),
    )
    is None,
  )
  let original = owner.input_cleanup_resources.failed_root.unwrap()
  let retained = Ref(Some(owner))
  retire_failed_stopped_holder_input_constructor(owner, retained)
  assert_true(retained.val is None)
  assert_true(original.issue() is @filesystem.RootOpen(_))
  assert_true(owner.input_cleanup_resources.failed_root is None)
  assert_true(owner.transfer_journal is None)
  assert_false(owner.physical_cleanup_done)
  assert_true(owner.terminal_close is RecoveryTerminalOpen)
  let next = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(next.try_acquire().unwrap())
  assert_true(next.close())
  let saved = fresh_journal(owner.environment).unwrap()
  assert_true(saved.recover_after("").unwrap() is None)
  retain_control_replay_journal_close(saved)
  fixture.close().unwrap()
}

///|
test "release command observation closes original ready Journal and keeps saved row unchanged" {
  let (library, journal, request, path, _) = cleanup_test_open(
    "release-command-reader",
  )
  journal.accept(request).unwrap() |> ignore
  retain_control_replay_journal_close(journal)
  let environment = replay_journal_test_environment(library, path)
  // This fresh fixture intentionally has metadata but no dispatch envelope.
  // The actual caller must retire that reader on its unavailable result too.
  assert_true(
    accepted_request(environment, "release-command-reader", [0]) is None,
  )
  let saved = fresh_journal(environment).unwrap()
  assert_eq(
    @remote.dispatch_record_revision(saved.require(request).unwrap()),
    0,
  )
  assert_false(saved.cancellation_requested(request).unwrap())
  assert_true(saved.output_report_after("").unwrap() is None)
  retain_control_replay_journal_close(saved)
}
