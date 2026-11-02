///|
/// Actual constructor and caller-retirement controls only. Test Libraries and
/// local handle callbacks do not admit an Effect cleanup, a saved Run release,
/// a selected installed Resident or a whole-Host physical stop.
test "stopped holder resources retain original failed Transfer Journal instead of another acquisition" {
  let (owner, _) = retained_recovery_test_open(
    "stopped-holder-transfer-failure",
  )
  let (root, path) = orphan_store_test_root("stopped-holder-transfer-failure")
  root.create_directory("journal-is-directory").unwrap() |> ignore
  let transfer_path = path + "/journal-is-directory"
  assert_true(
    stopped_holder_cleanup_resources(owner, transfer_path, Some(path)) is None,
  )
  let original = owner.input_cleanup_resources.failed_transfer_journal.unwrap()
  assert_true(
    original.issue() is @transfer_journal.Physical(@sqlite.DatabaseOpen(_)),
  )
  assert_true(owner.transfer_journal is None)
  assert_true(owner.input_cleanup_resources.retained_root is None)
  assert_true(owner.input_cleanup_resources.failed_root is None)
  assert_true(
    stopped_holder_cleanup_resources(
      owner,
      path + "/foreign.sqlite3",
      Some(path),
    )
    is None,
  )
  assert_eq(root.inspect_generation("foreign.sqlite3").unwrap(), None)
  assert_true(
    stopped_holder_cleanup_resources(owner, transfer_path, Some(path)) is None,
  )
  assert_true(
    owner.input_cleanup_resources.failed_transfer_journal is Some(same) &&
    physical_equal(same, original),
  )
  assert_false(retry_stopped_holder_cleanup_handles(owner))
  assert_false(owner.physical_cleanup_done)
  assert_eq(owner.input_cleanup_step.val, 0)
  assert_eq(owner.slot.verify_current_hold(), Ok(()))
  let cleanup = partial_output_recovery_cleanup(
    new_holder_partial_output_resources(),
    owner,
    owner.slot,
    "original stopped-holder Transfer Journal failed",
  )
  assert_true(retry_partial_output_recovery_cleanup(cleanup))
  assert_false(owner.physical_cleanup_done)
  assert_true(owner.terminal_close is RecoveryTerminalOpen)
  assert_true(
    original.issue() is @transfer_journal.Physical(@sqlite.DatabaseOpen(_)),
  )
  root.close().unwrap()
}

///|
test "stopped holder resources retain failed Root and the same earlier Transfer Journal" {
  let (owner, _) = retained_recovery_test_open("stopped-holder-root-failure")
  let (root, path) = orphan_store_test_root("stopped-holder-root-failure")
  let transfer_path = path + "/transfer.sqlite3"
  let original_root_path = path + "/missing-root"
  assert_true(
    stopped_holder_cleanup_resources(
      owner,
      transfer_path,
      Some(original_root_path),
    )
    is None,
  )
  let original = owner.input_cleanup_resources.failed_root.unwrap()
  assert_true(original.issue() is @filesystem.RootOpen(_))
  let transfers = owner.transfer_journal.unwrap()
  // Changing the owned fixture after failure cannot turn the failed original
  // constructor into a ready Root or replace it through the same command.
  root.create_directory("missing-root").unwrap() |> ignore
  assert_true(
    stopped_holder_cleanup_resources(
      owner,
      transfer_path,
      Some(original_root_path),
    )
    is None,
  )
  assert_true(
    stopped_holder_cleanup_resources(owner, transfer_path, Some(path)) is None,
  )
  assert_true(owner.input_cleanup_resources.retained_root is None)
  assert_true(
    owner.input_cleanup_resources.failed_root is Some(same) &&
    physical_equal(same, original),
  )
  assert_true(
    owner.transfer_journal is Some(same) && physical_equal(same, transfers),
  )
  assert_false(retry_stopped_holder_cleanup_handles(owner))
  assert_false(owner.physical_cleanup_done)
  assert_eq(owner.slot.verify_current_hold(), Ok(()))
  let cleanup = partial_output_recovery_cleanup(
    new_holder_partial_output_resources(),
    owner,
    owner.slot,
    "original stopped-holder Root failed",
  )
  assert_true(retry_partial_output_recovery_cleanup(cleanup))
  assert_true(owner.transfer_journal is None)
  assert_true(owner.input_cleanup_resources.failed_root is None)
  assert_true(original.issue() is @filesystem.RootOpen(_))
  assert_false(owner.physical_cleanup_done)
  root.close().unwrap()
}

