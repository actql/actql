///|
fn retained_recovery_test_open(
  name : String,
) -> (StoppedReleaseRecovery, String) raise {
  let (installed, path) = control_bundle_test_open(name)
  let installer = control_bundle_test_install(installed, "1")
  installer.append(b"runtime-one").unwrap()
  installer.seal().unwrap() |> ignore
  installed.activate(control_bundle_test_cid("1")).unwrap() |> ignore
  installed.close_checked().unwrap()
  let matches = recovery_open_test_matches(
    path,
    path + "/dispatch.sqlite3",
    control_bundle_test_cid("1"),
  )
  let slot = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let owner = open_release_recovery_with_custody(
    matches,
    recovery_open_test_environment(matches),
    slot,
    "original-retained-recovery",
  ).unwrap()
  (owner, path)
}

///|
/// These exercise actual constructor and parent-handle ordering only. The
/// fixture Libraries are not an installed Resident; no saved Run, whole-Host
/// stop, reclaimed capacity or Effect cleanup admission is established here.
test "retained recovery keeps failed Transfer Journal custody through pending parent retirement" {
  let (owner, path) = retained_recovery_test_open("retained-failed-transfer")
  let (root, root_path) = orphan_store_test_root("retained-failed-transfer")
  root.create_directory("journal-is-directory").unwrap() |> ignore
  let resources = new_holder_partial_output_resources()
  resources.retained_root = Some(root)
  let failed = match
    @transfer_journal.open_journal_with_custody(
      owner.environment.sqlite_library,
      root_path + "/journal-is-directory",
      262144L,
      16,
      4096,
      1048576L,
    ) {
    Err(CleanupRequired(original)) => original
    _ => {
      fail("expected actual failed Transfer Journal constructor custody")
      abort("unexpected Transfer Journal constructor")
    }
  }
  resources.failed_transfer_journal = Some(failed)
  assert_true(
    failed.issue() is @transfer_journal.Physical(@sqlite.DatabaseOpen(_)),
  )
  let installer = control_bundle_test_install(owner.bundles, "2")
  let original = partial_output_recovery_cleanup(
    resources,
    owner,
    owner.slot,
    "original Transfer Journal acquisition failed",
  )
  assert_true(
    original.resources.failed_transfer_journal is Some(same) &&
    physical_equal(same, failed),
  )
  assert_false(retry_partial_output_recovery_cleanup(original))
  assert_eq(original.step.val, 3)
  assert_true(resources.failed_transfer_journal is None)
  assert_true(resources.retained_root is None)
  assert_eq(owner.slot.verify_current_hold(), Ok(()))
  assert_false(owner.physical_cleanup_done)
  assert_true(owner.terminal_close is RecoveryTerminalOpen)
  assert_false(retry_partial_output_recovery_cleanup(original))
  assert_eq(original.step.val, 3)
  installer.cancel().unwrap()
  assert_true(retry_partial_output_recovery_cleanup(original))
  assert_eq(original.step.val, 5)
  assert_eq(original.failure, "original Transfer Journal acquisition failed")
  assert_true(
    failed.issue() is @transfer_journal.Physical(@sqlite.DatabaseOpen(_)),
  )
  assert_false(owner.physical_cleanup_done)
  assert_true(owner.terminal_close is RecoveryTerminalOpen)
  let independent = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(independent.try_acquire().unwrap())
  assert_true(independent.close())
}

///|
test "retained recovery finishes same child callback before parents and never repeats its observed ACK" {
  let (owner, path) = retained_recovery_test_open("retained-callback-order")
  let (root, root_path) = orphan_store_test_root("retained-callback-order")
  let writer = root.create_writer("reader-stage", 1L).unwrap()
  writer.append(b"x").unwrap()
  writer.seal("borrowed").unwrap() |> ignore
  let generation = root.inspect_generation("borrowed").unwrap().unwrap()
  let reader = root.open_reader("borrowed", generation).unwrap()
  let transfer = @transfer_journal.open_journal_with_custody(
    owner.environment.sqlite_library,
    root_path + "/transfer.sqlite3",
    262144L,
    16,
    4096,
    1048576L,
  ).unwrap()
  let resources = new_holder_partial_output_resources()
  resources.retained_root = Some(root)
  resources.transfer_journal = Some(transfer)
  let (child, _) = control_bundle_test_open("retained-callback-child")
  let child_installer = control_bundle_test_install(child, "1")
  let parent_installer = control_bundle_test_install(owner.bundles, "2")
  let calls = Ref(0)
  // A local caller-ordering diagnostic backed by actual pending Store and
  // Reader handles, not a substitute for the Core-admitted Effect callback.
  owner.physical_cleanup = Some(() => {
    calls.val += 1
    guard resources.retained_root is Some(same) &&
      physical_equal(same, root) &&
      resources.transfer_journal is Some(same) &&
      physical_equal(same, transfer) &&
      owner.slot.verify_current_hold() == Ok(()) &&
      owner.journal.recover_after("") is Ok(None) else {
      return false
    }
    guard child.close_checked() is Ok(_) else { return false }
    reader.close() is Ok(_)
  })
  let original = partial_output_recovery_cleanup(
    resources,
    owner,
    owner.slot,
    "original child cleanup pending",
  )
  assert_false(retry_partial_output_recovery_cleanup(original))
  assert_eq(original.step.val, 0)
  assert_eq(calls.val, 1)
  assert_true(
    resources.retained_root is Some(same) && physical_equal(same, root),
  )
  assert_true(
    resources.transfer_journal is Some(same) && physical_equal(same, transfer),
  )
  assert_eq(owner.slot.verify_current_hold(), Ok(()))
  child_installer.cancel().unwrap()
  assert_false(retry_partial_output_recovery_cleanup(original))
  assert_eq(original.step.val, 3)
  assert_eq(calls.val, 2)
  assert_true(resources.retained_root is None)
  assert_true(resources.transfer_journal is None)
  assert_eq(owner.slot.verify_current_hold(), Ok(()))
  assert_false(retry_partial_output_recovery_cleanup(original))
  assert_eq(calls.val, 2)
  parent_installer.cancel().unwrap()
  assert_true(retry_partial_output_recovery_cleanup(original))
  assert_true(retry_partial_output_recovery_cleanup(original))
  assert_eq(calls.val, 2)
  assert_eq(original.failure, "original child cleanup pending")
  assert_false(owner.physical_cleanup_done)
  assert_true(owner.terminal_close is RecoveryTerminalOpen)
  let independent = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(independent.try_acquire().unwrap())
  assert_true(independent.close())
}