///|
test "stopped holder callback ACK remains once across original input and terminal parent cleanup" {
  let (owner, path) = retained_recovery_test_open(
    "stopped-holder-callback-order",
  )
  let (fixture, root_path) = orphan_store_test_root(
    "stopped-holder-callback-order",
  )
  fixture.close().unwrap()
  let (transfers, root) = stopped_holder_cleanup_resources(
    owner,
    root_path + "/transfer.sqlite3",
    Some(root_path),
  ).unwrap()
  let root = root.unwrap()
  let (same_transfers, same_root) = stopped_holder_cleanup_resources(
    owner,
    root_path + "/transfer.sqlite3",
    Some(root_path),
  ).unwrap()
  assert_true(physical_equal(transfers, same_transfers))
  assert_true(physical_equal(root, same_root.unwrap()))
  // Even ready handles cannot stand in for the original admitted callback.
  assert_false(retry_stopped_holder_cleanup_handles(owner))
  assert_false(owner.physical_cleanup_done)
  let writer = root.create_writer("reader-stage", 1L).unwrap()
  writer.append(b"x").unwrap()
  writer.seal("borrowed").unwrap() |> ignore
  let reader = root
    .open_reader(
      "borrowed",
      root.inspect_generation("borrowed").unwrap().unwrap(),
    )
    .unwrap()
  let (child, _) = control_bundle_test_open("stopped-holder-callback-child")
  let child_installer = control_bundle_test_install(child, "1")
  let parent_installer = control_bundle_test_install(owner.bundles, "2")
  let calls = Ref(0)
  // This local diagnostic closes real pending resources. It supplies no
  // authority in production; settle_stopped_holder_custody admits that port.
  owner.physical_cleanup = Some(() => {
    calls.val += 1
    guard child.close_checked() is Ok(_) else { return false }
    reader.close() is Ok(_)
  })
  assert_false(retry_stopped_holder_cleanup_handles(owner))
  assert_eq(owner.input_cleanup_step.val, 0)
  assert_eq(calls.val, 1)
  assert_true(
    owner.input_cleanup_resources.retained_root is Some(same) &&
    physical_equal(same, root),
  )
  assert_true(
    owner.transfer_journal is Some(same) && physical_equal(same, transfers),
  )
  assert_false(owner.physical_cleanup_done)
  child_installer.cancel().unwrap()
  assert_true(retry_stopped_holder_cleanup_handles(owner))
  assert_eq(calls.val, 2)
  assert_eq(owner.input_cleanup_step.val, 3)
  assert_true(owner.input_cleanup_resources.retained_root is None)
  assert_true(owner.transfer_journal is None)
  assert_true(owner.physical_cleanup_done)
  assert_true(owner.terminal_close is RecoveryTerminalOpen)
  assert_eq(owner.slot.verify_current_hold(), Ok(()))
  let terminal = partial_output_recovery_cleanup(
    new_holder_partial_output_resources(),
    owner,
    owner.slot,
    "original terminal parent still pending",
  )
  assert_false(retry_partial_output_recovery_cleanup(terminal))
  assert_eq(terminal.step.val, 3)
  assert_eq(calls.val, 2)
  parent_installer.cancel().unwrap()
  assert_true(retry_partial_output_recovery_cleanup(terminal))
  assert_true(retry_stopped_holder_cleanup_handles(owner))
  assert_eq(calls.val, 2)
  assert_eq(terminal.failure, "original terminal parent still pending")
  let independent = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(independent.try_acquire().unwrap())
  assert_true(independent.close())
}
